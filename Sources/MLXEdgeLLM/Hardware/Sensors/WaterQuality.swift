import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Water Quality Sensor Data Model

struct WaterQualityData: Codable {
    let pH: Double
    let TDS: Double
    let temperature: Double
    let turbidity: Double
    let timestamp: Date
    let location: CLLocationCoordinate2D
}

// MARK: - Water Quality Sensor Manager

class WaterQualitySensorManager: ObservableObject {
    @Published var waterQualityData: WaterQualityData?
    @Published var isSensorConnected: Bool = false
    
    private var locationManager: CLLocationManager
    private var arSession: ARSession
    
    init() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        
        arSession = ARSession()
    }
    
    func connectSensor() {
        // Simulate sensor connection
        isSensorConnected = true
        fetchWaterQualityData()
    }
    
    func disconnectSensor() {
        isSensorConnected = false
        waterQualityData = nil
    }
    
    private func fetchWaterQualityData() {
        guard isSensorConnected else { return }
        
        // Simulate fetching data from sensor
        let pH = Double.random(in: 6.0...8.0)
        let TDS = Double.random(in: 0...500)
        let temperature = Double.random(in: 10.0...30.0)
        let turbidity = Double.random(in: 0.0...10.0)
        let location = locationManager.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        
        let data = WaterQualityData(pH: pH, TDS: TDS, temperature: temperature, turbidity: turbidity, timestamp: Date(), location: location)
        waterQualityData = data
    }
}

// MARK: - CLLocationManagerDelegate

extension WaterQualitySensorManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse {
            locationManager.startUpdatingLocation()
        }
    }
}

// MARK: - Water Quality Sensor View Model

class WaterQualityViewModel: ObservableObject {
    @Published var sensorManager: WaterQualitySensorManager
    
    init(sensorManager: WaterQualitySensorManager) {
        self.sensorManager = sensorManager
    }
    
    func connectSensor() {
        sensorManager.connectSensor()
    }
    
    func disconnectSensor() {
        sensorManager.disconnectSensor()
    }
}

// MARK: - Water Quality Sensor View

struct WaterQualitySensorView: View {
    @StateObject private var viewModel: WaterQualityViewModel
    
    init(sensorManager: WaterQualitySensorManager) {
        _viewModel = StateObject(wrappedValue: WaterQualityViewModel(sensorManager: sensorManager))
    }
    
    var body: some View {
        VStack {
            if let data = viewModel.sensorManager.waterQualityData {
                WaterQualityDataView(data: data)
            } else {
                Text("No sensor data available")
            }
            
            Button(action: {
                viewModel.connectSensor()
            }) {
                Text("Connect Sensor")
            }
            .disabled(viewModel.sensorManager.isSensorConnected)
            
            Button(action: {
                viewModel.disconnectSensor()
            }) {
                Text("Disconnect Sensor")
            }
            .disabled(!viewModel.sensorManager.isSensorConnected)
        }
        .padding()
    }
}

// MARK: - Water Quality Data View

struct WaterQualityDataView: View {
    let data: WaterQualityData
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("pH: \(data.pH, specifier: "%.2f")")
            Text("TDS: \(data.TDS, specifier: "%.2f") ppm")
            Text("Temperature: \(data.temperature, specifier: "%.2f") °C")
            Text("Turbidity: \(data.turbidity, specifier: "%.2f") NTU")
            Text("Timestamp: \(data.timestamp, style: .date)")
            Text("Location: \(data.location.latitude), \(data.location.longitude)")
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Preview

struct WaterQualitySensorView_Previews: PreviewProvider {
    static var previews: some View {
        WaterQualitySensorView(sensorManager: WaterQualitySensorManager())
    }
}