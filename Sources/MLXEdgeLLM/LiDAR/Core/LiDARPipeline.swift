// LiDARPipeline.swift — Orchestrator for the enhanced LiDAR processing pipeline
// Wires: KalmanFuse → MotionUndistortion → ClutterFilter → YOLO → Haptics
// Includes thermal-adaptive throttling and per-component benchmarking
// All called from LiDARCaptureEngine.session(_:didUpdate:)

import Foundation
import ARKit
import Combine
import simd

// MARK: - Pipeline Configuration

struct LiDARPipelineConfig {
    var enableKalmanFusion: Bool = true
    var enableClutterFilter: Bool = true
    var enableYOLO: Bool = true
    var enableRangeExtension: Bool = true
    var enableHapticOverlay: Bool = true

    /// Auto-configure based on device capability
    static func recommended(for capability: DeviceCapability = .current) -> LiDARPipelineConfig {
        LiDARPipelineConfig(
            enableKalmanFusion: capability.enableKalmanFusion,
            enableClutterFilter: true,
            enableYOLO: capability.enableYOLO,
            enableRangeExtension: capability.enableRangeExtension,
            enableHapticOverlay: true
        )
    }
}

// MARK: - Pipeline Output

struct PipelineFrameResult {
    let timestamp: TimeInterval
    let fusedPose: FusedPose?
    let undistortedPoints: [SIMD3<Float>]
    let filteredCloud: FilteredCloud?
    let yoloDetections: [YOLODetection]
    let extendedPoints: [SIMD3<Float>]
    let processingTimeMs: Double
}

// MARK: - LiDARPipeline

@MainActor
final class LiDARPipeline: ObservableObject {

    // Components
    private let kalman: KalmanFuse
    private let imuBuffer: IMUBuffer
    private let clutterFilter: ClutterFilter
    let yoloDetector: YOLOThreatDetector
    let hapticOverlay: TacticalHapticOverlay
    let personDetector = PersonDetector()
    var gaussianEngine: GaussianSplatEngine?   // internal — allows Gaussian training from LiDARCaptureEngine

    // Thermal monitoring & benchmarking
    let thermalMonitor = ThermalMonitor()
    let benchmark = PipelineBenchmark()
    private var calibrator: KalmanCalibrator?

    // Configuration
    private let baseConfig: LiDARPipelineConfig
    private let capability: DeviceCapability

    // LingBot-Map streaming state config (stride updated by thermal throttle)
    var lingBotMapConfig = VoxelStreamMap.Config()

    // Active display mode (set from LiDARTabView)
    var activeMode: LiDARMode = .full

    // Active throttle state (updated by thermal monitor)
    @Published private(set) var activeThrottleProfile: ThrottleProfile = .nominal
    @Published private(set) var effectiveYOLOFrameSkip: Int = 3
    private var yoloFrameCounter: Int = 0

    // State
    @Published private(set) var isRunning = false
    @Published private(set) var lastFrameResult: PipelineFrameResult?
    @Published private(set) var isCalibrating = false
    @Published private(set) var detectedPeopleCount: Int = 0

    // Frame timestamp tracking for undistortion
    private var previousFrameTimestamp: TimeInterval?
    private var thermalCancellable: AnyCancellable?
    private var snapshotTimer: Timer?

    init(
        config: LiDARPipelineConfig = .recommended(),
        capability: DeviceCapability = .current
    ) {
        self.baseConfig = config
        self.capability = capability

        // Initialize Kalman with best available config (calibrated or device baseline)
        let kalmanConfig = KalmanConfig.bestAvailable(for: capability)
        self.kalman = KalmanFuse(config: kalmanConfig)

        self.imuBuffer = IMUBuffer()
        self.clutterFilter = ClutterFilter()
        self.yoloDetector = YOLOThreatDetector(capability: capability)
        self.hapticOverlay = TacticalHapticOverlay()
        self.effectiveYOLOFrameSkip = capability.yoloFrameSkip

        if config.enableRangeExtension {
            self.gaussianEngine = GaussianSplatEngine(capability: capability)
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isRunning else { return }

        // Start IMU capture for Kalman fusion
        if baseConfig.enableKalmanFusion {
            imuBuffer.onSample = { [weak self] sample in
                self?.kalman.predictIMU(sample: sample)
            }
            imuBuffer.start(rate: capability.kalmanIMURate)
        }

        // Load YOLO model
        if baseConfig.enableYOLO {
            await yoloDetector.loadModel()
        }

        // Start haptic engine
        if baseConfig.enableHapticOverlay {
            hapticOverlay.start()
        }

        // Subscribe to thermal state changes for adaptive throttling
        thermalCancellable = thermalMonitor.$currentProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.applyThrottleProfile(profile)
            }

        // Take benchmark snapshots every second
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.takeBenchmarkSnapshot()
            }
        }

        isRunning = true
        print("[LiDARPipeline] Started — Kalman:\(baseConfig.enableKalmanFusion) YOLO:\(baseConfig.enableYOLO) RangeExt:\(baseConfig.enableRangeExtension) Haptic:\(baseConfig.enableHapticOverlay) Thermal:\(thermalMonitor.currentLevel.description)")
    }

    func stop() {
        imuBuffer.stop()
        hapticOverlay.shutdown()
        thermalCancellable?.cancel()
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        gaussianEngine = nil
        isRunning = false
        kalman.reset()
        benchmark.printReport()
        benchmark.reset()
        print("[LiDARPipeline] Stopped")
    }

    // MARK: - Frame Processing

    /// Main entry point called from LiDARCaptureEngine.session(_:didUpdate:)
    func processFrame(_ frame: ARFrame) -> [SIMD3<Float>] {
        benchmark.startTiming("totalFrame")
        benchmark.recordFrame()
        let frameTimestamp = frame.timestamp

        // 1. Kalman fusion update (LiDAR measurement)
        var fusedPose: FusedPose?
        if baseConfig.enableKalmanFusion {
            benchmark.startTiming("kalmanUpdate")
            kalman.updateLiDAR(pose: frame.camera.transform, timestamp: frameTimestamp)
            fusedPose = kalman.currentPose()
            benchmark.endTiming("kalmanUpdate")

            // Feed calibrator if active
            if let cal = calibrator, cal.isCalibrating {
                cal.addLiDARPose(timestamp: frameTimestamp, transform: frame.camera.transform)
            }
        }

        // 2. YOLO detection (throttled by thermal-adjusted frame skip, gated by mode)
        yoloFrameCounter += 1
        if baseConfig.enableYOLO && activeMode.enablesYOLO && yoloFrameCounter % effectiveYOLOFrameSkip == 0 {
            benchmark.startTiming("yoloInference")
            yoloDetector.processFrame(frame)
            benchmark.endTiming("yoloInference")
        }

        // 2b. Person tracking from YOLO detections
        if baseConfig.enableYOLO && activeMode.enablesYOLO {
            personDetector.update(detections: yoloDetector.activeDetections, timestamp: frameTimestamp)
            detectedPeopleCount = personDetector.peopleCount
        }

        // 3. Feed detections to haptic overlay (gated by mode)
        if baseConfig.enableHapticOverlay && activeMode.enablesHaptics {
            benchmark.startTiming("hapticUpdate")
            hapticOverlay.activeDetections = yoloDetector.activeDetections
            if let pose = fusedPose {
                hapticOverlay.devicePosition = pose.position
            }
            benchmark.endTiming("hapticUpdate")
        } else if !activeMode.enablesHaptics {
            hapticOverlay.stopHaptics()
        }

        // 4. Gaussian splatting range extension
        var extended: [SIMD3<Float>] = []
        if let engine = gaussianEngine, baseConfig.enableRangeExtension && activeThrottleProfile.enableRangeExtension {
            benchmark.startTiming("gaussianExtend")
            extended = engine.extendedPoints(
                cameraTransform: frame.camera.transform,
                intrinsics: frame.camera.intrinsics
            )
            benchmark.endTiming("gaussianExtend")
        }

        previousFrameTimestamp = frameTimestamp
        benchmark.endTiming("totalFrame")

        return extended
    }

    /// Process extracted point cloud through undistortion + clutter filter.
    func processPoints(
        _ points: [SIMD3<Float>],
        intensities: [Float]? = nil,
        frameStartTime: TimeInterval,
        frameEndTime: TimeInterval
    ) -> (filtered: [SIMD3<Float>], ground: [SIMD3<Float>]) {
        var processed = points

        // Undistort using Kalman fused poses
        if baseConfig.enableKalmanFusion {
            processed = benchmark.measure("motionUndistortion") {
                MotionUndistortion.undistort(
                    points: processed,
                    startTime: frameStartTime,
                    endTime: frameEndTime,
                    kalman: kalman
                )
            }
        }

        // Clutter filter (can be disabled by thermal throttling)
        if baseConfig.enableClutterFilter && activeThrottleProfile.enableClutterFilter {
            let result = benchmark.measure("clutterFilter") {
                clutterFilter.filter(points: processed, intensities: intensities)
            }
            return (filtered: result.objectPoints, ground: result.groundPoints)
        }

        return (filtered: processed, ground: [])
    }

    /// Get the fused transform to use instead of raw ARKit transform
    func fusedTransform(at timestamp: TimeInterval) -> simd_float4x4? {
        guard baseConfig.enableKalmanFusion else { return nil }
        return kalman.interpolatedPose(at: timestamp)?.transform
    }

    // MARK: - Thermal-Adaptive Throttling

    private func applyThrottleProfile(_ profile: ThrottleProfile) {
        activeThrottleProfile = profile

        // LingBot-Map voxel fusion stride (1 = full-res, 2 = half, 4 = quarter)
        lingBotMapConfig.voxelFusionStride = profile.voxelFusionStride

        // Adjust YOLO frame skip
        effectiveYOLOFrameSkip = capability.yoloFrameSkip * profile.yoloFrameSkipMultiplier

        // Adjust IMU rate if thermal is serious
        if profile.kalmanIMURateMultiplier < 1.0 && imuBuffer.isRunning {
            let newRate = capability.kalmanIMURate * profile.kalmanIMURateMultiplier
            imuBuffer.stop()
            imuBuffer.start(rate: newRate)
        }

        // Disable/enable range extension
        if !profile.enableRangeExtension && gaussianEngine != nil {
            gaussianEngine = nil
            print("[LiDARPipeline] Gaussian splatting disabled (thermal: \(thermalMonitor.currentLevel.description))")
        } else if profile.enableRangeExtension && gaussianEngine == nil && baseConfig.enableRangeExtension {
            gaussianEngine = GaussianSplatEngine(capability: capability)
            print("[LiDARPipeline] Gaussian splatting re-enabled")
        }

        print("[LiDARPipeline] Throttle applied — YOLO skip:\(effectiveYOLOFrameSkip) GaussIter:\(profile.gaussianIterationsPerFrame) Clutter:\(profile.enableClutterFilter) RangeExt:\(profile.enableRangeExtension)")
    }

    // MARK: - Kalman Calibration

    /// Start a 5-second calibration run to tune Kalman Q/R matrices
    func startCalibration(duration: TimeInterval = 5.0) {
        calibrator = KalmanCalibrator(duration: duration)
        calibrator?.startCalibration()
        isCalibrating = true

        // Also feed IMU samples to calibrator
        let originalHandler = imuBuffer.onSample
        imuBuffer.onSample = { [weak self] sample in
            originalHandler?(sample)
            self?.calibrator?.addIMUSample(
                timestamp: sample.timestamp,
                acceleration: sample.acceleration,
                rotationRate: sample.rotationRate
            )
        }

        print("[LiDARPipeline] Calibration started — hold device steady for \(Int(duration))s")
    }

    /// Finish calibration and apply tuned parameters
    func finishCalibration() -> KalmanCalibrator.CalibrationResult? {
        guard let cal = calibrator else { return nil }

        let baselineConfig = KalmanConfig.recommended(for: capability)
        let result = cal.finishCalibration(baseConfig: baselineConfig)

        if let result {
            result.config.save()
            print("[LiDARPipeline] Calibration complete — residual improved \(String(format: "%.1f", result.residualBefore * 1000))mm → \(String(format: "%.1f", result.residualAfter * 1000))mm")
        }

        calibrator = nil
        isCalibrating = false

        // Restore IMU handler
        imuBuffer.onSample = { [weak self] sample in
            self?.kalman.predictIMU(sample: sample)
        }

        return result
    }

    var calibrationProgress: Float {
        calibrator?.progress ?? 0
    }

    // MARK: - Benchmarking

    private func takeBenchmarkSnapshot() {
        benchmark.takeSnapshot(
            thermalLevel: thermalMonitor.currentLevel,
            gaussianCount: gaussianEngine?.gaussianCount ?? 0,
            pointCloudSize: 0
        )
    }
}
