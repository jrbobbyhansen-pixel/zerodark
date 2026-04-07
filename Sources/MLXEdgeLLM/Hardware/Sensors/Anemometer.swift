import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Anemometer Interface

class Anemometer: ObservableObject {
    @Published var windSpeed: Double = 0.0
    @Published var averageWindSpeed: Double = 0.0
    @Published var windDirection: CLLocationDirection? = nil
    
    private var windSpeedHistory: [Double] = []
    private let maxHistoryCount = 10
    
    private var locationManager: CLLocationManager
    
    init() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.startUpdatingHeading()
    }
    
    func updateWindSpeed(_ speed: Double) {
        windSpeed = speed
        windSpeedHistory.append(speed)
        if windSpeedHistory.count > maxHistoryCount {
            windSpeedHistory.removeFirst()
        }
        averageWindSpeed = windSpeedHistory.reduce(0, +) / Double(windSpeedHistory.count)
    }
}

// MARK: - CLLocationManagerDelegate

extension Anemometer: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        windDirection = newHeading.magneticHeading
    }
}

// MARK: - SwiftUI View

struct AnemometerView: View {
    @StateObject private var anemometer = Anemometer()
    
    var body: some View {
        VStack {
            Text("Wind Speed: \(anemometer.windSpeed, specifier: "%.1f") m/s")
                .font(.largeTitle)
            
            Text("Average Wind Speed: \(anemometer.averageWindSpeed, specifier: "%.1f") m/s")
                .font(.title2)
            
            if let direction = anemometer.windDirection {
                Text("Wind Direction: \(direction, specifier: "%.0f")°")
                    .font(.title2)
            } else {
                Text("Wind Direction: N/A")
                    .font(.title2)
            }
        }
        .padding()
        .onAppear {
            // Simulate wind speed updates
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                let randomSpeed = Double.random(in: 0...20)
                anemometer.updateWindSpeed(randomSpeed)
            }
        }
    }
}

// MARK: - Preview

struct AnemometerView_Previews: PreviewProvider {
    static var previews: some View {
        AnemometerView()
    }
}