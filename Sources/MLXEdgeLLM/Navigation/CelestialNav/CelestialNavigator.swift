// CelestialNavigator.swift — Celestial navigation system (NASA COTS-Star-Tracker pattern)

import AVFoundation
import Observation

/// Celestial navigator using star detection
@MainActor
public class CelestialNavigator: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published public var estimatedHeading: Double?
    @Published public var detectedStarCount: Int = 0
    @Published public var isSessionRunning: Bool = false

    private let captureSession = AVCaptureSession()
    private let detector = StarDetector()
    private let solver = AttitudeSolver()
    private let catalog = StarCatalog.shared
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.zerodark.celestial")

    public override init() {
        super.init()
    }

    /// Start capture session
    public func startSession() {
        guard !isSessionRunning else { return }

        // Configure session
        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        captureSession.addInput(input)

        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        captureSession.addOutput(output)

        captureSession.startRunning()
        isSessionRunning = true
    }

    /// Stop capture session
    public func stopSession() {
        captureSession.stopRunning()
        isSessionRunning = false
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Detect stars
        let detectedStars = detector.detect(in: pixelBuffer)

        Task { @MainActor [weak self] in
            self?.detectedStarCount = detectedStars.count

            guard detectedStars.count >= 2 else {
                self?.estimatedHeading = nil
                return
            }

            // Get visible catalog stars (simple visibility check)
            let visibleCatalog = (self?.catalog.visibleStars(heading: 0, altitude: 0) ?? []).prefix(detectedStars.count)

            // Solve attitude
            if let quat = self?.solver.solve(detected: detectedStars, catalog: Array(visibleCatalog)) {
                // Convert quaternion to heading
                let heading = self?.quaternionToHeading(quat) ?? 0
                self?.estimatedHeading = heading
            }
        }
    }

    /// Convert quaternion to heading (yaw angle)
    private func quaternionToHeading(_ quat: simd_quatd) -> Double {
        let roll = atan2(2 * (quat.vector.w * quat.vector.x + quat.vector.y * quat.vector.z),
                         1 - 2 * (quat.vector.x * quat.vector.x + quat.vector.y * quat.vector.y))
        let pitch = asin(2 * (quat.vector.w * quat.vector.y - quat.vector.z * quat.vector.x))
        let yaw = atan2(2 * (quat.vector.w * quat.vector.z + quat.vector.x * quat.vector.y),
                        1 - 2 * (quat.vector.y * quat.vector.y + quat.vector.z * quat.vector.z))

        var heading = yaw * 180.0 / .pi
        if heading < 0 {
            heading += 360
        }
        return heading
    }
}
