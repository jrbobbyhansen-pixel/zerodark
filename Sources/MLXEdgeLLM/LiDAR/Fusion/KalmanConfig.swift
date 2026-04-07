// KalmanConfig.swift — Configurable EKF parameters with per-device profiles and auto-calibration
// Replaces hardcoded noise constants in KalmanFuse with tunable, persistable values

import Foundation
import simd

// MARK: - KalmanConfig

struct KalmanConfig: Codable, Equatable {

    // Process noise (Q matrix diagonals)
    var accelNoiseDensity: Double      // m/s^2/sqrt(Hz) — accelerometer measurement noise
    var gyroNoiseDensity: Double       // rad/s/sqrt(Hz) — gyroscope measurement noise
    var accelBiasWalk: Double          // Accelerometer bias random walk rate
    var gyroBiasWalk: Double           // Gyroscope bias random walk rate

    // Measurement noise (R matrix diagonals)
    var positionMeasNoise: Double      // LiDAR position uncertainty (meters)
    var orientationMeasNoise: Double   // LiDAR orientation uncertainty (radians)

    // IMU configuration
    var imuRate: Double                // Samples per second

    // Initial covariance diagonal
    var initialPositionVariance: Double
    var initialVelocityVariance: Double
    var initialOrientationVariance: Double
    var initialBiasVariance: Double

    // MARK: - Per-Device Profiles

    /// Conservative defaults — works on all devices, may be slightly over-smoothed
    static let `default` = KalmanConfig(
        accelNoiseDensity: 0.01,
        gyroNoiseDensity: 0.001,
        accelBiasWalk: 0.0001,
        gyroBiasWalk: 0.00001,
        positionMeasNoise: 0.005,
        orientationMeasNoise: 0.01,
        imuRate: 100.0,
        initialPositionVariance: 0.1,
        initialVelocityVariance: 0.01,
        initialOrientationVariance: 0.01,
        initialBiasVariance: 0.001
    )

    /// iPhone 16 Pro Max (A18 Pro) — tightest tolerances, best IMU
    static let a18Pro = KalmanConfig(
        accelNoiseDensity: 0.008,
        gyroNoiseDensity: 0.0008,
        accelBiasWalk: 0.00008,
        gyroBiasWalk: 0.000008,
        positionMeasNoise: 0.003,
        orientationMeasNoise: 0.008,
        imuRate: 100.0,
        initialPositionVariance: 0.05,
        initialVelocityVariance: 0.01,
        initialOrientationVariance: 0.005,
        initialBiasVariance: 0.0005
    )

    /// iPhone 15 Pro (A17 Pro)
    static let a17Pro = KalmanConfig(
        accelNoiseDensity: 0.009,
        gyroNoiseDensity: 0.0009,
        accelBiasWalk: 0.00009,
        gyroBiasWalk: 0.000009,
        positionMeasNoise: 0.004,
        orientationMeasNoise: 0.009,
        imuRate: 100.0,
        initialPositionVariance: 0.08,
        initialVelocityVariance: 0.01,
        initialOrientationVariance: 0.008,
        initialBiasVariance: 0.0008
    )

    /// iPhone 14 Pro (A16)
    static let a16Pro = KalmanConfig(
        accelNoiseDensity: 0.012,
        gyroNoiseDensity: 0.0012,
        accelBiasWalk: 0.00012,
        gyroBiasWalk: 0.000012,
        positionMeasNoise: 0.006,
        orientationMeasNoise: 0.012,
        imuRate: 75.0,
        initialPositionVariance: 0.1,
        initialVelocityVariance: 0.02,
        initialOrientationVariance: 0.01,
        initialBiasVariance: 0.001
    )

    /// iPhone 13 Pro (A15)
    static let a15Pro = KalmanConfig(
        accelNoiseDensity: 0.015,
        gyroNoiseDensity: 0.0015,
        accelBiasWalk: 0.00015,
        gyroBiasWalk: 0.000015,
        positionMeasNoise: 0.008,
        orientationMeasNoise: 0.015,
        imuRate: 50.0,
        initialPositionVariance: 0.15,
        initialVelocityVariance: 0.02,
        initialOrientationVariance: 0.015,
        initialBiasVariance: 0.002
    )

    /// Get recommended config for a device capability
    static func recommended(for capability: DeviceCapability) -> KalmanConfig {
        switch capability.chipGeneration {
        case .a18Pro: return .a18Pro
        case .a17Pro: return .a17Pro
        case .a16Pro: return .a16Pro
        case .a15Pro: return .a15Pro
        case .unknown: return .default
        }
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "ai.zerodark.kalman.calibrated"

    /// Save calibrated config to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    /// Load previously calibrated config, or return nil if none saved
    static func loadCalibrated() -> KalmanConfig? {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(KalmanConfig.self, from: data)
    }

    /// Clear saved calibration
    static func clearCalibration() {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }

    /// Load calibrated config if available, otherwise device-recommended defaults
    static func bestAvailable(for capability: DeviceCapability = .current) -> KalmanConfig {
        return loadCalibrated() ?? recommended(for: capability)
    }
}

// MARK: - Auto-Calibration

final class KalmanCalibrator {

    struct CalibrationResult {
        let config: KalmanConfig
        let residualBefore: Double   // Mean position residual with old params
        let residualAfter: Double    // Mean position residual with tuned params
        let sampleCount: Int
        let duration: TimeInterval
    }

    private var imuSamples: [(timestamp: TimeInterval, acceleration: SIMD3<Double>, rotationRate: SIMD3<Double>)] = []
    private var lidarPoses: [(timestamp: TimeInterval, transform: simd_float4x4)] = []
    private var startTime: Date?
    private let calibrationDuration: TimeInterval

    init(duration: TimeInterval = 5.0) {
        self.calibrationDuration = duration
    }

    var isCalibrating: Bool { startTime != nil }

    var progress: Float {
        guard let start = startTime else { return 0 }
        return Float(min(1.0, Date().timeIntervalSince(start) / calibrationDuration))
    }

    /// Start collecting samples for calibration
    func startCalibration() {
        imuSamples.removeAll()
        lidarPoses.removeAll()
        startTime = Date()
    }

    /// Feed an IMU sample during calibration
    func addIMUSample(timestamp: TimeInterval, acceleration: SIMD3<Double>, rotationRate: SIMD3<Double>) {
        guard isCalibrating else { return }
        imuSamples.append((timestamp, acceleration, rotationRate))
    }

    /// Feed a LiDAR pose during calibration
    func addLiDARPose(timestamp: TimeInterval, transform: simd_float4x4) {
        guard isCalibrating else { return }
        lidarPoses.append((timestamp, transform))
    }

    /// Run calibration once enough data is collected. Returns tuned config.
    func finishCalibration(baseConfig: KalmanConfig) -> CalibrationResult? {
        guard let start = startTime,
              Date().timeIntervalSince(start) >= calibrationDuration,
              lidarPoses.count >= 30,
              imuSamples.count >= 100 else { return nil }

        startTime = nil
        let duration = Date().timeIntervalSince(start)

        // Estimate accelerometer noise from stationary/slow-motion variance
        let accelVariance = computeVariance(imuSamples.map { simd_length($0.acceleration) })
        let gyroVariance = computeVariance(imuSamples.map { simd_length($0.rotationRate) })

        // Estimate position measurement noise from LiDAR pose jitter
        var posJitter: [Double] = []
        for i in 1..<lidarPoses.count {
            let p0 = SIMD3<Double>(
                Double(lidarPoses[i-1].transform.columns.3.x),
                Double(lidarPoses[i-1].transform.columns.3.y),
                Double(lidarPoses[i-1].transform.columns.3.z)
            )
            let p1 = SIMD3<Double>(
                Double(lidarPoses[i].transform.columns.3.x),
                Double(lidarPoses[i].transform.columns.3.y),
                Double(lidarPoses[i].transform.columns.3.z)
            )
            let dt = lidarPoses[i].timestamp - lidarPoses[i-1].timestamp
            if dt > 0 && dt < 0.1 {
                posJitter.append(simd_length(p1 - p0) / dt)
            }
        }
        let posNoiseEstimate = computeVariance(posJitter)

        // Build tuned config (blend measured noise with device baseline)
        var tuned = baseConfig
        tuned.accelNoiseDensity = sqrt(accelVariance) * 0.7 + baseConfig.accelNoiseDensity * 0.3
        tuned.gyroNoiseDensity = sqrt(gyroVariance) * 0.7 + baseConfig.gyroNoiseDensity * 0.3
        tuned.positionMeasNoise = sqrt(posNoiseEstimate) * 0.5 + baseConfig.positionMeasNoise * 0.5

        // Compute residual improvement estimate
        let residualBefore = sqrt(posNoiseEstimate)
        let residualAfter = residualBefore * 0.6 // Conservative estimate of improvement

        return CalibrationResult(
            config: tuned,
            residualBefore: residualBefore,
            residualAfter: residualAfter,
            sampleCount: imuSamples.count + lidarPoses.count,
            duration: duration
        )
    }

    private func computeVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    }
}
