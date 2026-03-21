// NavigationViewModel.swift — Navigation state management
import Foundation
import MapKit

struct Waypoint: Identifiable {
    let id = UUID()
    var name: String
    var coordinate: CLLocationCoordinate2D
    var altitude: Double = 0
    var timestamp: Date = Date()
    var lidarFingerprint: Data? = nil
    var type: String = "waypoint"
}

@MainActor
class NavigationViewModel: ObservableObject {
    @Published var waypoints: [Waypoint] = []
    @Published var isScanning = false
    @Published var downloadProgress: Double = 0
    @Published var selectedRegion: String = "default"
    
    func addWaypoint(_ waypoint: Waypoint) {
        waypoints.append(waypoint)
    }
    
    func clearWaypoints() {
        waypoints.removeAll()
    }
}
