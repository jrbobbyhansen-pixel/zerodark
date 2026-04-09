import Foundation
import SwiftUI

// MARK: - WeatherStation

class WeatherStation: ObservableObject {
    @Published var temperature: Double?
    @Published var humidity: Double?
    @Published var windSpeed: Double?
    @Published var pressure: Double?
    
    @Published var alertThresholds: AlertThresholds = AlertThresholds()
    
    private var sensor: Sensor?
    
    func connect(to sensor: Sensor) {
        self.sensor = sensor
        sensor.delegate = self
        sensor.startLogging()
    }
    
    func disconnect() {
        sensor?.stopLogging()
        sensor = nil
    }
}

// MARK: - Sensor

protocol Sensor {
    var delegate: SensorDelegate? { get set }
    func startLogging()
    func stopLogging()
}

// MARK: - SensorDelegate

protocol SensorDelegate: AnyObject {
    func sensor(_ sensor: Sensor, didUpdate temperature: Double)
    func sensor(_ sensor: Sensor, didUpdate humidity: Double)
    func sensor(_ sensor: Sensor, didUpdate windSpeed: Double)
    func sensor(_ sensor: Sensor, didUpdate pressure: Double)
}

// MARK: - KestrelSensor

class KestrelSensor: Sensor {
    weak var delegate: SensorDelegate?
    
    func startLogging() {
        // Start logging from Kestrel sensor
    }
    
    func stopLogging() {
        // Stop logging from Kestrel sensor
    }
    
    // Simulate sensor data update
    func simulateDataUpdate() {
        delegate?.sensor(self, didUpdate: 22.5) // Temperature in Celsius
        delegate?.sensor(self, didUpdate: 45.0) // Humidity in percentage
        delegate?.sensor(self, didUpdate: 10.0) // Wind speed in km/h
        delegate?.sensor(self, didUpdate: 1013.25) // Pressure in hPa
    }
}

// MARK: - AlertThresholds

struct AlertThresholds {
    var temperatureHigh: Double = 30.0
    var temperatureLow: Double = 10.0
    var humidityHigh: Double = 80.0
    var humidityLow: Double = 20.0
    var windSpeedHigh: Double = 50.0
    var pressureHigh: Double = 1020.0
    var pressureLow: Double = 980.0
}

// MARK: - WeatherStationView

struct WeatherStationView: View {
    @StateObject private var weatherStation = WeatherStation()
    
    var body: some View {
        VStack {
            Text("Temperature: \(weatherStation.temperature?.formatted() ?? "N/A")°C")
            Text("Humidity: \(weatherStation.humidity?.formatted() ?? "N/A")%")
            Text("Wind Speed: \(weatherStation.windSpeed?.formatted() ?? "N/A") km/h")
            Text("Pressure: \(weatherStation.pressure?.formatted() ?? "N/A") hPa")
            
            Button("Connect Sensor") {
                let kestrelSensor = KestrelSensor()
                weatherStation.connect(to: kestrelSensor)
                kestrelSensor.simulateDataUpdate()
            }
            
            Button("Disconnect Sensor") {
                weatherStation.disconnect()
            }
        }
        .padding()
    }
}

// MARK: - SensorDelegate Extension

extension WeatherStation: SensorDelegate {
    func sensor(_ sensor: Sensor, didUpdate temperature: Double) {
        self.temperature = temperature
    }
    
    func sensor(_ sensor: Sensor, didUpdate humidity: Double) {
        self.humidity = humidity
    }
    
    func sensor(_ sensor: Sensor, didUpdate windSpeed: Double) {
        self.windSpeed = windSpeed
    }
    
    func sensor(_ sensor: Sensor, didUpdate pressure: Double) {
        self.pressure = pressure
    }
}