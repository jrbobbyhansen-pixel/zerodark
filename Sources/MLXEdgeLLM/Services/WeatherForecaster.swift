import Foundation
import CoreLocation

final class WeatherForecaster: ObservableObject {
    @Published private(set) var barometricPressureTrend: BarometricPressureTrend = .stable
    @Published private(set) var stormWarning: Bool = false
    
    private var pressureReadings: [Double] = []
    private let maxReadings = 12 // For 12-24 hour trend analysis
    
    private let locationManager: CLLocationManager
    
    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
    }
    
    func addPressureReading(_ pressure: Double) {
        pressureReadings.append(pressure)
        if pressureReadings.count > maxReadings {
            pressureReadings.removeFirst()
        }
        analyzePressureTrend()
    }
    
    private func analyzePressureTrend() {
        guard let first = pressureReadings.first, let last = pressureReadings.last else {
            barometricPressureTrend = .stable
            stormWarning = false
            return
        }
        
        let trend = last - first
        if trend < -0.5 { // Example threshold for rapid drop
            barometricPressureTrend = .rapidDrop
            stormWarning = true
        } else if trend > 0.5 {
            barometricPressureTrend = .rapidRise
        } else {
            barometricPressureTrend = .stable
        }
        
        stormWarning = barometricPressureTrend == .rapidDrop
    }
}

extension WeatherForecaster: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Simulate pressure reading for demonstration purposes
        let simulatedPressure = location.altitude + Double.random(in: -10...10)
        addPressureReading(simulatedPressure)
    }
}

enum BarometricPressureTrend {
    case stable
    case rapidRise
    case rapidDrop
}