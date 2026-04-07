import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ParticipantTracker

class ParticipantTracker: ObservableObject {
    @Published var participants: [Participant] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var isCheckingIn: Bool = false
    @Published var isEmergencyRecall: Bool = false
    
    private let locationManager = CLLocationManager()
    private let arSession = ARSession()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func checkInParticipant(_ participant: Participant) {
        participants.append(participant)
        isCheckingIn = false
    }
    
    func checkOutParticipant(_ participant: Participant) {
        participants.removeAll { $0.id == participant.id }
    }
    
    func initiateEmergencyRecall() {
        isEmergencyRecall = true
        // Additional logic for emergency recall
    }
    
    func stopEmergencyRecall() {
        isEmergencyRecall = false
    }
}

// MARK: - Participant

struct Participant: Identifiable {
    let id: UUID
    let name: String
    var location: CLLocationCoordinate2D?
}

// MARK: - CLLocationManagerDelegate

extension ParticipantTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last?.coordinate else { return }
        currentLocation = location
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

// MARK: - ParticipantTrackerView

struct ParticipantTrackerView: View {
    @StateObject private var tracker = ParticipantTracker()
    
    var body: some View {
        VStack {
            $name(location: tracker.currentLocation)
                .edgesIgnoringSafeArea(.all)
            
            List(tracker.participants) { participant in
                Text("\(participant.name) - \(participant.location?.description ?? "Unknown")")
            }
            
            Button("Check In Participant") {
                tracker.isCheckingIn = true
            }
            .sheet(isPresented: $tracker.isCheckingIn) {
                CheckInView(tracker: tracker)
            }
            
            Button("Emergency Recall") {
                tracker.initiateEmergencyRecall()
            }
            .alert(isPresented: $tracker.isEmergencyRecall) {
                Alert(title: Text("Emergency Recall"), message: Text("All participants are being recalled."), dismissButton: .default(Text("OK")) {
                    tracker.stopEmergencyRecall()
                })
            }
        }
    }
}

// MARK: - CheckInView

struct CheckInView: View {
    @ObservedObject var tracker: ParticipantTracker
    @State private var name: String = ""
    
    var body: some View {
        VStack {
            TextField("Participant Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button("Check In") {
                let participant = Participant(id: UUID(), name: name, location: tracker.currentLocation)
                tracker.checkInParticipant(participant)
            }
            .disabled(name.isEmpty)
        }
        .padding()
    }
}

// MARK: - MapView

struct ParticipantMapSnippet: UIViewRepresentable {
    var location: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        if let location = location {
            let region = MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000)
            mapView.setRegion(region, animated: true)
        }
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = location {
            let region = MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000)
            uiView.setRegion(region, animated: true)
        }
    }
}