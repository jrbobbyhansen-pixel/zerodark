import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - WaterLevelTracker

class WaterLevelTracker: ObservableObject {
    @Published var waterLevels: [WaterLevel] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var peakPrediction: Date?

    private var locationManager: CLLocationManager
    private var arSession: ARSession

    init() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        arSession = ARSession()
    }

    func addWaterLevel(_ level: WaterLevel) {
        waterLevels.append(level)
        updatePeakPrediction()
    }

    func updatePeakPrediction() {
        guard let latestLevel = waterLevels.last else { return }
        let riseRate = calculateRiseRate()
        if riseRate > 0 {
            let timeToPeak = TimeInterval(latestLevel.level / riseRate)
            peakPrediction = Date().addingTimeInterval(timeToPeak)
        } else {
            peakPrediction = nil
        }
    }

    private func calculateRiseRate() -> Double {
        guard waterLevels.count > 1 else { return 0 }
        let latest = waterLevels.last!
        let previous = waterLevels[waterLevels.count - 2]
        let timeDifference = latest.timestamp.timeIntervalSince(previous.timestamp)
        return (latest.level - previous.level) / timeDifference
    }
}

// MARK: - WaterLevel

struct WaterLevel: Identifiable {
    let id = UUID()
    let level: Double
    let timestamp: Date
}

// MARK: - CLLocationManagerDelegate

extension WaterLevelTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }
}

// MARK: - WaterLevelView

struct WaterLevelView: View {
    @StateObject private var viewModel = WaterLevelTracker()

    var body: some View {
        VStack {
            if let currentLocation = viewModel.currentLocation {
                Text("Current Location: \(currentLocation.latitude), \(currentLocation.longitude)")
            } else {
                Text("Location not available")
            }

            List(viewModel.waterLevels) { level in
                Text("Level: \(level.level), Time: \(level.timestamp, style: .date)")
            }

            if let peakPrediction = viewModel.peakPrediction {
                Text("Peak Prediction: \(peakPrediction, style: .date)")
            } else {
                Text("No peak prediction available")
            }

            Button("Add Water Level") {
                let newLevel = WaterLevel(level: 10.0, timestamp: Date())
                viewModel.addWaterLevel(newLevel)
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct WaterLevelView_Previews: PreviewProvider {
    static var previews: some View {
        WaterLevelView()
    }
}