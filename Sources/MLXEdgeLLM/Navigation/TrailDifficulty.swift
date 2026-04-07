import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - TrailDifficulty

struct TrailDifficulty {
    let slope: Double
    let exposure: Double
    let terrainRoughness: Double
    
    var difficulty: Int {
        let slopeFactor = max(0, min(1, slope / 50.0)) // Assume slope is in degrees
        let exposureFactor = max(0, min(1, exposure / 10.0)) // Assume exposure is in percentage
        let terrainFactor = max(0, min(1, terrainRoughness / 5.0)) // Assume terrain roughness is in meters
        
        let averageFactor = (slopeFactor + exposureFactor + terrainFactor) / 3.0
        return Int(round(averageFactor * 5))
    }
}

// MARK: - TrailSegment

struct TrailSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let slope: Double
    let exposure: Double
    let terrainRoughness: Double
    
    var difficulty: TrailDifficulty {
        TrailDifficulty(slope: slope, exposure: exposure, terrainRoughness: terrainRoughness)
    }
}

// MARK: - TrailRoute

struct TrailRoute {
    let segments: [TrailSegment]
    
    var difficultyProfile: [Int] {
        segments.map { $0.difficulty.difficulty }
    }
}

// MARK: - TrailDifficultyViewModel

class TrailDifficultyViewModel: ObservableObject {
    @Published var route: TrailRoute = TrailRoute(segments: [])
    
    func updateRoute(_ segments: [TrailSegment]) {
        route = TrailRoute(segments: segments)
    }
}

// MARK: - TrailDifficultyView

struct TrailDifficultyView: View {
    @StateObject private var viewModel = TrailDifficultyViewModel()
    
    var body: some View {
        VStack {
            Text("Trail Difficulty Profile")
                .font(.largeTitle)
                .padding()
            
            List(viewModel.route.segments.indices, id: \.self) { index in
                let segment = viewModel.route.segments[index]
                HStack {
                    Text("Segment \(index + 1)")
                        .font(.headline)
                    Spacer()
                    Text("Difficulty: \(segment.difficulty.difficulty)")
                        .font(.subheadline)
                }
            }
            .padding()
            
            Button(action: {
                // Example of updating the route
                let newSegments = [
                    TrailSegment(start: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), end: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), slope: 10.0, exposure: 5.0, terrainRoughness: 2.0),
                    TrailSegment(start: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), end: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196), slope: 20.0, exposure: 10.0, terrainRoughness: 3.0)
                ]
                viewModel.updateRoute(newSegments)
            }) {
                Text("Update Route")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
    }
}

// MARK: - Preview

struct TrailDifficultyView_Previews: PreviewProvider {
    static var previews: some View {
        TrailDifficultyView()
    }
}