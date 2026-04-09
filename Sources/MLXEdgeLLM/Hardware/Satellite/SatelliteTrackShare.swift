import Foundation
import SwiftUI
import CoreLocation

// MARK: - SatelliteTrackShare

class SatelliteTrackShare: ObservableObject {
    @Published var isTracking = false
    @Published var trackInterval: TimeInterval = 60.0
    @Published var lastLocation: CLLocationCoordinate2D?
    
    private var locationManager: CLLocationManager
    private var timer: Timer?
    
    init() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }
    
    func startTracking() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        isTracking = true
        startTimer()
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        isTracking = false
        timer?.invalidate()
        timer = nil
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: trackInterval, repeats: true) { [weak self] _ in
            self?.sendLocation()
        }
    }
    
    private func sendLocation() {
        guard let location = locationManager.location else { return }
        lastLocation = location.coordinate
        // Implement satellite track sharing logic here
        print("Sending location: \(location.coordinate)")
    }
}

// MARK: - CLLocationManagerDelegate

extension SatelliteTrackShare: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - SatelliteTrackShareView

struct SatelliteTrackShareView: View {
    @StateObject private var viewModel = SatelliteTrackShare()
    
    var body: some View {
        VStack {
            Text("Satellite Track Sharing")
                .font(.largeTitle)
                .padding()
            
            Toggle("Start Tracking", isOn: $viewModel.isTracking)
                .onChange(of: viewModel.isTracking) { tracking in
                    if tracking {
                        viewModel.startTracking()
                    } else {
                        viewModel.stopTracking()
                    }
                }
            
            Text("Track Interval: \(Int(viewModel.trackInterval)) seconds")
                .padding()
            
            if let lastLocation = viewModel.lastLocation {
                Text("Last Location: \(lastLocation.latitude), \(lastLocation.longitude)")
                    .padding()
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct SatelliteTrackShareView_Previews: PreviewProvider {
    static var previews: some View {
        SatelliteTrackShareView()
    }
}