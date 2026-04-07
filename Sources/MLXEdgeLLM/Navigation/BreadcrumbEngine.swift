// BreadcrumbEngine.swift — EKF GPS/IMU fused breadcrumb trail
// 7-state Extended Kalman Filter: [lat, lon, alt, vN, vE, vD, heading]
// Replaces naive CLLocationManager-only breadcrumb recording

import Foundation
import CoreLocation
import CoreMotion
import Combine
import Accelerate

// MARK: - BreadcrumbEngine

@MainActor
final class BreadcrumbEngine: ObservableObject {
    static let shared = BreadcrumbEngine()

    // Published trail for map rendering
    @Published private(set) var trail: [CLLocationCoordinate2D] = []
    @Published private(set) var isRecording = false
    @Published private(set) var speedMps: Double = 0
    @Published private(set) var heading: Double = 0
    @Published private(set) var currentPosition: CLLocationCoordinate2D?
    @Published private(set) var positionUncertaintyMeters: Double = 0

    // EKF state vector: [lat, lon, alt, vN, vE, vD, heading] (7 states)
    private var x = [Double](repeating: 0, count: 7)
    // Covariance matrix (7x7)
    private var P = [Double](repeating: 0, count: 49)

    // Process noise Q (diagonal)
    private let qPosition: Double = 0.0001      // lat/lon noise (deg²/s)
    private let qAltitude: Double = 0.01         // alt noise (m²/s)
    private let qVelocity: Double = 0.5          // velocity noise (m²/s²)
    private let qHeading: Double = 0.01          // heading noise (rad²/s)

    // Hardware
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var locationDelegate: LocationDelegate?

    // Trail management
    private let maxTrailPoints = 2000
    private let pruneThreshold = 1000
    private let minRecordDistanceMeters: Double = 2.0
    private var lastRecordedCoord: CLLocationCoordinate2D?

    // Timing
    private var lastPredictTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var initialized = false

    private init() {
        initializeCovariance()
    }

    // MARK: - Lifecycle

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        initialized = false
        trail = []
        lastRecordedCoord = nil

        // Location updates
        locationDelegate = LocationDelegate { [weak self] location in
            Task { @MainActor in
                self?.updateGPS(location)
            }
        }
        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1.0
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        // IMU prediction at 10Hz
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion else { return }
                Task { @MainActor in
                    self?.predictIMU(motion)
                }
            }
        }
    }

    func stopRecording() {
        isRecording = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
        locationDelegate = nil
    }

    func clearTrail() {
        trail = []
        lastRecordedCoord = nil
    }

    // MARK: - EKF Predict (IMU)

    private func predictIMU(_ motion: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        guard initialized else {
            lastPredictTime = now
            return
        }
        let dt = now - lastPredictTime
        guard dt > 0 && dt < 1.0 else {
            lastPredictTime = now
            return
        }
        lastPredictTime = now

        // Full DCM rotation: device accel → NED using attitude rotation matrix
        let rm = motion.attitude.rotationMatrix
        let ax = motion.userAcceleration.x
        let ay = motion.userAcceleration.y
        let az = motion.userAcceleration.z

        // R_body_to_NED * accel_body (3x3 * 3x1) — proper frame transform
        let aN = rm.m11 * ax + rm.m12 * ay + rm.m13 * az
        let aE = rm.m21 * ax + rm.m22 * ay + rm.m23 * az
        let aD = rm.m31 * ax + rm.m32 * ay + rm.m33 * az

        // Convert accel from g-units to m/s²
        let aNms2 = aN * 9.81
        let aEms2 = aE * 9.81
        let aDms2 = aD * 9.81

        // Coordinate conversion constants
        let lat = x[0]
        let mPerDegLat = 111320.0
        let mPerDegLon = 111320.0 * cos(lat * .pi / 180.0)
        let invLat = 1.0 / mPerDegLat
        let invLon = 1.0 / max(mPerDegLon, 1.0)

        // --- State prediction: x_k|k-1 = f(x_k-1) ---
        x[0] += x[3] * dt * invLat           // lat += vN * dt / m_per_deg
        x[1] += x[4] * dt * invLon           // lon += vE * dt / m_per_deg
        x[2] += x[5] * dt                     // alt += vD * dt
        x[3] += aNms2 * dt                    // vN += aN * dt
        x[4] += aEms2 * dt                    // vE += aE * dt
        x[5] += aDms2 * dt                    // vD += aD * dt
        // x[6] heading: update from gyro-integrated yaw, blended with current estimate
        let measuredHeading = motion.attitude.yaw
        let headingInnovation = measuredHeading - x[6]
        // Wrap to [-pi, pi]
        let wrappedInnovation = atan2(sin(headingInnovation), cos(headingInnovation))
        let headingBlend = 0.1 * dt  // Slow drift toward measured (not overwrite)
        x[6] += wrappedInnovation * headingBlend

        // --- Jacobian F (7x7) = df/dx ---
        // F = I + dt * [partial derivatives]
        // Non-trivial partials: d(lat)/d(vN) = dt/mPerDegLat, d(lon)/d(vE) = dt/mPerDegLon
        // All other off-diagonals are zero for this model
        var F = [Double](repeating: 0, count: 49)
        for i in 0..<7 { F[i * 7 + i] = 1.0 }   // Identity
        F[0 * 7 + 3] = dt * invLat                 // d(lat)/d(vN)
        F[1 * 7 + 4] = dt * invLon                 // d(lon)/d(vE)
        F[2 * 7 + 5] = dt                          // d(alt)/d(vD)

        // --- Process noise Q (diagonal) ---
        var Q = [Double](repeating: 0, count: 49)
        Q[0 * 7 + 0] = qPosition * dt
        Q[1 * 7 + 1] = qPosition * dt
        Q[2 * 7 + 2] = qAltitude * dt
        Q[3 * 7 + 3] = qVelocity * dt
        Q[4 * 7 + 4] = qVelocity * dt
        Q[5 * 7 + 5] = qVelocity * dt
        Q[6 * 7 + 6] = qHeading * dt

        // --- Covariance propagation: P = F * P * F' + Q ---
        let FP = matMul7(F, P)
        let Ft = transpose7(F)
        let FPFt = matMul7(FP, Ft)
        for i in 0..<49 { P[i] = FPFt[i] + Q[i] }

        updatePublishedState()
    }

    // MARK: - EKF Update (GPS)

    /// GPS measurement update with full Kalman gain matrix
    /// Measurement model: z = [lat, lon, alt, vN, vE] (5 measurements when speed available, else 3)
    private func updateGPS(_ location: CLLocation) {
        let now = ProcessInfo.processInfo.systemUptime

        if !initialized {
            x[0] = location.coordinate.latitude
            x[1] = location.coordinate.longitude
            x[2] = location.altitude
            x[3] = 0; x[4] = 0; x[5] = 0
            x[6] = location.course >= 0 ? location.course * .pi / 180.0 : 0
            initializeCovariance()
            initialized = true
            lastPredictTime = now
            lastUpdateTime = now
            recordTrailPoint()
            return
        }

        let hAcc = max(location.horizontalAccuracy, 1.0)
        let vAcc = max(location.verticalAccuracy, 2.0)
        let mPerDegLat = 111320.0
        let mPerDegLon = 111320.0 * cos(x[0] * .pi / 180.0)

        let hasSpeed = location.speed >= 0 && location.speedAccuracy >= 0

        if hasSpeed {
            // 5-measurement update: [lat, lon, alt, vN, vE]
            let gpsVN = location.speed * cos(location.course * .pi / 180.0)
            let gpsVE = location.speed * sin(location.course * .pi / 180.0)

            // H matrix (5x7): maps state to measurement
            // H = [[1,0,0,0,0,0,0], [0,1,0,0,0,0,0], [0,0,1,0,0,0,0], [0,0,0,1,0,0,0], [0,0,0,0,1,0,0]]
            // Innovation y = z - H*x
            let y: [Double] = [
                location.coordinate.latitude - x[0],
                location.coordinate.longitude - x[1],
                location.altitude - x[2],
                gpsVN - x[3],
                gpsVE - x[4]
            ]

            // R diagonal (5x5)
            let rLat = pow(hAcc / mPerDegLat, 2)
            let rLon = pow(hAcc / mPerDegLon, 2)
            let rAlt = pow(vAcc, 2)
            let rSpd = pow(max(location.speedAccuracy, 0.5), 2)
            let R: [Double] = [rLat, rLon, rAlt, rSpd, rSpd]

            // Since H is a simple selector (first 5 rows of I), S = H*P*H' + R simplifies to:
            // S[i][j] = P[i*7+j] for i,j in 0..<5, plus R on diagonal
            // K = P*H' * S^-1, and since H selects columns 0-4:
            // K[i][j] = P[i*7+j] / S[j][j]  (when S is approximately diagonal for decoupled channels)
            // For proper coupling, compute full 5x5 S and invert
            var S = [Double](repeating: 0, count: 25)
            for i in 0..<5 {
                for j in 0..<5 {
                    S[i * 5 + j] = P[i * 7 + j]
                }
                S[i * 5 + i] += R[i]
            }

            // Invert S (5x5) via Gauss-Jordan
            guard let Sinv = invert5x5(S) else {
                lastUpdateTime = now
                return
            }

            // K = P * H' * Sinv (7x5) — H' selects rows 0-4, so P*H' = columns 0-4 of P
            // K[i][j] = sum_k P[i*7+k] * Sinv[k*5+j] for k in 0..<5
            var K = [Double](repeating: 0, count: 35) // 7x5
            for i in 0..<7 {
                for j in 0..<5 {
                    var sum = 0.0
                    for k in 0..<5 {
                        sum += P[i * 7 + k] * Sinv[k * 5 + j]
                    }
                    K[i * 5 + j] = sum
                }
            }

            // State update: x += K * y
            for i in 0..<7 {
                var correction = 0.0
                for j in 0..<5 {
                    correction += K[i * 5 + j] * y[j]
                }
                x[i] += correction
            }

            // Covariance update: P = (I - K*H) * P
            // (I - K*H) is 7x7: KH[i][j] = K[i][j] for j < 5, else 0
            var IKH = [Double](repeating: 0, count: 49)
            for i in 0..<7 { IKH[i * 7 + i] = 1.0 }
            for i in 0..<7 {
                for j in 0..<5 {
                    IKH[i * 7 + j] -= K[i * 5 + j]
                }
            }
            let Pnew = matMul7(IKH, P)
            P = Pnew

        } else {
            // 3-measurement update: [lat, lon, alt] only
            let y: [Double] = [
                location.coordinate.latitude - x[0],
                location.coordinate.longitude - x[1],
                location.altitude - x[2]
            ]
            let R: [Double] = [
                pow(hAcc / mPerDegLat, 2),
                pow(hAcc / mPerDegLon, 2),
                pow(vAcc, 2)
            ]

            // S = P[0:3, 0:3] + R (3x3)
            var S = [Double](repeating: 0, count: 9)
            for i in 0..<3 {
                for j in 0..<3 { S[i * 3 + j] = P[i * 7 + j] }
                S[i * 3 + i] += R[i]
            }

            guard let Sinv = invert3x3(S) else {
                lastUpdateTime = now
                return
            }

            // K (7x3) = P[:,0:3] * Sinv
            var K = [Double](repeating: 0, count: 21)
            for i in 0..<7 {
                for j in 0..<3 {
                    var sum = 0.0
                    for k in 0..<3 { sum += P[i * 7 + k] * Sinv[k * 3 + j] }
                    K[i * 3 + j] = sum
                }
            }

            for i in 0..<7 {
                var correction = 0.0
                for j in 0..<3 { correction += K[i * 3 + j] * y[j] }
                x[i] += correction
            }

            var IKH = [Double](repeating: 0, count: 49)
            for i in 0..<7 { IKH[i * 7 + i] = 1.0 }
            for i in 0..<7 {
                for j in 0..<3 { IKH[i * 7 + j] -= K[i * 3 + j] }
            }
            P = matMul7(IKH, P)
        }

        // Wrap heading to [-pi, pi]
        x[6] = atan2(sin(x[6]), cos(x[6]))

        lastUpdateTime = now
        updatePublishedState()
        recordTrailPoint()
    }

    // MARK: - Trail Recording

    private func recordTrailPoint() {
        let coord = CLLocationCoordinate2D(latitude: x[0], longitude: x[1])

        // Skip if too close to last recorded point
        if let last = lastRecordedCoord {
            let dist = distanceMeters(from: last, to: coord)
            if dist < minRecordDistanceMeters { return }
        }

        trail.append(coord)
        lastRecordedCoord = coord
        currentPosition = coord

        // Prune if trail exceeds threshold
        if trail.count > maxTrailPoints {
            trail = douglasPeuckerSimplify(trail, epsilon: 0.00001, maxPoints: pruneThreshold)
        }
    }

    // MARK: - Published State

    private func updatePublishedState() {
        speedMps = sqrt(x[3] * x[3] + x[4] * x[4])
        heading = x[6] * 180.0 / .pi
        if heading < 0 { heading += 360.0 }
        currentPosition = CLLocationCoordinate2D(latitude: x[0], longitude: x[1])
        positionUncertaintyMeters = sqrt(P[0]) * 111320.0 // Rough lat uncertainty to meters
    }

    // MARK: - Initialization

    private func initializeCovariance() {
        P = [Double](repeating: 0, count: 49)
        // Position uncertainty: ~10m in degrees
        P[0] = pow(10.0 / 111320.0, 2)   // lat
        P[8] = pow(10.0 / 111320.0, 2)   // lon
        P[16] = 25.0                       // alt (5m)
        P[24] = 1.0                        // vN (1 m/s)
        P[32] = 1.0                        // vE (1 m/s)
        P[40] = 0.25                       // vD (0.5 m/s)
        P[48] = 0.1                        // heading (0.3 rad)
    }

    // MARK: - Douglas-Peucker Simplification

    private func douglasPeuckerSimplify(_ points: [CLLocationCoordinate2D], epsilon: Double, maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var result = dpSimplify(points, epsilon: epsilon)
        // If still too many, increase epsilon
        var eps = epsilon
        while result.count > maxPoints {
            eps *= 2.0
            result = dpSimplify(points, epsilon: eps)
        }
        return result
    }

    private func dpSimplify(_ points: [CLLocationCoordinate2D], epsilon: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var maxDist: Double = 0
        var maxIdx = 0

        let first = points[0]
        let last = points[points.count - 1]

        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(points[i], lineStart: first, lineEnd: last)
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }

        if maxDist > epsilon {
            let left = dpSimplify(Array(points[0...maxIdx]), epsilon: epsilon)
            let right = dpSimplify(Array(points[maxIdx...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    private func perpendicularDistance(_ point: CLLocationCoordinate2D, lineStart: CLLocationCoordinate2D, lineEnd: CLLocationCoordinate2D) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        let denom = sqrt(dx * dx + dy * dy)
        guard denom > 0 else { return 0 }
        return abs(dy * point.longitude - dx * point.latitude + lineEnd.longitude * lineStart.latitude - lineEnd.latitude * lineStart.longitude) / denom
    }

    // MARK: - Matrix Operations (7x7)

    /// 7x7 matrix multiply: C = A * B (row-major)
    private func matMul7(_ A: [Double], _ B: [Double]) -> [Double] {
        var C = [Double](repeating: 0, count: 49)
        for i in 0..<7 {
            for j in 0..<7 {
                var sum = 0.0
                for k in 0..<7 { sum += A[i * 7 + k] * B[k * 7 + j] }
                C[i * 7 + j] = sum
            }
        }
        return C
    }

    /// 7x7 transpose
    private func transpose7(_ A: [Double]) -> [Double] {
        var T = [Double](repeating: 0, count: 49)
        for i in 0..<7 {
            for j in 0..<7 { T[j * 7 + i] = A[i * 7 + j] }
        }
        return T
    }

    /// 3x3 matrix inversion via Cramer's rule
    private func invert3x3(_ m: [Double]) -> [Double]? {
        let a = m[0], b = m[1], c = m[2]
        let d = m[3], e = m[4], f = m[5]
        let g = m[6], h = m[7], i = m[8]
        let det = a*(e*i - f*h) - b*(d*i - f*g) + c*(d*h - e*g)
        guard abs(det) > 1e-30 else { return nil }
        let invDet = 1.0 / det
        return [
            (e*i - f*h) * invDet, (c*h - b*i) * invDet, (b*f - c*e) * invDet,
            (f*g - d*i) * invDet, (a*i - c*g) * invDet, (c*d - a*f) * invDet,
            (d*h - e*g) * invDet, (b*g - a*h) * invDet, (a*e - b*d) * invDet
        ]
    }

    /// 5x5 matrix inversion via Gauss-Jordan elimination
    private func invert5x5(_ m: [Double]) -> [Double]? {
        let n = 5
        // Augmented matrix [m | I]
        var aug = [Double](repeating: 0, count: n * 2 * n)
        for i in 0..<n {
            for j in 0..<n { aug[i * 2 * n + j] = m[i * n + j] }
            aug[i * 2 * n + n + i] = 1.0
        }
        // Forward elimination with partial pivoting
        for col in 0..<n {
            var maxRow = col
            var maxVal = abs(aug[col * 2 * n + col])
            for row in (col + 1)..<n {
                let v = abs(aug[row * 2 * n + col])
                if v > maxVal { maxVal = v; maxRow = row }
            }
            guard maxVal > 1e-30 else { return nil }
            if maxRow != col {
                for j in 0..<(2 * n) { aug.swapAt(col * 2 * n + j, maxRow * 2 * n + j) }
            }
            let pivot = aug[col * 2 * n + col]
            for j in 0..<(2 * n) { aug[col * 2 * n + j] /= pivot }
            for row in 0..<n where row != col {
                let factor = aug[row * 2 * n + col]
                for j in 0..<(2 * n) { aug[row * 2 * n + j] -= factor * aug[col * 2 * n + j] }
            }
        }
        // Extract inverse
        var inv = [Double](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in 0..<n { inv[i * n + j] = aug[i * 2 * n + n + j] }
        }
        return inv
    }

    // MARK: - Helpers

    private func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let loc2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return loc1.distance(from: loc2)
    }

    // MARK: - GPX Export

    func exportGPX() -> Data {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="ZeroDark BreadcrumbEngine">
          <trk>
            <name>EKF Breadcrumb Trail</name>
            <trkseg>
        """
        for coord in trail {
            gpx += "      <trkpt lat=\"\(coord.latitude)\" lon=\"\(coord.longitude)\"/>\n"
        }
        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """
        return gpx.data(using: .utf8) ?? Data()
    }
}

// MARK: - Location Delegate

private class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let onLocation: (CLLocation) -> Void

    init(onLocation: @escaping (CLLocation) -> Void) {
        self.onLocation = onLocation
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocation(location)
    }
}
