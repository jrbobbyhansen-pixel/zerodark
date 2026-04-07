// PlaneDetection.swift — Sequential multi-plane RANSAC detection
// Extracts multiple planes from point cloud by iteratively fitting and removing inliers
// Classifies each plane as floor/wall/ceiling/roof based on normal orientation

import Foundation
import simd

// MARK: - Detected Plane

struct DetectedPlane: Identifiable {
    let id = UUID()
    let plane: Plane
    let classification: PlaneClassification
    let inlierCount: Int
    let centroid: SIMD3<Float>
    let inlierIndices: [Int]
}

struct Plane {
    let normal: SIMD3<Float>
    let distance: Float

    /// Signed distance from point to plane
    func distanceTo(_ point: SIMD3<Float>) -> Float {
        simd_dot(normal, point) + distance
    }
}

enum PlaneClassification: String, CaseIterable {
    case floor
    case ceiling
    case wall
    case roof
    case unknown
}

// MARK: - RANSAC Parameters

struct RANSACParameters {
    var maxIterationsPerPlane: Int = 1000
    var distanceThreshold: Float = 0.03
    var minInlierRatio: Float = 0.05
    var maxPlanes: Int = 10
    var minInlierCount: Int = 50

    static let `default` = RANSACParameters()
}

// MARK: - PlaneDetection

class PlaneDetection {

    /// Detect multiple planes in a point cloud using sequential RANSAC.
    static func detectPlanes(
        in points: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        scannerHeight: Float = 1.5,
        parameters: RANSACParameters = .default
    ) -> [DetectedPlane] {
        guard points.count >= 3 else { return [] }

        var detectedPlanes: [DetectedPlane] = []
        var remainingIndices = Array(0..<points.count)

        for _ in 0..<parameters.maxPlanes {
            guard remainingIndices.count >= parameters.minInlierCount else { break }

            // Run RANSAC on remaining points
            guard let (plane, inlierIndices) = ransacFit(
                points: points,
                indices: remainingIndices,
                parameters: parameters
            ) else { break }

            // Check minimum inlier ratio
            let ratio = Float(inlierIndices.count) / Float(remainingIndices.count)
            guard ratio >= parameters.minInlierRatio || inlierIndices.count >= parameters.minInlierCount else { break }

            // Compute centroid of inliers
            var centroid = SIMD3<Float>.zero
            for idx in inlierIndices { centroid += points[idx] }
            centroid /= Float(inlierIndices.count)

            // Classify the plane
            let classification = classifyPlane(normal: plane.normal, centroid: centroid, scannerHeight: scannerHeight)

            detectedPlanes.append(DetectedPlane(
                plane: plane,
                classification: classification,
                inlierCount: inlierIndices.count,
                centroid: centroid,
                inlierIndices: inlierIndices
            ))

            // Remove inlier indices from remaining pool
            let inlierSet = Set(inlierIndices)
            remainingIndices.removeAll { inlierSet.contains($0) }
        }

        return detectedPlanes
    }

    // MARK: - RANSAC Core

    /// Fit a single plane to the point subset using RANSAC.
    private static func ransacFit(
        points: [SIMD3<Float>],
        indices: [Int],
        parameters: RANSACParameters
    ) -> (Plane, [Int])? {
        guard indices.count >= 3 else { return nil }

        var bestPlane: Plane?
        var bestInliers: [Int] = []

        for _ in 0..<parameters.maxIterationsPerPlane {
            // Sample 3 random points
            let i0 = indices[Int.random(in: 0..<indices.count)]
            let i1 = indices[Int.random(in: 0..<indices.count)]
            let i2 = indices[Int.random(in: 0..<indices.count)]
            guard i0 != i1 && i1 != i2 && i0 != i2 else { continue }

            let p0 = points[i0], p1 = points[i1], p2 = points[i2]

            // Compute plane normal via cross product
            let v1 = p1 - p0
            let v2 = p2 - p0
            var normal = simd_cross(v1, v2)
            let len = simd_length(normal)
            guard len > 1e-6 else { continue }
            normal /= len

            // Plane equation: dot(normal, x) + d = 0
            let d = -simd_dot(normal, p0)
            let candidate = Plane(normal: normal, distance: d)

            // Count inliers
            var inliers: [Int] = []
            for idx in indices {
                if abs(candidate.distanceTo(points[idx])) <= parameters.distanceThreshold {
                    inliers.append(idx)
                }
            }

            if inliers.count > bestInliers.count {
                bestPlane = candidate
                bestInliers = inliers
            }

            // Early termination if we found a great fit
            if Float(bestInliers.count) / Float(indices.count) > 0.8 { break }
        }

        guard let plane = bestPlane, bestInliers.count >= parameters.minInlierCount else { return nil }

        // Refine plane normal using all inliers (least-squares)
        let refined = refinePlane(points: points, inliers: bestInliers)
        return (refined ?? plane, bestInliers)
    }

    /// Refine plane fit using PCA on inlier points.
    private static func refinePlane(points: [SIMD3<Float>], inliers: [Int]) -> Plane? {
        guard inliers.count >= 3 else { return nil }

        var centroid = SIMD3<Float>.zero
        for idx in inliers { centroid += points[idx] }
        centroid /= Float(inliers.count)

        // Build covariance matrix
        var cov = simd_float3x3(0)
        for idx in inliers {
            let d = points[idx] - centroid
            cov[0] += SIMD3(d.x * d.x, d.x * d.y, d.x * d.z)
            cov[1] += SIMD3(d.y * d.x, d.y * d.y, d.y * d.z)
            cov[2] += SIMD3(d.z * d.x, d.z * d.y, d.z * d.z)
        }

        // Normal = eigenvector of smallest eigenvalue (same method as PointCloudEngine)
        let normal = smallestEigenvector3x3(cov)
        let distance = -simd_dot(normal, centroid)
        return Plane(normal: normal, distance: distance)
    }

    // MARK: - Classification

    /// Classify a plane based on its normal orientation relative to gravity.
    private static func classifyPlane(normal: SIMD3<Float>, centroid: SIMD3<Float>, scannerHeight: Float) -> PlaneClassification {
        let up = SIMD3<Float>(0, 1, 0)
        let dotUp = abs(simd_dot(normal, up))

        if dotUp > 0.9 {
            // Horizontal plane — floor or ceiling?
            if centroid.y < scannerHeight * 0.3 {
                return .floor
            } else if centroid.y > scannerHeight * 1.5 {
                return .ceiling
            } else {
                return centroid.y < scannerHeight ? .floor : .ceiling
            }
        } else if dotUp < 0.15 {
            return .wall
        } else if dotUp > 0.5 && centroid.y > scannerHeight {
            return .roof
        }

        return .unknown
    }

    // MARK: - Eigenvector Helper

    private static func smallestEigenvector3x3(_ m: simd_float3x3) -> SIMD3<Float> {
        let a = m[0][0], b = m[1][1], c = m[2][2]
        let d = m[0][1], e = m[1][2], f = m[0][2]

        let p1 = d*d + f*f + e*e
        if p1 < 1e-10 {
            let eigenvalues = [a, b, c]
            let minIdx = eigenvalues.enumerated().min(by: { $0.element < $1.element })!.offset
            var v = SIMD3<Float>.zero
            v[minIdx] = 1
            return v
        }

        let q = (a + b + c) / 3.0
        let p2 = (a - q)*(a - q) + (b - q)*(b - q) + (c - q)*(c - q) + 2*p1
        let p = sqrt(p2 / 6.0)

        var B = m
        B[0][0] -= q; B[1][1] -= q; B[2][2] -= q
        B[0] /= p; B[1] /= p; B[2] /= p

        let detB = B[0][0] * (B[1][1]*B[2][2] - B[1][2]*B[2][1])
                 - B[0][1] * (B[1][0]*B[2][2] - B[1][2]*B[2][0])
                 + B[0][2] * (B[1][0]*B[2][1] - B[1][1]*B[2][0])
        let r = detB / 2.0

        let phi: Float = r <= -1 ? .pi / 3.0 : (r >= 1 ? 0 : acos(r) / 3.0)
        let eig2 = q + 2 * p * cos(phi + (2.0 * .pi / 3.0))

        var shifted = m
        shifted[0][0] -= eig2; shifted[1][1] -= eig2; shifted[2][2] -= eig2

        let row0 = SIMD3(shifted[0][0], shifted[0][1], shifted[0][2])
        let row1 = SIMD3(shifted[1][0], shifted[1][1], shifted[1][2])
        var normal = simd_cross(row0, row1)
        let len = simd_length(normal)
        if len > 1e-8 {
            return normal / len
        }
        let row2 = SIMD3(shifted[2][0], shifted[2][1], shifted[2][2])
        normal = simd_cross(row0, row2)
        let len2 = simd_length(normal)
        return len2 > 1e-8 ? normal / len2 : SIMD3(0, 1, 0)
    }
}
