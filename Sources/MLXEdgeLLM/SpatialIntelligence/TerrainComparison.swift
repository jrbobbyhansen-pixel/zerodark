import Foundation
import SwiftUI
import ARKit

// MARK: - TerrainComparison

class TerrainComparison: ObservableObject {
    @Published var firstScan: [ARMeshResource] = []
    @Published var secondScan: [ARMeshResource] = []
    @Published var differences: [ARMeshResource] = []
    
    func compareScans() {
        differences = firstScan.filter { firstMesh in
            !secondScan.contains { secondMesh in
                firstMesh.geometry.bounds == secondMesh.geometry.bounds
            }
        }
    }
}

// MARK: - ARMeshResource

struct ARMeshResource: Identifiable {
    let id = UUID()
    let geometry: ARMeshGeometry
}

// MARK: - ARMeshGeometry

struct ARMeshGeometry {
    let bounds: ARMeshBounds
}

// MARK: - ARMeshBounds

struct ARMeshBounds {
    let min: SIMD3<Float>
    let max: SIMD3<Float>
}

// MARK: - TerrainComparisonView

struct TerrainComparisonView: View {
    @StateObject private var viewModel = TerrainComparison()
    
    var body: some View {
        VStack {
            Button("Compare Scans") {
                viewModel.compareScans()
            }
            
            List(viewModel.differences, id: \.id) { mesh in
                Text("Difference at \(mesh.geometry.bounds.min)")
            }
        }
    }
}

// MARK: - Preview

struct TerrainComparisonView_Previews: PreviewProvider {
    static var previews: some View {
        TerrainComparisonView()
    }
}