import Foundation
import SwiftUI
import CoreLocation

// MARK: - DSTAR Data Handler

class DstarDataHandler: ObservableObject {
    @Published var slowData: String = ""
    @Published var fastData: String = ""
    @Published var gpsPosition: CLLocationCoordinate2D?
    @Published var shortMessages: [String] = []
    @Published var callsignRouting: [String: String] = [:]

    private var locationManager: CLLocationManager

    init() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func handleSlowData(_ data: String) {
        slowData = data
    }

    func handleFastData(_ data: String) {
        fastData = data
    }

    func shareGPSPosition() {
        if let location = locationManager.location {
            gpsPosition = location.coordinate
        }
    }

    func receiveShortMessage(_ message: String) {
        shortMessages.append(message)
    }

    func routeCallsign(_ callsign: String, to destination: String) {
        callsignRouting[callsign] = destination
    }
}

// MARK: - CLLocationManagerDelegate

extension DstarDataHandler: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            gpsPosition = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

// MARK: - SwiftUI View

struct DstarDataView: View {
    @StateObject private var dataHandler = DstarDataHandler()

    var body: some View {
        VStack {
            Text("Slow Data: \(dataHandler.slowData)")
            Text("Fast Data: \(dataHandler.fastData)")
            if let gpsPosition = dataHandler.gpsPosition {
                Text("GPS Position: \(gpsPosition.latitude), \(gpsPosition.longitude)")
            } else {
                Text("GPS Position: Not available")
            }
            List(dataHandler.shortMessages, id: \.self) { message in
                Text(message)
            }
            List(dataHandler.callsignRouting) { callsign, destination in
                Text("\(callsign) -> \(destination)")
            }
        }
        .onAppear {
            dataHandler.shareGPSPosition()
        }
    }
}

// MARK: - Preview

struct DstarDataView_Previews: PreviewProvider {
    static var previews: some View {
        DstarDataView()
    }
}