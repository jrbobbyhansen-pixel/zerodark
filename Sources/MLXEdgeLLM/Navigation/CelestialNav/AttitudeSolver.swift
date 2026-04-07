// AttitudeSolver.swift — TRIAD attitude estimation from star observations
// Determines camera orientation from matched star pairs (detected pixels → catalog vectors)

import simd
import Foundation

/// Attitude solver using TRIAD algorithm
/// Requires at least 2 matched star pairs (detected pixel ↔ catalog entry)
public class AttitudeSolver {
    /// Camera intrinsics (pixels). Updated via setCameraIntrinsics().
    private var focalLengthPx: Double = 1000.0  // default ~60° FOV on 1080p
    private var principalX: Double = 540.0
    private var principalY: Double = 960.0

    public init() {}

    /// Set camera intrinsics from actual sensor parameters
    /// - Parameters:
    ///   - focalLength: focal length in pixels (fx ≈ fy for square pixels)
    ///   - cx: principal point x (typically imageWidth / 2)
    ///   - cy: principal point y (typically imageHeight / 2)
    public func setCameraIntrinsics(focalLength: Double, cx: Double, cy: Double) {
        self.focalLengthPx = focalLength
        self.principalX = cx
        self.principalY = cy
    }

    /// Solve attitude from detected and catalog stars using TRIAD
    /// Returns rotation quaternion from camera frame to celestial frame
    public func solve(detected: [DetectedStar], catalog: [StarEntry]) -> simd_quatd? {
        guard detected.count >= 2 && catalog.count >= 2 else {
            return nil
        }

        // Convert detected pixel positions to unit vectors in camera frame
        let b1 = pixelToUnitVector(x: Double(detected[0].x), y: Double(detected[0].y))
        let b2 = pixelToUnitVector(x: Double(detected[1].x), y: Double(detected[1].y))

        // Convert catalog entries to unit vectors in celestial frame
        let r1 = celestialToUnitVector(ra: catalog[0].rightAscension, dec: catalog[0].declination)
        let r2 = celestialToUnitVector(ra: catalog[1].rightAscension, dec: catalog[1].declination)

        // TRIAD algorithm: construct orthonormal triads in both frames
        // Body triad
        let tb1 = b1
        let tb2 = simd_normalize(simd_cross(b1, b2))
        let cross_tb = simd_cross(tb1, tb2)
        guard simd_length(tb2) > 1e-10 && simd_length(cross_tb) > 1e-10 else {
            return nil  // Stars too close together or coincident
        }
        let tb3 = simd_normalize(cross_tb)

        // Reference triad
        let tr1 = r1
        let tr2 = simd_normalize(simd_cross(r1, r2))
        let cross_tr = simd_cross(tr1, tr2)
        guard simd_length(tr2) > 1e-10 && simd_length(cross_tr) > 1e-10 else {
            return nil
        }
        let tr3 = simd_normalize(cross_tr)

        // Rotation matrix R = [r-triad] * [b-triad]^T
        // R maps body vectors to reference vectors: r = R * b
        let bodyMatrix = simd_double3x3(columns: (tb1, tb2, tb3))
        let refMatrix = simd_double3x3(columns: (tr1, tr2, tr3))
        let R = refMatrix * bodyMatrix.transpose

        // Convert rotation matrix to quaternion
        return quaternionFromRotationMatrix(R)
    }

    // MARK: - Coordinate Conversions

    /// Convert pixel (x, y) to unit vector in camera frame using pinhole model
    private func pixelToUnitVector(x: Double, y: Double) -> simd_double3 {
        let vx = (x - principalX) / focalLengthPx
        let vy = (y - principalY) / focalLengthPx
        let vz = 1.0
        return simd_normalize(simd_double3(vx, vy, vz))
    }

    /// Convert RA/Dec (degrees) to unit vector in celestial frame
    private func celestialToUnitVector(ra: Double, dec: Double) -> simd_double3 {
        let raRad = ra * .pi / 180.0
        let decRad = dec * .pi / 180.0
        return simd_double3(
            cos(decRad) * cos(raRad),
            cos(decRad) * sin(raRad),
            sin(decRad)
        )
    }

    /// Extract quaternion from a 3x3 rotation matrix (Shepperd's method)
    private func quaternionFromRotationMatrix(_ R: simd_double3x3) -> simd_quatd {
        let trace = R[0][0] + R[1][1] + R[2][2]

        let w: Double, x: Double, y: Double, z: Double

        if trace > 0 {
            let s = 0.5 / sqrt(trace + 1.0)
            w = 0.25 / s
            x = (R[2][1] - R[1][2]) * s
            y = (R[0][2] - R[2][0]) * s
            z = (R[1][0] - R[0][1]) * s
        } else if R[0][0] > R[1][1] && R[0][0] > R[2][2] {
            let s = 2.0 * sqrt(1.0 + R[0][0] - R[1][1] - R[2][2])
            w = (R[2][1] - R[1][2]) / s
            x = 0.25 * s
            y = (R[0][1] + R[1][0]) / s
            z = (R[0][2] + R[2][0]) / s
        } else if R[1][1] > R[2][2] {
            let s = 2.0 * sqrt(1.0 + R[1][1] - R[0][0] - R[2][2])
            w = (R[0][2] - R[2][0]) / s
            x = (R[0][1] + R[1][0]) / s
            y = 0.25 * s
            z = (R[1][2] + R[2][1]) / s
        } else {
            let s = 2.0 * sqrt(1.0 + R[2][2] - R[0][0] - R[1][1])
            w = (R[1][0] - R[0][1]) / s
            x = (R[0][2] + R[2][0]) / s
            y = (R[1][2] + R[2][1]) / s
            z = 0.25 * s
        }

        return simd_quatd(ix: x, iy: y, iz: z, r: w)
    }
}
