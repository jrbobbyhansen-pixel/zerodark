import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - QuickMessages

struct QuickMessages {
    static let sitrepTemplate = "SITREP: Location: %@, Time: %@, Status: %@"
    static let medevacTemplate = """
MEDEVAC 9-LINE:
1. Location: %@
2. Time: %@
3. Patient Name: %@
4. Condition: %@
5. Blood Pressure: %@
6. Heart Rate: %@
7. Breathing: %@
8. Injuries: %@
9. Additional Notes: %@
"""
    static let contactReportTemplate = "Contact Report: Location: %@, Time: %@, Contact: %@, Details: %@"
}

// MARK: - MessageViewModel

class MessageViewModel: ObservableObject {
    @Published var location: CLLocationCoordinate2D?
    @Published var currentTime: Date = Date()
    @Published var status: String = ""
    @Published var patientName: String = ""
    @Published var condition: String = ""
    @Published var bloodPressure: String = ""
    @Published var heartRate: String = ""
    @Published var breathing: String = ""
    @Published var injuries: String = ""
    @Published var additionalNotes: String = ""
    @Published var contactName: String = ""
    @Published var contactDetails: String = ""

    func formatSITREP() -> String {
        guard let location = location else { return "" }
        return String(format: QuickMessages.sitrepTemplate, location.description, currentTime.formatted(), status)
    }

    func formatMEDEVAC() -> String {
        guard let location = location else { return "" }
        return String(format: QuickMessages.medevacTemplate, location.description, currentTime.formatted(), patientName, condition, bloodPressure, heartRate, breathing, injuries, additionalNotes)
    }

    func formatContactReport() -> String {
        guard let location = location else { return "" }
        return String(format: QuickMessages.contactReportTemplate, location.description, currentTime.formatted(), contactName, contactDetails)
    }
}

// MARK: - QuickMessageView

struct QuickMessageView: View {
    @StateObject private var viewModel = MessageViewModel()
    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        VStack {
            Button("Send SITREP") {
                let message = viewModel.formatSITREP()
                sendMessage(message)
            }
            Button("Send MEDEVAC") {
                let message = viewModel.formatMEDEVAC()
                sendMessage(message)
            }
            Button("Send Contact Report") {
                let message = viewModel.formatContactReport()
                sendMessage(message)
            }
        }
        .onAppear {
            viewModel.location = locationManager.currentLocation
            viewModel.currentTime = Date()
        }
    }

    private func sendMessage(_ message: String) {
        // Implementation for sending message
        print("Message sent: \(message)")
    }
}

// MARK: - LocationManager

class LocationManager: ObservableObject {
    @Published var currentLocation: CLLocationCoordinate2D?

    init() {
        fetchLocation()
    }

    private func fetchLocation() {
        let locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
        manager.stopUpdatingLocation()
    }
}