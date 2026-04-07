import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - HillshadeGenerator

class HillshadeGenerator: ObservableObject {
    @Published var hillshadeImage: UIImage?
    @Published var sunAngle: Double = 45.0
    @Published var sunAzimuth: Double = 315.0
    
    private let demData: [[Double]]
    
    init(demData: [[Double]]) {
        self.demData = demData
    }
    
    func generateHillshade() {
        let width = demData.count
        let height = demData.first?.count ?? 0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        
        hillshadeImage = renderer.image { context in
            let context = context.cgContext
            let dx = cos(sunAngle.radians) * cos(sunAzimuth.radians)
            let dy = cos(sunAngle.radians) * sin(sunAzimuth.radians)
            let dz = sin(sunAngle.radians)
            
            for y in 0..<height {
                for x in 0..<width {
                    let z = demData[x][y]
                    let nx = -dx
                    let ny = -dy
                    let nz = dz
                    
                    let intensity = max(0, nx * 0 + ny * 0 + nz * 1)
                    let color = UIColor(hue: 0.0, saturation: 0.0, brightness: intensity, alpha: 1.0)
                    
                    context.setFillColor(color.cgColor)
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
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
        [0, 1, 2],
        [3, 4, 5],
        [6, 7, 8]
    ])
    
    var body: some View {
        VStack {
            if let hillshadeImage = hillshadeGenerator.hillshadeImage {
                Image(uiImage: hillshadeImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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