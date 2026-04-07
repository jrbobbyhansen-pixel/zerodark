import Foundation
import CoreLocation
import SwiftUI

struct DistanceBearing {
    let pointA: CLLocationCoordinate2D
    let pointB: CLLocationCoordinate2D
    
    var distance: CLLocationDistance {
        let locationA = CLLocation(latitude: pointA.latitude, longitude: pointA.longitude)
        let locationB = CLLocation(latitude: pointB.latitude, longitude: pointB.longitude)
        return locationA.distance(from: locationB)
    }
    
    var bearing: CLLocationDirection {
        let locationA = CLLocation(latitude: pointA.latitude, longitude: pointA.longitude)
        let locationB = CLLocation(latitude: pointB.latitude, longitude: pointB.longitude)
        return locationA.bearing(to: locationB)
    }
}

extension CLLocation {
    func bearing(to location: CLLocation) -> CLLocationDirection {
        let lat1 = self.coordinate.latitude.toRadians()
        let lon1 = self.coordinate.longitude.toRadians()
        let lat2 = location.coordinate.latitude.toRadians()
        let lon2 = location.coordinate.longitude.toRadians()
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        
        return radiansBearing.toDegrees()
    }
}

extension Double {
    func toRadians() -> Double {
        return self * .pi / 180
    }
    
    func toDegrees() -> Double {
        return self * 180 / .pi
    }
}

class DistanceBearingViewModel: ObservableObject {
    @Published var waypoints: [CLLocationCoordinate2D] = []
    @Published var selectedWaypointIndex: Int? = nil
    
    func addWaypoint(_ waypoint: CLLocationCoordinate2D) {
        waypoints.append(waypoint)
    }
    
    func removeWaypoint(at index: Int) {
        waypoints.remove(at: index)
        if selectedWaypointIndex == index {
            selectedWaypointIndex = nil
        } else if selectedWaypointIndex! > index {
            selectedWaypointIndex! -= 1
        }
    }
    
    func calculateDistanceAndBearing(from indexA: Int, to indexB: Int) -> DistanceBearing? {
        guard indexA < waypoints.count, indexB < waypoints.count else { return nil }
        let pointA = waypoints[indexA]
        let pointB = waypoints[indexB]
        return DistanceBearing(pointA: pointA, pointB: pointB)
    }
}

struct DistanceBearingView: View {
    @StateObject private var viewModel = DistanceBearingViewModel()
    
    var body: some View {
        VStack {
            List(0..<viewModel.waypoints.count, id: \.self) { index in
                HStack {
                    Text("Waypoint \(index + 1)")
                    Spacer()
                    Button(action: {
                        viewModel.selectedWaypointIndex = index
                    }) {
                        Text("Select")
                    }
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { index in
                    viewModel.removeWaypoint(at: index)
                }
            }
            
            if let selectedIndex = viewModel.selectedWaypointIndex {
                Text("Selected Waypoint: \(selectedIndex + 1)")
                Button(action: {
                    viewModel.selectedWaypointIndex = nil
                }) {
                    Text("Deselect")
                }
            }
            
            Button(action: {
                // Add new waypoint logic here
            }) {
                Text("Add Waypoint")
            }
        }
        .padding()
    }
}

struct DistanceBearingView_Previews: PreviewProvider {
    static var previews: some View {
        DistanceBearingView()
    }
}