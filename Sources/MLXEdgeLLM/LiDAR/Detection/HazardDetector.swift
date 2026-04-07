// HazardDetector.swift — DEM-based terrain hazard detection
// Detects: drop-offs (steep elevation changes), holes (local depressions),
// and structural instability (high plane-fit residuals)
// Operates on post-scan DEM grid and PlaneDetection output

import Foundation
import simd

// MARK: - Hazard Types

enum HazardType: String, CaseIterable {
    case dropOff           // Steep elevation change > 1.5m within 1m horizontal
    case hole              // Local depression surrounded by higher terrain
    case unstableStructure // Plane with high fit residual (fractured surface)
}

enum HazardSeverity: Int, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: HazardSeverity, rhs: HazardSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Hazard: Identifiable {
    let id = UUID()
    let type: HazardType
    let position: SIMD3<Float>
    let severity: HazardSeverity
    let description: String
}

// MARK: - HazardDetector

class HazardDetector {

    /// Cell size of the DEM grid (meters)
    var cellSize: Float = 0.5

    /// Minimum elevation drop to qualify as a drop-off (meters)
    var dropOffThreshold: Float = 1.5

    /// Minimum depression depth for hole detection (meters)
    var holeThreshold: Float = 0.5

    /// Minimum neighbors that must be higher for hole classification
    var holeNeighborCount: Int = 6

    // MARK: - Detect All Hazards

    /// Run all hazard detection algorithms on the DEM grid and optional plane data.
    func detect(
        dem: [[Float]],
        cellSize: Float = 0.5,
        planes: [DetectedPlane] = [],
        originOffset: SIMD2<Float> = .zero
    ) -> [Hazard] {
        self.cellSize = cellSize
        var hazards: [Hazard] = []

        let rows = dem.count
        guard rows >= 3, let cols = dem.first?.count, cols >= 3 else { return [] }

        // 1. Drop-off detection
        hazards += detectDropOffs(dem: dem, rows: rows, cols: cols, originOffset: originOffset)

        // 2. Hole detection
        hazards += detectHoles(dem: dem, rows: rows, cols: cols, originOffset: originOffset)

        // 3. Structural instability from plane residuals
        hazards += detectUnstablePlanes(planes: planes)

        return hazards
    }

    // MARK: - Drop-Off Detection

    /// Find cells where elevation drops more than threshold within 1 cell distance.
    private func detectDropOffs(dem: [[Float]], rows: Int, cols: Int, originOffset: SIMD2<Float>) -> [Hazard] {
        var hazards: [Hazard] = []

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                let center = dem[r][c]
                if center.isNaN { continue }

                var maxDrop: Float = 0
                var dropDirection = SIMD2<Float>.zero

                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        let neighbor = dem[r + dr][c + dc]
                        if neighbor.isNaN { continue }
                        let drop = center - neighbor
                        if drop > maxDrop {
                            maxDrop = drop
                            dropDirection = SIMD2(Float(dc), Float(dr))
                        }
                    }
                }

                if maxDrop >= dropOffThreshold {
                    let worldPos = SIMD3<Float>(
                        Float(c) * cellSize + originOffset.x,
                        center,
                        Float(r) * cellSize + originOffset.y
                    )
                    let severity: HazardSeverity = maxDrop >= 3.0 ? .critical : (maxDrop >= 2.0 ? .high : .medium)
                    hazards.append(Hazard(
                        type: .dropOff,
                        position: worldPos,
                        severity: severity,
                        description: "Drop-off: \(String(format: "%.1f", maxDrop))m"
                    ))
                }
            }
        }

        return hazards
    }

    // MARK: - Hole Detection

    /// Find cells that are lower than most of their 8 neighbors by more than threshold.
    private func detectHoles(dem: [[Float]], rows: Int, cols: Int, originOffset: SIMD2<Float>) -> [Hazard] {
        var hazards: [Hazard] = []

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                let center = dem[r][c]
                if center.isNaN { continue }

                var higherCount = 0
                var totalDiff: Float = 0

                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        let neighbor = dem[r + dr][c + dc]
                        if neighbor.isNaN { continue }
                        if neighbor - center > holeThreshold {
                            higherCount += 1
                            totalDiff += neighbor - center
                        }
                    }
                }

                if higherCount >= holeNeighborCount {
                    let avgDepth = totalDiff / Float(higherCount)
                    let worldPos = SIMD3<Float>(
                        Float(c) * cellSize + originOffset.x,
                        center,
                        Float(r) * cellSize + originOffset.y
                    )
                    let severity: HazardSeverity = avgDepth >= 1.5 ? .high : (avgDepth >= 0.8 ? .medium : .low)
                    hazards.append(Hazard(
                        type: .hole,
                        position: worldPos,
                        severity: severity,
                        description: "Hole: ~\(String(format: "%.1f", avgDepth))m deep"
                    ))
                }
            }
        }

        return hazards
    }

    // MARK: - Unstable Structure Detection

    /// Planes with very few inliers relative to their extent indicate fractured/unstable surfaces.
    private func detectUnstablePlanes(planes: [DetectedPlane]) -> [Hazard] {
        var hazards: [Hazard] = []

        for plane in planes {
            // A wall or ceiling with sparse inlier density may indicate structural damage
            guard plane.classification == .wall || plane.classification == .ceiling else { continue }
            guard plane.inlierCount > 0 else { continue }

            // Heuristic: if inlier count is suspiciously low for a detected plane, flag it
            if plane.inlierCount < 30 {
                hazards.append(Hazard(
                    type: .unstableStructure,
                    position: plane.centroid,
                    severity: .medium,
                    description: "Potentially unstable \(plane.classification.rawValue) (sparse surface)"
                ))
            }
        }

        return hazards
    }
}
