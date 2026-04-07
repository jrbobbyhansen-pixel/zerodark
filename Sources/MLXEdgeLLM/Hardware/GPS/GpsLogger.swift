import Foundation
import CoreLocation
import SwiftUI

class GpsLogger: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var batteryLevel: Double = 1.0
    @Published var isLogging: Bool = false
    
    private let locationManager = CLLocationManager()
    private let batteryMonitor = UIDevice.current
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        batteryMonitor.isBatteryMonitoringEnabled = true
    }
    
    func startLogging() {
        isLogging = true
        locationManager.startUpdatingLocation()
    }
    
    func stopLogging() {
        isLogging = false
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        location = newLocation
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
    
    func updateBatteryLevel() {
        batteryLevel = batteryMonitor.batteryLevel
    }
}

struct GpsLoggerView: View {
    @StateObject private var gpsLogger = GpsLogger()
    
    var body: some View {
        VStack {
            Text("GPS Logger")
                .font(.largeTitle)
                .padding()
            
            if let location = gpsLogger.location {
                Text("Latitude: \(location.coordinate.latitude, specifier: "%.6f")")
                Text("Longitude: \(location.coordinate.longitude, specifier: "%.6f")")
            } else {
                Text("No location data available")
            }
            
            Text("Battery Level: \(gpsLogger.batteryLevel, specifier: "%.2f")")
            
            Button(action: {
                gpsLogger.startLogging()
            }) {
                Text("Start Logging")
            }
            .padding()
            
            Button(action: {
                gpsLogger.stopLogging()
            }) {
                Text("Stop Logging")
            }
            .padding()
        }
        .onAppear {
            gpsLogger.updateBatteryLevel()
        }
    }
}

struct GpsLoggerView_Previews: PreviewProvider {
    static var previews: some View {
        GpsLoggerView()
    }
}