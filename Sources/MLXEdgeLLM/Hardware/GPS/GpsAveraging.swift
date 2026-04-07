import Foundation
import CoreLocation
import SwiftUI

class GpsAveraging: ObservableObject {
    @Published var averagedLocation: CLLocationCoordinate2D?
    @Published var confidence: Double = 0.0
    @Published var waypoints: [CLLocationCoordinate2D] = []
    
    private var locationManager: CLLocationManager
    private var timer: Timer?
    private var averagingDuration: TimeInterval
    private var startTime: Date?
    
    init(duration: TimeInterval = 60.0) {
        self.averagingDuration = duration
        self.locationManager = CLLocationManager()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestWhenInUseAuthorization()
    }
    
    func startAveraging() {
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: averagingDuration, repeats: false) { [weak self] _ in
            self?.stopAveraging()
        }
        locationManager.startUpdatingLocation()
    }
    
    func stopAveraging() {
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        calculateAveragedLocation()
    }
    
    private func calculateAveragedLocation() {
        guard !waypoints.isEmpty else { return }
        
        let latitudeSum = waypoints.reduce(0) { $0 + $1.latitude }
        let longitudeSum = waypoints.reduce(0) { $0 + $1.longitude }
        let count = Double(waypoints.count)
        
        let averageLatitude = latitudeSum / count
        let averageLongitude = longitudeSum / count
        
        averagedLocation = CLLocationCoordinate2D(latitude: averageLatitude, longitude: averageLongitude)
        confidence = calculateConfidence()
        saveAveragedWaypoint()
    }
    
    private func calculateConfidence() -> Double {
        // Simple confidence calculation based on number of waypoints
        return min(1.0, Double(waypoints.count) / 10.0)
    }
    
    private func saveAveragedWaypoint() {
        guard let averagedLocation = averagedLocation else { return }
        waypoints.append(averagedLocation)
    }
}

extension GpsAveraging: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        waypoints.append(location.coordinate)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

struct GpsAveragingView: View {
    @StateObject private var gpsAveraging = GpsAveraging()
    
    var body: some View {
        VStack {
            if let averagedLocation = gpsAveraging.averagedLocation {
                Text("Averaged Location: \(averagedLocation.latitude), \(averagedLocation.longitude)")
            } else {
                Text("No averaged location yet")
            }
            
            Text("Confidence: \(gpsAveraging.confidence, specifier: "%.2f")")
            
            Button("Start Averaging") {
                gpsAveraging.startAveraging()
            }
            
            Button("Stop Averaging") {
                gpsAveraging.stopAveraging()
            }
        }
        .padding()
    }
}

struct GpsAveragingView_Previews: PreviewProvider {
    static var previews: some View {
        GpsAveragingView()
    }
}