// MonteCarloMatcher.swift — Monte Carlo scan matching (Boeing Cartographer pattern)

import simd
import Foundation

/// Monte Carlo scan matcher
public class MonteCarloMatcher {
    private let proposalCount: Int = 500
    private let icpIterations: Int = 10

    public init() {}

    /// Match scan against reference using Monte Carlo + ICP
    public func match(
        scan: [[simd_float2]],
        reference: [[simd_float2]],
        initialPose: simd_float3
    ) -> ScanMatchResult {
        guard !scan.isEmpty && !reference.isEmpty else {
            return ScanMatchResult(
                transform: simd_float3x3(1),
                score: 0,
                converged: false
            )
        }

        var bestScore: Float = 0
        var bestTransform = simd_float3x3(1)

        // Generate random proposals
        for _ in 0..<proposalCount {
            let dTheta = Float.random(in: -0.1...0.1)
            let dx = Float.random(in: -2...2)
            let dy = Float.random(in: -2...2)

            let cosTheta = cos(dTheta)
            let sinTheta = sin(dTheta)

            // 3x3 transform matrix (2D rotation + translation in homogeneous coords)
            let proposal = simd_float3x3(
                simd_float3(cosTheta, sinTheta, dx),
                simd_float3(-sinTheta, cosTheta, dy),
                simd_float3(0, 0, 1)
            )

            // Score proposal
            let score = scoreTransform(proposal, scan: scan, reference: reference)

            if score > bestScore {
                bestScore = score
                bestTransform = proposal
            }
        }

        // Refine best with ICP
        var transform = bestTransform
        for _ in 0..<icpIterations {
            let refined = refineICP(transform, scan: scan, reference: reference)
            let newScore = scoreTransform(refined, scan: scan, reference: reference)

            if newScore > bestScore {
                bestScore = newScore
                transform = refined
            }
        }

        return ScanMatchResult(
            transform: transform,
            score: bestScore,
            converged: bestScore > 0.5
        )
    }

    /// Score transform by overlap
    private func scoreTransform(
        _ transform: simd_float3x3,
        scan: [[simd_float2]],
        reference: [[simd_float2]]
    ) -> Float {
        var score: Float = 0
        let threshold: Float = 0.5  // Max matching distance
        let flatScan = scan.flatMap({ $0 })

        guard !flatScan.isEmpty else { return 0 }

        for point in flatScan {
            // Transform point
            let p = simd_float3(point.x, point.y, 1)
            let transformed = transform * p
            let tPoint = simd_float2(transformed.x, transformed.y)

            // Find closest reference point
            var minDist = Float.infinity
            for refPoint in reference.flatMap({ $0 }) {
                let dist = simd_distance(tPoint, refPoint)
                minDist = min(minDist, dist)
            }

            if minDist < threshold {
                score += 1 - (minDist / threshold)
            }
        }

        return score / Float(flatScan.count)
    }

    /// Refine transform using ICP
    private func refineICP(
        _ transform: simd_float3x3,
        scan: [[simd_float2]],
        reference: [[simd_float2]]
    ) -> simd_float3x3 {
        // Simplified ICP: compute mean and apply adjustment
        let flatScan = scan.flatMap { $0 }
        let scanMean = flatScan.reduce(simd_float2(0), +) / Float(flatScan.count)

        var sumDx: Float = 0
        var sumDy: Float = 0

        for point in flatScan {
            let p = simd_float3(point.x, point.y, 1)
            let transformed = transform * p
            let tPoint = simd_float2(transformed.x, transformed.y)

            // Find closest reference
            var closest = simd_float2(0)
            var minDist = Float.infinity

            for refPoint in reference.flatMap({ $0 }) {
                let dist = simd_distance(tPoint, refPoint)
                if dist < minDist {
                    minDist = dist
                    closest = refPoint
                }
            }

            sumDx += closest.x - tPoint.x
            sumDy += closest.y - tPoint.y
        }

        let adjustment = simd_float2(
            sumDx / Float(flatScan.count),
            sumDy / Float(flatScan.count)
        ) * 0.1

        // Apply adjustment
        var refined = transform
        refined[0].z += adjustment.x
        refined[1].z += adjustment.y

        return refined
    }
}
