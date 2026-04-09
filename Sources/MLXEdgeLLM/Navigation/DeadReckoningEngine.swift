// DeadReckoningEngine.swift — IMU-based dead reckoning with ZUPT
// Targets: <50m error over 10 minutes, no-mag urban heading fallback

import Foundation
import SwiftUI
import CoreLocation
import CoreMotion

// MARK: - DeadReckoningEngine

@MainActor
final class DeadReckoningEngine: ObservableObject {
    static let shared = DeadReckoningEngine()

    @Published var heading: CLLocationDirection = 0
    @Published var paceCount: Int = 0
    @Published var estimatedPosition: CLLocationCoordinate2D?
    @Published var confidenceRadius: CLLocationDistance = 0
    @Published var zuptCount: Int = 0
    @Published var isActive: Bool = false

    private var lastKnownPosition: CLLocationCoordinate2D?
    private var velocity: SIMD3<Double> = .zero  // NED frame (m/s)
    private var position: SIMD3<Double> = .zero  // NED offset from lastKnownPosition (meters)

    // IMU
    private let motionManager = CMMotionManager()
    private var lastIMUTime: TimeInterval = 0

    // ZUPT detection
    private let zuptWindowSize = 40         // 200Hz * 0.2s = 40 samples
    private let zuptVarianceThreshold: Double = 0.05  // m/s^2 variance threshold
    private var accelMagnitudeBuffer: [Double] = []
    private var isStationary: Bool = true

    // No-mag heading
    private var gyroHeading: Double = 0     // radians, gyro-integrated
    private var urbanBiasDetected: Bool = false

    // Confidence model
    private let maxConfidenceGrowthRate: Double = 0.08  // m/s without ZUPT (<50m in 10min)
    private let zuptConfidenceResetFraction: Double = 0.3  // retain 30% after ZUPT
    private var lastConfidenceUpdateTime: TimeInterval = 0

    // Step detection
    private var lastAccelPeak: Double = 0
    private var stepDetectionPhase: StepPhase = .waiting
    private let stepThresholdHigh: Double = 1.2  // g threshold for step peak
    private let stepThresholdLow: Double = 0.8   // g threshold for step valley
    private let paceDistance: CLLocationDistance = 0.762

    private enum StepPhase {
        case waiting, peakDetected
    }

    init() {}

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start(from position: CLLocationCoordinate2D, heading initialHeading: Double) {
        lastKnownPosition = position
        heading = initialHeading
        gyroHeading = initialHeading * .pi / 180.0
        self.position = .zero
        velocity = .zero
        confidenceRadius = 0
        paceCount = 0
        zuptCount = 0
        accelMagnitudeBuffer = []
        isActive = true
        lastConfidenceUpdateTime = ProcessInfo.processInfo.systemUptime

        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 200.0  // 200Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            self?.processIMU(motion)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isActive = false
    }

    /// Set anchor position from external GPS fix (e.g. BreadcrumbEngine)
    func resetAnchor(position: CLLocationCoordinate2D, heading newHeading: Double) {
        lastKnownPosition = position
        self.position = .zero
        velocity = .zero
        heading = newHeading
        gyroHeading = newHeading * .pi / 180.0
        confidenceRadius = 0
    }

    // MARK: - IMU Processing

    private func processIMU(_ motion: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastIMUTime
        guard lastIMUTime > 0, dt > 0, dt < 0.1 else {
            lastIMUTime = now
            return
        }
        lastIMUTime = now

        // --- Heading update ---
        updateHeading(motion)

        // --- Accelerometer magnitude for ZUPT + step detection ---
        let ax = motion.userAcceleration.x
        let ay = motion.userAcceleration.y
        let az = motion.userAcceleration.z

        // Full DCM rotation to NED
        let rm = motion.attitude.rotationMatrix
        let aN = rm.m11 * ax + rm.m12 * ay + rm.m13 * az
        let aE = rm.m21 * ax + rm.m22 * ay + rm.m23 * az
        let aD = rm.m31 * ax + rm.m32 * ay + rm.m33 * az

        let accelMag = sqrt(ax * ax + ay * ay + az * az)
        accelMagnitudeBuffer.append(accelMag)
        if accelMagnitudeBuffer.count > zuptWindowSize {
            accelMagnitudeBuffer.removeFirst()
        }

        // --- ZUPT detection ---
        detectZUPT()

        // --- Step detection (pace counting) ---
        detectStep(accelMag: accelMag + 1.0)  // +1.0 to include gravity magnitude

        // --- Dead reckoning integration ---
        if !isStationary {
            // Integrate acceleration → velocity (NED, m/s^2)
            velocity.x += aN * 9.81 * dt
            velocity.y += aE * 9.81 * dt
            velocity.z += aD * 9.81 * dt

            // Clamp velocity to reasonable walking/running speed (max 5 m/s)
            let hSpeed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
            if hSpeed > 5.0 {
                let scale = 5.0 / hSpeed
                velocity.x *= scale
                velocity.y *= scale
            }
        }

        // Integrate velocity → position offset
        position.x += velocity.x * dt
        position.y += velocity.y * dt

        // --- Update confidence radius ---
        let timeSinceConfUpdate = now - lastConfidenceUpdateTime
        if timeSinceConfUpdate > 0 {
            confidenceRadius += maxConfidenceGrowthRate * timeSinceConfUpdate
            lastConfidenceUpdateTime = now
        }

        // --- Update published position ---
        updateEstimatedPosition()
    }

    // MARK: - Heading (no-mag fallback)

    private func updateHeading(_ motion: CMDeviceMotion) {
        let dt = motionManager.deviceMotionUpdateInterval

        // Detect urban magnetic bias
        let magAccuracy = motion.magneticField.accuracy
        urbanBiasDetected = (magAccuracy == .uncalibrated || magAccuracy.rawValue < 0)

        if urbanBiasDetected {
            // Pure gyro integration — accumulate yaw from rotation rate
            gyroHeading += motion.rotationRate.z * dt
            // Wrap to [0, 2*pi]
            gyroHeading = gyroHeading.truncatingRemainder(dividingBy: 2 * .pi)
            if gyroHeading < 0 { gyroHeading += 2 * .pi }

            heading = gyroHeading * 180.0 / .pi
        } else {
            // Magnetometer available — use fused heading
            let fusedHeading = motion.attitude.yaw
            var headingDeg = fusedHeading * 180.0 / .pi
            if headingDeg < 0 { headingDeg += 360.0 }
            heading = headingDeg
            gyroHeading = fusedHeading  // Keep gyro synced for seamless fallback
        }

        // Drift correction from BreadcrumbEngine EKF heading if available
        if let ekfHeading = BreadcrumbEngine.shared.fusedNavPose?.heading, !urbanBiasDetected {
            let ekfRad = ekfHeading * .pi / 180.0
            let innovation = atan2(sin(ekfRad - gyroHeading), cos(ekfRad - gyroHeading))
            gyroHeading += innovation * 0.01  // Gentle correction
        }
    }

    // MARK: - ZUPT Detection

    private func detectZUPT() {
        guard accelMagnitudeBuffer.count >= zuptWindowSize else { return }

        // Compute variance of accelerometer magnitude over window
        let mean = accelMagnitudeBuffer.reduce(0, +) / Double(accelMagnitudeBuffer.count)
        let variance = accelMagnitudeBuffer.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(accelMagnitudeBuffer.count)

        let wasStationary = isStationary

        // Correlate with step detection: ZUPT only valid during walking gait
        // (foot-plant phase). If no steps detected recently, require even lower
        // variance to avoid false triggers from vehicles/elevators.
        let hasRecentSteps = paceCount > 0
        let effectiveThreshold = hasRecentSteps ? zuptVarianceThreshold : zuptVarianceThreshold * 0.25

        isStationary = variance < effectiveThreshold

        if isStationary && !wasStationary {
            applyZUPT()
        }
    }

    private func applyZUPT() {
        // Zero velocity update — when foot is on ground, velocity must be zero
        velocity = .zero
        zuptCount += 1

        // Reduce confidence radius (ZUPT constrains drift)
        confidenceRadius *= zuptConfidenceResetFraction
    }

    // MARK: - Step Detection

    private func detectStep(accelMag: Double) {
        switch stepDetectionPhase {
        case .waiting:
            if accelMag > stepThresholdHigh {
                stepDetectionPhase = .peakDetected
                lastAccelPeak = accelMag
            }
        case .peakDetected:
            if accelMag < stepThresholdLow {
                stepDetectionPhase = .waiting
                paceCount += 1
            }
        }
    }

    // MARK: - Position Update

    private func updateEstimatedPosition() {
        guard let anchor = lastKnownPosition else { return }

        let mPerDegLat = 111320.0
        let mPerDegLon = 111320.0 * cos(anchor.latitude * .pi / 180.0)

        let newLat = anchor.latitude + position.x / mPerDegLat
        let newLon = anchor.longitude + position.y / max(mPerDegLon, 1.0)

        estimatedPosition = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
    }
}

// MARK: - Extensions

extension CLLocationDirection {
    var degreesToRadians: Double {
        return Double(self) * .pi / 180
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let location1 = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2)
    }
}
