import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TrailerTracker

class TrailerTracker: ObservableObject {
    @Published var lastSeenLocation: CLLocationCoordinate2D?
    @Published var isMoving: Bool = false
    @Published var inventory: [String: Int] = [:]
    
    private let locationManager = CLLocationManager()
    private var previousLocation: CLLocation?
    
    init() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func updateInventory(item: String, quantity: Int) {
        inventory[item] = quantity
    }
}

// MARK: - CLLocationManagerDelegate

extension TrailerTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        if let previousLocation = previousLocation {
            let distance = location.distance(from: previousLocation)
            isMoving = distance > 10 // Threshold for movement
        }
        
        lastSeenLocation = location.coordinate
        previousLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

// MARK: - TrailerTrackerView

struct TrailerTrackerView: View {
    @StateObject private var tracker = TrailerTracker()
    
    var body: some View {
        VStack {
            if let lastSeenLocation = tracker.lastSeenLocation {
                Text("Last Seen: \(lastSeenLocation.latitude), \(lastSeenLocation.longitude)")
            } else {
                Text("Location not available")
            }
            
            Text("Is Moving: \(tracker.isMoving ? "Yes" : "No")")
            
            List(tracker.inventory.keys, id: \.self) { item in
                HStack {
                    Text(item)
                    Spacer()
                    Text("\(tracker.inventory[item] ?? 0)")
                }
            }
            .navigationTitle("Trailer Tracker")
        }
        .onAppear {
            tracker.locationManager.requestWhenInUseAuthorization()
            tracker.locationManager.startUpdatingLocation()
        }
    }
}

// MARK: - Preview

struct TrailerTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        TrailerTrackerView()
    }
}