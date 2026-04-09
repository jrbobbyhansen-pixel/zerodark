import Foundation
import SwiftUI
import CoreLocation

// MARK: - RallyPoint

struct RallyPoint {
    let name: String
    let location: CLLocationCoordinate2D
}

// MARK: - RallyPointSet

struct RallyPointSet {
    let name: String
    let primaryRallyPoint: RallyPoint
    let alternateRallyPoint: RallyPoint
}

// MARK: - RallyPointManager

class RallyPointManager: ObservableObject {
    @Published var rallyPointSets: [RallyPointSet] = []
    @Published var currentRallyPointSet: RallyPointSet?
    
    func setPrimaryRallyPoint(_ rallyPoint: RallyPoint, in set: RallyPointSet) {
        if let index = rallyPointSets.firstIndex(where: { $0.name == set.name }) {
            var updatedSet = set
            updatedSet.primaryRallyPoint = rallyPoint
            rallyPointSets[index] = updatedSet
        }
    }
    
    func setAlternateRallyPoint(_ rallyPoint: RallyPoint, in set: RallyPointSet) {
        if let index = rallyPointSets.firstIndex(where: { $0.name == set.name }) {
            var updatedSet = set
            updatedSet.alternateRallyPoint = rallyPoint
            rallyPointSets[index] = updatedSet
        }
    }
    
    func broadcastRallyPointSet(_ set: RallyPointSet) {
        // Implementation for broadcasting the rally point set to the team
    }
    
    func calculateETA(from location: CLLocationCoordinate2D, to rallyPoint: RallyPoint) -> TimeInterval {
        // Implementation for calculating ETA using CoreLocation
        return 0.0
    }
}

// MARK: - RallyPointView

struct RallyPointView: View {
    @StateObject private var viewModel = RallyPointManager()
    
    var body: some View {
        VStack {
            if let currentSet = viewModel.currentRallyPointSet {
                Text("Current Rally Point Set: \(currentSet.name)")
                Text("Primary Rally Point: \(currentSet.primaryRallyPoint.name)")
                Text("Alternate Rally Point: \(currentSet.alternateRallyPoint.name)")
                
                Button("Broadcast Rally Point Set") {
                    viewModel.broadcastRallyPointSet(currentSet)
                }
            } else {
                Text("No rally point set selected")
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct RallyPointView_Previews: PreviewProvider {
    static var previews: some View {
        RallyPointView()
    }
}