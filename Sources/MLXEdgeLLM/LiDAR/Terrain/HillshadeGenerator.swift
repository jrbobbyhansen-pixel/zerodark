// HillshadeGenerator.swift — Analytical hillshade from DEM
// Computes surface normals via Horn's finite differences, then dots with sun direction vector
// Produces a grayscale UIImage where brightness = illumination intensity

import Foundation
import SwiftUI

// MARK: - HillshadeGenerator

class HillshadeGenerator: ObservableObject {
    @Published var hillshadeImage: UIImage?
    @Published var sunAngle: Double = 45.0       // Altitude angle above horizon (degrees)
    @Published var sunAzimuth: Double = 315.0    // Compass bearing of sun (degrees, 0=N, 90=E)

    private let demData: [[Double]]

    /// Cell size in meters
    var cellSize: Double = 1.0

    init(demData: [[Double]]) {
        self.demData = demData
    }

    /// Generate hillshade image using proper surface normals from finite differences.
    func generateHillshade() {
        let rows = demData.count
        guard rows >= 3, let cols = demData.first?.count, cols >= 3 else { return }

        // Sun direction vector (in terrain coordinate system)
        let altRad = sunAngle * .pi / 180.0
        let azRad = sunAzimuth * .pi / 180.0

        // Sun vector components (terrain coords: x=east, y=north, z=up)
        let sunX = cos(altRad) * sin(azRad)
        let sunY = cos(altRad) * cos(azRad)
        let sunZ = sin(altRad)

        // Compute hillshade values
        var values = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                // Horn's 3×3 kernel for surface normal
                let a = demData[r-1][c-1], b = demData[r-1][c], cc = demData[r-1][c+1]
                let d = demData[r][c-1],                         f = demData[r][c+1]
                let g = demData[r+1][c-1], h = demData[r+1][c], i = demData[r+1][c+1]

                // dz/dx and dz/dy using Horn's method
                let dzdx = ((cc + 2*f + i) - (a + 2*d + g)) / (8.0 * cellSize)
                let dzdy = ((a + 2*b + cc) - (g + 2*h + i)) / (8.0 * cellSize)

                // Surface normal = (-dzdx, -dzdy, 1) normalized
                let len = sqrt(dzdx * dzdx + dzdy * dzdy + 1.0)
                let nx = -dzdx / len
                let ny = -dzdy / len
                let nz = 1.0 / len

                // Dot product with sun vector = cos(angle between normal and sun)
                let illumination = max(0, nx * sunX + ny * sunY + nz * sunZ)
                values[r][c] = illumination
            }
        }

        // Copy edges
        for c in 0..<cols {
            values[0][c] = values[1][c]
            values[rows-1][c] = values[rows-2][c]
        }
        for r in 0..<rows {
            values[r][0] = values[r][1]
            values[r][cols-1] = values[r][cols-2]
        }

        // Render to UIImage
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cols, height: rows))
        hillshadeImage = renderer.image { ctx in
            let cgCtx = ctx.cgContext
            for r in 0..<rows {
                for c in 0..<cols {
                    let brightness = CGFloat(values[r][c])
                    cgCtx.setFillColor(UIColor(white: brightness, alpha: 1.0).cgColor)
                    cgCtx.fill(CGRect(x: c, y: r, width: 1, height: 1))
                }
            }
        }
    }

    /// Compute raw hillshade grid (0.0–1.0) without rendering to image.
    func computeHillshadeGrid() -> [[Double]] {
        let rows = demData.count
        guard rows >= 3, let cols = demData.first?.count, cols >= 3 else { return [] }

        let altRad = sunAngle * .pi / 180.0
        let azRad = sunAzimuth * .pi / 180.0
        let sunX = cos(altRad) * sin(azRad)
        let sunY = cos(altRad) * cos(azRad)
        let sunZ = sin(altRad)

        var grid = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)

        for r in 1..<(rows - 1) {
            for c in 1..<(cols - 1) {
                let a = demData[r-1][c-1], b = demData[r-1][c], cc = demData[r-1][c+1]
                let d = demData[r][c-1],                         f = demData[r][c+1]
                let g = demData[r+1][c-1], h = demData[r+1][c], i = demData[r+1][c+1]

                let dzdx = ((cc + 2*f + i) - (a + 2*d + g)) / (8.0 * cellSize)
                let dzdy = ((a + 2*b + cc) - (g + 2*h + i)) / (8.0 * cellSize)

                let len = sqrt(dzdx * dzdx + dzdy * dzdy + 1.0)
                let illumination = max(0, (-dzdx * sunX + -dzdy * sunY + sunZ) / len)
                grid[r][c] = illumination
            }
        }

        return grid
    }
}

// MARK: - Extensions

extension Double {
    var radians: Double {
        return self * .pi / 180
    }
}

// MARK: - Preview

struct HillshadeGeneratorPreview: View {
    @StateObject private var hillshadeGenerator = HillshadeGenerator(demData: [
        [0, 1, 2, 3, 4],
        [1, 3, 5, 7, 5],
        [2, 5, 10, 7, 4],
        [1, 3, 7, 5, 3],
        [0, 1, 4, 3, 2]
    ])

    var body: some View {
        VStack {
            if let hillshadeImage = hillshadeGenerator.hillshadeImage {
                Image(uiImage: hillshadeImage)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
            }
            Slider(value: $hillshadeGenerator.sunAngle, in: 0...90) {
                Text("Sun Angle: \(hillshadeGenerator.sunAngle, specifier: "%.0f")°")
            }
            Slider(value: $hillshadeGenerator.sunAzimuth, in: 0...360) {
                Text("Sun Azimuth: \(hillshadeGenerator.sunAzimuth, specifier: "%.0f")°")
            }
            Button("Generate Hillshade") {
                hillshadeGenerator.generateHillshade()
            }
        }
        .padding()
    }
}

struct HillshadeGeneratorPreview_Previews: PreviewProvider {
    static var previews: some View {
        HillshadeGeneratorPreview()
    }
}
