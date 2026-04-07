import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - PointCloud

struct PointCloud {
    let points: [Point]
}

struct Point {
    let position: SIMD3<Float>
    let intensity: Float
}

// MARK: - CloudComparison

class CloudComparison: ObservableObject {
    @Published var distance: Float = 0.0
    @Published var changeDetection: [Point] = []
    @Published var volumetricDifference: Float = 0.0

    func compare(cloud1: PointCloud, cloud2: PointCloud) {
        calculateDistance(cloud1: cloud1, cloud2: cloud2)
        detectChanges(cloud1: cloud1, cloud2: cloud2)
        calculateVolumetricDifference(cloud1: cloud1, cloud2: cloud2)
    }

    private func calculateDistance(cloud1: PointCloud, cloud2: PointCloud) {
        guard !cloud1.points.isEmpty && !cloud2.points.isEmpty else { return }
        let distance = cloud1.points.reduce(0) { acc, point in
            acc + cloud2.points.map { simd_length(point.position - $0.position) }.min() ?? 0
        }
        self.distance = distance / Float(cloud1.points.count)
    }

    private func detectChanges(cloud1: PointCloud, cloud2: PointCloud) {
        let cloud1Set = Set(cloud1.points.map { $0.position })
        let cloud2Set = Set(cloud2.points.map { $0.position })
        let addedPoints = cloud2Set.subtracting(cloud1Set).map { Point(position: $0, intensity: 0) }
        let removedPoints = cloud1Set.subtracting(cloud2Set).map { Point(position: $0, intensity: 0) }
        self.changeDetection = addedPoints + removedPoints
    }

    private func calculateVolumetricDifference(cloud1: PointCloud, cloud2: PointCloud) {
        let volume1 = cloud1.points.reduce(0) { acc, point in
            acc + point.intensity
        }
        let volume2 = cloud2.points.reduce(0) { acc, point in
            acc + point.intensity
        }
        self.volumetricDifference = volume2 - volume1
    }
}

// MARK: - CloudComparisonView

struct CloudComparisonView: View {
    @StateObject private var viewModel = CloudComparison()

    var body: some View {
        VStack {
            Text("Cloud Comparison")
                .font(.largeTitle)
                .padding()

            Text("Distance: \(viewModel.distance, specifier: "%.2f")")
                .font(.title2)
                .padding()

            Text("Change Detection: \(viewModel.changeDetection.count) points")
                .font(.title2)
                .padding()

            Text("Volumetric Difference: \(viewModel.volumetricDifference, specifier: "%.2f")")
                .font(.title2)
                .padding()

            Button("Compare Clouds") {
                let cloud1 = PointCloud(points: [
                    Point(position: SIMD3<Float>(0, 0, 0), intensity: 1),
                    Point(position: SIMD3<Float>(1, 1, 1), intensity: 2)
                ])
                let cloud2 = PointCloud(points: [
                    Point(position: SIMD3<Float>(0, 0, 0), intensity: 1),
                    Point(position: SIMD3<Float>(1, 1, 2), intensity: 3)
                ])
                viewModel.compare(cloud1: cloud1, cloud2: cloud2)
            }
            .padding()
        }
    }
}

// MARK: - Preview

struct CloudComparisonView_Previews: PreviewProvider {
    static var previews: some View {
        CloudComparisonView()
    }
}