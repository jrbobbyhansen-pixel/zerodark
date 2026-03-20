// AttitudeSolver.swift — QUEST attitude estimation algorithm (NASA COTS-Star-Tracker pattern)

import simd
import Foundation

/// Attitude solver using QUEST algorithm
public class AttitudeSolver {
    public init() {}

    /// Solve attitude from detected and catalog stars
    public func solve(detected: [DetectedStar], catalog: [StarEntry]) -> simd_quatd? {
        guard detected.count >= 2 && catalog.count >= 2 else {
            return nil
        }

        // Simplified QUEST: build K matrix from star pairs
        var K = simd_double4x4(0)

        for i in 0..<min(detected.count, catalog.count) {
            let detected = detected[i]
            let catalog = catalog[i]

            // Convert detected pixel to unit vector (rough approximation)
            let dVec = simd_double3(
                Double(detected.x) / 320.0 - 1.0,  // Center and normalize
                Double(detected.y) / 240.0 - 1.0,
                2.0  // Constant depth
            )
            let dNorm = normalize(dVec)

            // Catalog vector in spherical coordinates
            let raRad = catalog.rightAscension * .pi / 180.0
            let decRad = catalog.declination * .pi / 180.0
            let cVec = simd_double3(
                cos(decRad) * cos(raRad),
                cos(decRad) * sin(raRad),
                sin(decRad)
            )

            // Accumulate K matrix
            K += simd_double4x4(
                simd_double4(dNorm.x * cVec.x, dNorm.x * cVec.y, dNorm.x * cVec.z, 0),
                simd_double4(dNorm.y * cVec.x, dNorm.y * cVec.y, dNorm.y * cVec.z, 0),
                simd_double4(dNorm.z * cVec.x, dNorm.z * cVec.y, dNorm.z * cVec.z, 0),
                simd_double4(0, 0, 0, 0)
            )
        }

        // Power iteration to find largest eigenvalue/eigenvector
        var v = simd_double4(1, 0, 0, 0)
        for _ in 0..<10 {
            let Kv = K * v
            let norm = simd_length(Kv)
            if norm > 0 {
                v = Kv / norm
            }
        }

        // Convert eigenvector to quaternion
        let quat = simd_quatd(
            vector: simd_double4(v.x, v.y, v.z, v.w)
        )

        return quat
    }

    private func normalize(_ v: simd_double3) -> simd_double3 {
        let len = simd_length(v)
        return len > 0 ? v / len : v
    }
}
