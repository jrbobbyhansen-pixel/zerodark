// ContourExtraction.swift — Marching squares contour extraction from DEM
// Traces iso-elevation lines through bilinear interpolation on grid cells
// Produces polyline segments for each contour level

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Contour Extraction

struct ContourExtraction {
    let dem: DigitalElevationModel
    let interval: Double

    /// Extract contour lines at the given elevation interval using marching squares.
    func extractContours() -> [Contour] {
        var contours: [Contour] = []

        let minE = floor(dem.minElevation / interval) * interval
        let maxE = ceil(dem.maxElevation / interval) * interval

        for elevation in stride(from: minE, through: maxE, by: interval) {
            let segments = marchingSquares(elevation: elevation)
            let lines = chainSegments(segments)
            for line in lines {
                if line.count >= 2 {
                    contours.append(Contour(elevation: elevation, points: line))
                }
            }
        }

        return contours
    }

    // MARK: - Marching Squares

    /// For each 2×2 cell, classify corners as above/below the threshold
    /// and emit line segments through interpolated edge crossings.
    private func marchingSquares(elevation: Double) -> [(SIMD2<Double>, SIMD2<Double>)] {
        var segments: [(SIMD2<Double>, SIMD2<Double>)] = []

        for r in 0..<(dem.height - 1) {
            for c in 0..<(dem.width - 1) {
                // Corner values: TL(0), TR(1), BR(2), BL(3)
                let tl = dem.grid[r][c]
                let tr = dem.grid[r][c+1]
                let br = dem.grid[r+1][c+1]
                let bl = dem.grid[r+1][c]

                // Binary index: bit 3=TL, bit 2=TR, bit 1=BR, bit 0=BL
                var index = 0
                if tl >= elevation { index |= 8 }
                if tr >= elevation { index |= 4 }
                if br >= elevation { index |= 2 }
                if bl >= elevation { index |= 1 }

                // Skip all-in or all-out
                if index == 0 || index == 15 { continue }

                // Edge interpolation points
                let top    = interpolateEdge(x1: Double(c), y1: Double(r), v1: tl,
                                             x2: Double(c+1), y2: Double(r), v2: tr, level: elevation)
                let right  = interpolateEdge(x1: Double(c+1), y1: Double(r), v1: tr,
                                             x2: Double(c+1), y2: Double(r+1), v2: br, level: elevation)
                let bottom = interpolateEdge(x1: Double(c), y1: Double(r+1), v1: bl,
                                             x2: Double(c+1), y2: Double(r+1), v2: br, level: elevation)
                let left   = interpolateEdge(x1: Double(c), y1: Double(r), v1: tl,
                                             x2: Double(c), y2: Double(r+1), v2: bl, level: elevation)

                // Marching squares lookup (16 cases)
                switch index {
                case 1:  segments.append((left, bottom))
                case 2:  segments.append((bottom, right))
                case 3:  segments.append((left, right))
                case 4:  segments.append((top, right))
                case 5:  // Saddle: use center value to disambiguate
                    let center = (tl + tr + br + bl) / 4.0
                    if center >= elevation {
                        segments.append((top, left))
                        segments.append((bottom, right))
                    } else {
                        segments.append((top, right))
                        segments.append((left, bottom))
                    }
                case 6:  segments.append((top, bottom))
                case 7:  segments.append((top, left))
                case 8:  segments.append((top, left))
                case 9:  segments.append((top, bottom))
                case 10: // Saddle
                    let center = (tl + tr + br + bl) / 4.0
                    if center >= elevation {
                        segments.append((top, right))
                        segments.append((left, bottom))
                    } else {
                        segments.append((top, left))
                        segments.append((bottom, right))
                    }
                case 11: segments.append((top, right))
                case 12: segments.append((left, right))
                case 13: segments.append((bottom, right))
                case 14: segments.append((left, bottom))
                default: break
                }
            }
        }

        return segments
    }

    /// Linear interpolation along a cell edge to find where elevation crosses the threshold.
    private func interpolateEdge(x1: Double, y1: Double, v1: Double,
                                 x2: Double, y2: Double, v2: Double,
                                 level: Double) -> SIMD2<Double> {
        let dv = v2 - v1
        let t: Double = abs(dv) > 1e-10 ? (level - v1) / dv : 0.5
        let clampedT = max(0, min(1, t))
        return SIMD2(x1 + clampedT * (x2 - x1), y1 + clampedT * (y2 - y1))
    }

    // MARK: - Segment Chaining

    /// Chain loose segments into polylines by matching endpoints.
    private func chainSegments(_ segments: [(SIMD2<Double>, SIMD2<Double>)]) -> [[SIMD2<Double>]] {
        guard !segments.isEmpty else { return [] }

        var remaining = segments
        var chains: [[SIMD2<Double>]] = []

        while !remaining.isEmpty {
            var chain = [remaining[0].0, remaining[0].1]
            remaining.removeFirst()

            var changed = true
            while changed {
                changed = false
                for i in (0..<remaining.count).reversed() {
                    let seg = remaining[i]
                    let eps = 1e-6
                    if distance(chain.last!, seg.0) < eps {
                        chain.append(seg.1)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.last!, seg.1) < eps {
                        chain.append(seg.0)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.first!, seg.1) < eps {
                        chain.insert(seg.0, at: 0)
                        remaining.remove(at: i)
                        changed = true
                    } else if distance(chain.first!, seg.0) < eps {
                        chain.insert(seg.1, at: 0)
                        remaining.remove(at: i)
                        changed = true
                    }
                }
            }

            chains.append(chain)
        }

        return chains
    }

    private func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = a - b
        return sqrt(d.x * d.x + d.y * d.y)
    }
}

// MARK: - Digital Elevation Model

struct DigitalElevationModel {
    let grid: [[Double]]
    let width: Int
    let height: Int
    let minElevation: Double
    let maxElevation: Double
    /// Cell size in meters
    let cellSize: Double

    init(grid: [[Double]], cellSize: Double = 0.5) {
        self.grid = grid
        self.height = grid.count
        self.width = grid.first?.count ?? 0
        self.cellSize = cellSize
        let flat = grid.flatMap { $0 }
        self.minElevation = flat.min() ?? 0
        self.maxElevation = flat.max() ?? 0
    }

    /// Convert grid position to world coordinates (meters from origin).
    func worldPosition(at row: Int, col: Int) -> SIMD2<Double> {
        SIMD2(Double(col) * cellSize, Double(row) * cellSize)
    }
}

// MARK: - Contour

struct Contour: Identifiable {
    let id = UUID()
    let elevation: Double
    /// Points in grid coordinates (col, row as doubles)
    let points: [SIMD2<Double>]
}

// MARK: - ViewModel

class ContourExtractionViewModel: ObservableObject {
    @Published var contours: [Contour] = []

    private let dem: DigitalElevationModel
    private let interval: Double

    init(dem: DigitalElevationModel, interval: Double) {
        self.dem = dem
        self.interval = interval
    }

    func extractContours() {
        let extractor = ContourExtraction(dem: dem, interval: interval)
        contours = extractor.extractContours()
    }
}

// MARK: - SwiftUI View

struct ContourMapView: View {
    @StateObject private var viewModel: ContourExtractionViewModel

    init(dem: DigitalElevationModel, interval: Double) {
        _viewModel = StateObject(wrappedValue: ContourExtractionViewModel(dem: dem, interval: interval))
    }

    var body: some View {
        VStack {
            Text("Contour Lines: \(viewModel.contours.count)")
                .font(.headline)

            Canvas { context, size in
                guard !viewModel.contours.isEmpty else { return }
                let scale = min(size.width, size.height) / 20.0

                for contour in viewModel.contours {
                    guard contour.points.count >= 2 else { continue }
                    var path = Path()
                    let first = contour.points[0]
                    path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                    for pt in contour.points.dropFirst() {
                        path.addLine(to: CGPoint(x: pt.x * scale, y: pt.y * scale))
                    }
                    context.stroke(path, with: .color(.blue), lineWidth: 1)
                }
            }
            .frame(height: 300)
            .background(Color(.systemBackground))
        }
        .onAppear { viewModel.extractContours() }
    }
}
