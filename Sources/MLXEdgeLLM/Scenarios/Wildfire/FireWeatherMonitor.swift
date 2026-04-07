import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - FireWeatherMonitor

class FireWeatherMonitor: ObservableObject {
    @Published var temperature: Double = 0.0
    @Published var humidity: Double = 0.0
    @Published var windSpeed: Double = 0.0
    @Published var windDirection: Double = 0.0
    @Published var fuelMoisture: Double = 0.0
    @Published var fireDangerIndex: Double = 0.0
    @Published var isRedFlagCondition: Bool = false

    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService()

    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func updateWeatherData() {
        guard let location = locationManager.location else { return }
        Task {
            do {
                let weatherData = try await weatherService.fetchWeatherData(for: location.coordinate)
                temperature = weatherData.temperature
                humidity = weatherData.humidity
                windSpeed = weatherData.windSpeed
                windDirection = weatherData.windDirection
                fuelMoisture = weatherData.fuelMoisture
                calculateFireDangerIndex()
                checkRedFlagCondition()
            } catch {
                print("Failed to fetch weather data: \(error)")
            }
        }
    }

    private func calculateFireDangerIndex() {
        // Simple fire danger index calculation
        fireDangerIndex = (temperature + humidity + windSpeed) / 3
    }

    private func checkRedFlagCondition() {
        // Red flag conditions: high temperature, low humidity, strong wind
        isRedFlagCondition = temperature > 30 && humidity < 20 && windSpeed > 20
    }
}

// MARK: - CLLocationManagerDelegate

extension FireWeatherMonitor: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateWeatherData()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }
}

// MARK: - WeatherService

actor WeatherService {
    func fetchWeatherData(for coordinate: CLLocationCoordinate2D) async throws -> WeatherData {
        // Simulate fetching weather data
        let temperature = Double.random(in: 20...40)
        let humidity = Double.random(in: 10...50)
        let windSpeed = Double.random(in: 0...30)
        let windDirection = Double.random(in: 0...360)
        let fuelMoisture = Double.random(in: 0...100)
        return WeatherData(temperature: temperature, humidity: humidity, windSpeed: windSpeed, windDirection: windDirection, fuelMoisture: fuelMoisture)
    }
}

// MARK: - WeatherData

struct WeatherData {
    let temperature: Double
    let humidity: Double
    let windSpeed: Double
    let windDirection: Double
    let fuelMoisture: Double
}

// MARK: - FireWeatherView

struct FireWeatherView: View {
    @StateObject private var fireWeatherMonitor = FireWeatherMonitor()

    var body: some View {
        VStack {
            Text("Fire Weather Monitor")
                .font(.largeTitle)
                .padding()

            HStack {
                VStack {
                    Text("Temperature: \(String(format: "%.1f", fireWeatherMonitor.temperature))°C")
                    Text("Humidity: \(String(format: "%.1f", fireWeatherMonitor.humidity))%")
                }
                VStack {
                    Text("Wind Speed: \(String(format: "%.1f", fireWeatherMonitor.windSpeed)) km/h")
                    Text("Wind Direction: \(String(format: "%.1f", fireWeatherMonitor.windDirection))°")
                }
            }
            .padding()

            Text("Fuel Moisture: \(String(format: "%.1f", fireWeatherMonitor.fuelMoisture))%")
                .padding()

            Text("Fire Danger Index: \(String(format: "%.1f", fireWeatherMonitor.fireDangerIndex))")
                .padding()

            Text(fireWeatherMonitor.isRedFlagCondition ? "Red Flag Condition Detected!" : "No Red Flag Condition")
                .foregroundColor(fireWeatherMonitor.isRedFlagCondition ? .red : .green)
                .padding()
        }
        .onAppear {
            fireWeatherMonitor.updateWeatherData()
        }
    }
}

// MARK: - Preview

struct FireWeatherView_Previews: PreviewProvider {
    static var previews: some View {
        FireWeatherView()
    }
}