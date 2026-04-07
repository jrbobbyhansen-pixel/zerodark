// KalmanFuse.swift — Extended Kalman Filter for IMU + LiDAR pose fusion
// 15-state EKF: position(3), velocity(3), quaternion(4), gyro_bias(3), accel_bias(3)
// Produces undistorted pose estimates at IMU rate for point cloud deskewing

import Foundation
import simd
import Accelerate

// MARK: - Fused Pose

struct FusedPose {
    let timestamp: TimeInterval
    let position: SIMD3<Float>
    let velocity: SIMD3<Float>
    let orientation: simd_quatf
    let transform: simd_float4x4

    /// Construct a 4x4 transform from position + orientation
    init(timestamp: TimeInterval, position: SIMD3<Float>, velocity: SIMD3<Float>, orientation: simd_quatf) {
        self.timestamp = timestamp
        self.position = position
        self.velocity = velocity
        self.orientation = orientation

        let rotMatrix = simd_float3x3(orientation)
        self.transform = simd_float4x4(columns: (
            SIMD4<Float>(rotMatrix.columns.0, 0),
            SIMD4<Float>(rotMatrix.columns.1, 0),
            SIMD4<Float>(rotMatrix.columns.2, 0),
            SIMD4<Float>(position, 1)
        ))
    }
}

// MARK: - KalmanFuse

final class KalmanFuse: @unchecked Sendable {

    // State vector (stored as separate components for clarity)
    private var position: SIMD3<Double> = .zero
    private var velocity: SIMD3<Double> = .zero
    private var orientation: simd_quatd = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    private var gyroBias: SIMD3<Double> = .zero
    private var accelBias: SIMD3<Double> = .zero

    // Covariance (15x15, stored as flat array for Accelerate compatibility)
    private var P: [Double]  // 15x15 = 225 elements, row-major

    // Tunable noise parameters (from KalmanConfig)
    private let accelNoiseDensity: Double
    private let gyroNoiseDensity: Double
    private let accelBiasWalk: Double
    private let gyroBiasWalk: Double
    private let positionMeasNoise: Double
    private let orientationMeasNoise: Double

    // Config reference for reset
    private let config: KalmanConfig

    private var lastIMUTimestamp: TimeInterval?
    private var lastLiDARTimestamp: TimeInterval?
    private var isInitialized = false
    private let lock = NSLock()

    // Pose history for interpolation during undistortion
    private var poseHistory: [(timestamp: TimeInterval, pose: FusedPose)] = []
    private let maxHistorySize = 300 // ~3 seconds at 100Hz

    init(config: KalmanConfig = .bestAvailable()) {
        self.config = config
        self.accelNoiseDensity = config.accelNoiseDensity
        self.gyroNoiseDensity = config.gyroNoiseDensity
        self.accelBiasWalk = config.accelBiasWalk
        self.gyroBiasWalk = config.gyroBiasWalk
        self.positionMeasNoise = config.positionMeasNoise
        self.orientationMeasNoise = config.orientationMeasNoise

        // Initialize covariance from config
        P = [Double](repeating: 0, count: 225)
        for i in 0..<3 { P[i * 15 + i] = config.initialPositionVariance }
        for i in 3..<6 { P[i * 15 + i] = config.initialVelocityVariance }
        for i in 6..<10 { P[i * 15 + i] = config.initialOrientationVariance }
        for i in 10..<15 { P[i * 15 + i] = config.initialBiasVariance }
    }

    // MARK: - IMU Prediction Step (called at 100Hz)

    func predictIMU(sample: IMUSample) {
        lock.lock()
        defer { lock.unlock() }

        guard let lastTime = lastIMUTimestamp else {
            lastIMUTimestamp = sample.timestamp
            return
        }

        let dt = sample.timestamp - lastTime
        guard dt > 0 && dt < 0.1 else { // Sanity: skip if gap > 100ms
            lastIMUTimestamp = sample.timestamp
            return
        }
        lastIMUTimestamp = sample.timestamp

        // Bias-corrected IMU readings
        let correctedAccel = sample.acceleration - accelBias
        let correctedGyro = sample.rotationRate - gyroBias

        // Rotate acceleration to world frame
        let rotMatrix = simd_double3x3(orientation)
        let accelWorld = rotMatrix * correctedAccel - SIMD3<Double>(0, 9.81, 0)

        // State propagation
        position += velocity * dt + 0.5 * accelWorld * dt * dt
        velocity += accelWorld * dt

        // Quaternion integration (first-order)
        let omega = correctedGyro
        let omegaNorm = simd_length(omega)
        if omegaNorm > 1e-10 {
            let halfAngle = omegaNorm * dt * 0.5
            let axis = omega / omegaNorm
            let dq = simd_quatd(
                ix: axis.x * sin(halfAngle),
                iy: axis.y * sin(halfAngle),
                iz: axis.z * sin(halfAngle),
                r: cos(halfAngle)
            )
            orientation = (orientation * dq).normalized
        }

        // Propagate covariance: P = F*P*F' + Q
        propagateCovariance(dt: dt, accelWorld: accelWorld)

        // Store pose in history
        let fusedPose = currentFusedPose(at: sample.timestamp)
        appendPoseHistory(sample.timestamp, fusedPose)
    }

    // MARK: - LiDAR Measurement Update (called at ~30Hz)

    func updateLiDAR(pose: simd_float4x4, timestamp: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        if !isInitialized {
            // Initialize state from first LiDAR pose
            let t = SIMD3<Double>(Double(pose.columns.3.x), Double(pose.columns.3.y), Double(pose.columns.3.z))
            position = t
            velocity = .zero
            orientation = simd_quatd(simd_quatf(pose))
            isInitialized = true
            lastLiDARTimestamp = timestamp
            return
        }

        lastLiDARTimestamp = timestamp

        // Extract measurement
        let measPos = SIMD3<Double>(Double(pose.columns.3.x), Double(pose.columns.3.y), Double(pose.columns.3.z))
        let measQuat = simd_quatd(simd_quatf(pose))

        // Position innovation
        let posInnovation = measPos - position

        // Orientation innovation (as rotation vector)
        let dq = measQuat * orientation.conjugate
        let orientInnovation = 2.0 * SIMD3<Double>(dq.imag.x, dq.imag.y, dq.imag.z)

        // Innovation vector (6 elements: pos + orient)
        let innovation = [posInnovation.x, posInnovation.y, posInnovation.z,
                          orientInnovation.x, orientInnovation.y, orientInnovation.z]

        // Measurement matrix H (6x15): observes position (indices 0-2) and orientation (indices 6-8)
        var H = [Double](repeating: 0, count: 6 * 15)
        H[0 * 15 + 0] = 1  // pos.x
        H[1 * 15 + 1] = 1  // pos.y
        H[2 * 15 + 2] = 1  // pos.z
        H[3 * 15 + 6] = 1  // orient.x (approximate)
        H[4 * 15 + 7] = 1  // orient.y
        H[5 * 15 + 8] = 1  // orient.z

        // Measurement noise R (6x6 diagonal)
        var R = [Double](repeating: 0, count: 36)
        for i in 0..<3 { R[i * 6 + i] = positionMeasNoise * positionMeasNoise }
        for i in 3..<6 { R[i * 6 + i] = orientationMeasNoise * orientationMeasNoise }

        // Kalman gain: K = P*H' * (H*P*H' + R)^-1
        let PHt = matMul(P, transpose(H, rows: 6, cols: 15), m: 15, n: 6, k: 15)
        var S = matMul(H, PHt, m: 6, n: 6, k: 15)
        for i in 0..<36 { S[i] += R[i] }

        guard let Sinv = invert6x6(S) else { return }
        let K = matMul(PHt, Sinv, m: 15, n: 6, k: 6)

        // State update: x = x + K * innovation
        var dx = [Double](repeating: 0, count: 15)
        for i in 0..<15 {
            for j in 0..<6 {
                dx[i] += K[i * 6 + j] * innovation[j]
            }
        }

        position += SIMD3<Double>(dx[0], dx[1], dx[2])
        velocity += SIMD3<Double>(dx[3], dx[4], dx[5])

        // Orientation correction
        let dTheta = SIMD3<Double>(dx[6], dx[7], dx[8])
        let dThetaNorm = simd_length(dTheta)
        if dThetaNorm > 1e-12 {
            let axis = dTheta / dThetaNorm
            let corrQuat = simd_quatd(angle: dThetaNorm, axis: axis)
            orientation = (corrQuat * orientation).normalized
        }

        gyroBias += SIMD3<Double>(dx[9], dx[10], dx[11])
        accelBias += SIMD3<Double>(dx[12], dx[13], dx[14])

        // Covariance update: P = (I - K*H) * P
        var KH = matMul(K, H, m: 15, n: 15, k: 6)
        var IminusKH = [Double](repeating: 0, count: 225)
        for i in 0..<15 { IminusKH[i * 15 + i] = 1.0 }
        for i in 0..<225 { IminusKH[i] -= KH[i] }
        let newP = matMul(IminusKH, P, m: 15, n: 15, k: 15)
        P = newP

        // Update pose history
        let fusedPose = currentFusedPose(at: timestamp)
        appendPoseHistory(timestamp, fusedPose)
    }

    // MARK: - Pose Access

    /// Current fused pose (thread-safe)
    func currentPose() -> FusedPose {
        lock.lock()
        defer { lock.unlock() }
        return currentFusedPose(at: lastIMUTimestamp ?? ProcessInfo.processInfo.systemUptime)
    }

    /// Interpolate pose at a specific timestamp from history
    func interpolatedPose(at timestamp: TimeInterval) -> FusedPose? {
        lock.lock()
        defer { lock.unlock() }

        guard poseHistory.count >= 2 else { return poseHistory.first?.pose }

        // Find bracketing poses
        var lower = poseHistory.first!
        var upper = poseHistory.last!

        for entry in poseHistory {
            if entry.timestamp <= timestamp {
                lower = entry
            }
            if entry.timestamp >= timestamp && entry.timestamp < upper.timestamp {
                upper = entry
            }
        }

        if lower.timestamp == upper.timestamp { return lower.pose }

        let t = Float((timestamp - lower.timestamp) / (upper.timestamp - lower.timestamp))
        let interpPos = simd_mix(lower.pose.position, upper.pose.position, SIMD3<Float>(repeating: t))
        let interpVel = simd_mix(lower.pose.velocity, upper.pose.velocity, SIMD3<Float>(repeating: t))
        let interpOri = simd_slerp(lower.pose.orientation, upper.pose.orientation, t)

        return FusedPose(timestamp: timestamp, position: interpPos, velocity: interpVel, orientation: interpOri)
    }

    /// Get pose range for undistortion
    func poseRange(from startTime: TimeInterval, to endTime: TimeInterval) -> [FusedPose] {
        lock.lock()
        defer { lock.unlock() }
        return poseHistory
            .filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
            .map { $0.pose }
    }

    // MARK: - Private Helpers

    private func currentFusedPose(at timestamp: TimeInterval) -> FusedPose {
        FusedPose(
            timestamp: timestamp,
            position: SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z)),
            velocity: SIMD3<Float>(Float(velocity.x), Float(velocity.y), Float(velocity.z)),
            orientation: simd_quatf(
                ix: Float(orientation.imag.x),
                iy: Float(orientation.imag.y),
                iz: Float(orientation.imag.z),
                r: Float(orientation.real)
            )
        )
    }

    private func appendPoseHistory(_ timestamp: TimeInterval, _ pose: FusedPose) {
        poseHistory.append((timestamp, pose))
        if poseHistory.count > maxHistorySize {
            poseHistory.removeFirst(poseHistory.count - maxHistorySize)
        }
    }

    private func propagateCovariance(dt: Double, accelWorld: SIMD3<Double>) {
        // Simplified covariance propagation using discrete-time noise
        // F is approximately identity + dt * off-diagonal blocks
        // Q is diagonal process noise scaled by dt

        let dt2 = dt * dt
        let accelVar = accelNoiseDensity * accelNoiseDensity * dt
        let gyroVar = gyroNoiseDensity * gyroNoiseDensity * dt
        let accelBiasVar = accelBiasWalk * accelBiasWalk * dt
        let gyroBiasVar = gyroBiasWalk * gyroBiasWalk * dt

        // Add process noise to diagonal
        // Position (0-2): accel noise * dt^2
        for i in 0..<3 { P[i * 15 + i] += accelVar * dt2 }
        // Velocity (3-5): accel noise * dt
        for i in 3..<6 { P[i * 15 + i] += accelVar }
        // Orientation (6-9): gyro noise * dt (using 3 for rotation vector approx)
        for i in 6..<9 { P[i * 15 + i] += gyroVar }
        // Gyro bias (9-11)
        for i in 9..<12 { P[i * 15 + i] += gyroBiasVar }
        // Accel bias (12-14)
        for i in 12..<15 { P[i * 15 + i] += accelBiasVar }

        // Cross-terms: position-velocity coupling
        for i in 0..<3 {
            P[i * 15 + (i + 3)] += P[(i + 3) * 15 + (i + 3)] * dt
            P[(i + 3) * 15 + i] = P[i * 15 + (i + 3)]
        }
    }

    // MARK: - Matrix Operations

    private func matMul(_ A: [Double], _ B: [Double], m: Int, n: Int, k: Int) -> [Double] {
        var C = [Double](repeating: 0, count: m * n)
        vDSP_mmulD(A, 1, B, 1, &C, 1, vDSP_Length(m), vDSP_Length(n), vDSP_Length(k))
        return C
    }

    private func transpose(_ A: [Double], rows: Int, cols: Int) -> [Double] {
        var result = [Double](repeating: 0, count: rows * cols)
        vDSP_mtransD(A, 1, &result, 1, vDSP_Length(cols), vDSP_Length(rows))
        return result
    }

    private func invert6x6(_ matrix: [Double]) -> [Double]? {
        var M = matrix
        var N = __CLPK_integer(6)
        var pivots = [__CLPK_integer](repeating: 0, count: 6)
        var workspace = [Double](repeating: 0, count: 6)
        var info: __CLPK_integer = 0

        dgetrf_(&N, &N, &M, &N, &pivots, &info)
        guard info == 0 else { return nil }

        var lwork = N
        dgetri_(&N, &M, &N, &pivots, &workspace, &lwork, &info)
        guard info == 0 else { return nil }

        return M
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        position = .zero
        velocity = .zero
        orientation = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        gyroBias = .zero
        accelBias = .zero
        isInitialized = false
        lastIMUTimestamp = nil
        lastLiDARTimestamp = nil
        poseHistory.removeAll()
        P = [Double](repeating: 0, count: 225)
        for i in 0..<3 { P[i * 15 + i] = config.initialPositionVariance }
        for i in 3..<6 { P[i * 15 + i] = config.initialVelocityVariance }
        for i in 6..<10 { P[i * 15 + i] = config.initialOrientationVariance }
        for i in 10..<15 { P[i * 15 + i] = config.initialBiasVariance }
    }
}
