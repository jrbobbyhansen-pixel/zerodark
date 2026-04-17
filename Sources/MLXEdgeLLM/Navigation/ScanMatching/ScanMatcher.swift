// ScanMatcher.swift — ICP-based position correction for GPS-denied navigation
// Wraps MergeClouds PointCloudMerger to produce ScanMatchResult for BreadcrumbEngine.
// Only activates when GPS accuracy degrades beyond the dead-reckoning threshold (30m).

import Foundation
import simd

/// Matches incoming LiDAR frames against a reference map using ICP.
/// Outputs position corrections that BreadcrumbEngine injects as pseudo-GPS measurements.
final class ScanMatcher {

    /// GPS accuracy threshold above which scan matching activates (meters).
    /// Matches BreadcrumbEngine.gpsDegradedThresholdM to engage at the same boundary.
    var activationAccuracyM: Double = 30.0

    /// Minimum ICP score required to inject a correction (0–1).
    var minScoreThreshold: Float = 0.40

    /// Minimum number of incoming points needed to attempt matching.
    var minIncomingPoints: Int = 100

    private let merger = PointCloudMerger()
    /// Rolling reference map updated from accepted frames.
    private var referenceCloud: [SIMD3<Float>] = []
    private let maxReferencePoints: Int = 20_000
    private let lock = NSLock()

    // MARK: - Public API

    /// Attempt to match `incoming` against the accumulated reference map.
    /// - Returns: A `ScanMatchResult` with position delta if GPS is degraded and ICP converges,
    ///   `nil` if GPS is healthy, there is no reference map yet, or ICP fails to converge.
    func match(
        incoming: [SIMD3<Float>],
        gpsAccuracy: Double
    ) -> ScanMatchResult? {
        guard gpsAccuracy > activationAccuracyM else {
            // GPS is healthy — add to reference map but don't inject corrections
            updateReference(incoming)
            return nil
        }

        lock.lock()
        let ref = referenceCloud
        lock.unlock()

        guard ref.count >= minIncomingPoints,
              incoming.count >= minIncomingPoints else { return nil }

        // Run ICP: align incoming to reference, get delta transform
        let result = merger.alignAndMerge(base: ref, target: incoming)

        // Quality: overlap ratio and mean residual score
        let residualScore: Float = result.meanResidual > 0
            ? min(1.0, 0.05 / result.meanResidual)   // residual < 5cm → score 1.0
            : 0
        let score = (result.overlap * 0.5 + residualScore * 0.5)

        guard score >= minScoreThreshold, result.iterations > 1 else { return nil }

        // Extract translation delta from the ICP transform
        // transform column 3 = [tx, ty, tz, 1] in world-space meters
        let t4 = result.transform
        let tx = t4.columns.3.x
        let ty = t4.columns.3.y
        let tz = t4.columns.3.z
        let translationDelta = SIMD3<Float>(tx, ty, tz)

        // Only update reference when score is high (avoid poisoning with bad matches)
        if score > 0.6 {
            updateReference(incoming)
        }

        return ScanMatchResult(
            alignmentTransform: result.transform,
            translationMeters: translationDelta,
            score: score,
            converged: result.iterations < merger.maxIterations,
            meanResidual: result.meanResidual
        )
    }

    /// Seed the reference map with a known-good point cloud.
    /// Call this at the start of a scan when GPS is still healthy.
    func seed(with points: [SIMD3<Float>]) {
        lock.lock()
        defer { lock.unlock() }
        referenceCloud = Array(points.prefix(maxReferencePoints))
    }

    /// Clear the accumulated reference map (call on scan end or GPS recovery).
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        referenceCloud = []
    }

    // MARK: - Private

    private func updateReference(_ incoming: [SIMD3<Float>]) {
        lock.lock()
        defer { lock.unlock() }
        if referenceCloud.isEmpty {
            referenceCloud = Array(incoming.prefix(maxReferencePoints))
        } else {
            // Reservoir: add new points, keeping total under ceiling
            let capacity = maxReferencePoints - referenceCloud.count
            if capacity > 0 {
                referenceCloud.append(contentsOf: incoming.prefix(capacity))
            }
        }
    }
}
