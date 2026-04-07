import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - P25DataHandler

class P25DataHandler: ObservableObject {
    @Published var location: CLLocationCoordinate2D?
    @Published var statusMessage: String?
    @Published var emergencyAlert: String?
    @Published var registeredUnits: [String] = []

    private let locationManager = CLLocationManager()
    private let audioPlayer = AVAudioPlayer()

    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        do {
            audioPlayer.prepareToPlay()
        } catch {
            print("Failed to prepare audio player: \(error)")
        }
    }

    func registerUnit(_ unitID: String) {
        registeredUnits.append(unitID)
    }

    func handleP25Data(data: Data) {
        // Placeholder for P25 data handling logic
        // This should parse the data and update the appropriate properties
        // For example, if the data contains location information:
        if let locationData = parseLocationData(from: data) {
            location = locationData
        }
        // Similarly, handle status messages, emergency alerts, etc.
    }

    private func parseLocationData(from data: Data) -> CLLocationCoordinate2D? {
        // Placeholder for location data parsing logic
        // This should extract latitude and longitude from the data
        // For example, if the data is in JSON format:
        // return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return nil
    }

    func playEmergencyAlertSound() {
        guard let soundURL = Bundle.main.url(forResource: "emergency_alert", withExtension: "mp3") else { return }
        do {
            audioPlayer.url = soundURL
            audioPlayer.play()
        } catch {
            print("Failed to play emergency alert sound: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension P25DataHandler: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error)")
    }
}

// MARK: - P25DataView

struct P25DataView: View {
    @StateObject private var viewModel = P25DataHandler()

    var body: some View {
        VStack {
            if let location = viewModel.location {
                Text("Location: \(location.latitude), \(location.longitude)")
            } else {
                Text("Location not available")
            }

            if let statusMessage = viewModel.statusMessage {
                Text("Status: \(statusMessage)")
            } else {
                Text("No status message")
            }

            if let emergencyAlert = viewModel.emergencyAlert {
                Text("Emergency Alert: \(emergencyAlert)")
            } else {
                Text("No emergency alert")
            }

            List(viewModel.registeredUnits, id: \.self) { unit in
                Text("Unit: \(unit)")
            }

            Button("Register Unit") {
                viewModel.registerUnit("Unit123")
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct P25DataView_Previews: PreviewProvider {
    static var previews: some View {
        P25DataView()
    }
}