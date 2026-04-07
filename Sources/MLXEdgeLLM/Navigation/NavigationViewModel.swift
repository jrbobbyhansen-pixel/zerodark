// NavigationViewModel.swift — Navigation state management
import Foundation
import MapKit

struct NavViewWaypoint: Identifiable {
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
    @Published var waypoints: [NavViewWaypoint] = []
    @Published var isScanning = false
    @Published var downloadProgress: Double = 0
    @Published var selectedRegion: String = "default"
    
    func addNavViewWaypoint(_ waypoint: NavViewWaypoint) {
        waypoints.append(waypoint)
    }
    
    func clearWaypoints() {
        waypoints.removeAll()
    }
}
