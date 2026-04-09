import Foundation
import SwiftUI
import CoreLocation

// MARK: - BuddySystem

class BuddySystem: ObservableObject {
    @Published var teamMembers: [TeamMember] = []
    @Published var lastCheckIn: Date = Date()
    @Published var isAlertActive: Bool = false
    @Published var alertMessage: String = ""

    private let locationManager = CLLocationManager()
    private let maxSeparationTime: TimeInterval = 300 // 5 minutes

    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func addTeamMember(name: String, location: CLLocationCoordinate2D) {
        let member = TeamMember(name: name, location: location)
        teamMembers.append(member)
    }

    func updateTeamMemberLocation(name: String, location: CLLocationCoordinate2D) {
        if let index = teamMembers.firstIndex(where: { $0.name == name }) {
            teamMembers[index].location = location
        }
    }

    func checkSeparation() {
        let currentTime = Date()
        if currentTime.timeIntervalSince(lastCheckIn) > maxSeparationTime {
            isAlertActive = true
            alertMessage = "Team members are separated for too long!"
        } else {
            isAlertActive = false
        }
        lastCheckIn = currentTime
    }
}

// MARK: - TeamMember

struct TeamMember: Identifiable {
    let id = UUID()
    var name: String
    var location: CLLocationCoordinate2D
}

// MARK: - CLLocationManagerDelegate

extension BuddySystem: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateTeamMemberLocation(name: "Your Name", location: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

// MARK: - BuddySystemView

struct BuddySystemView: View {
    @StateObject private var buddySystem = BuddySystem()

    var body: some View {
        VStack {
            $name(teamMembers: $buddySystem.teamMembers)
                .edgesIgnoringSafeArea(.all)

            Button(action: {
                buddySystem.checkSeparation()
            }) {
                Text("Check Separation")
            }
            .padding()

            if buddySystem.isAlertActive {
                AlertView(message: buddySystem.alertMessage)
            }
        }
        .onAppear {
            buddySystem.addTeamMember(name: "Your Name", location: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        }
    }
}

// MARK: - MapView

struct FieldBuddyMapSnippet: UIViewRepresentable {
    @Binding var teamMembers: [TeamMember]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        for member in teamMembers {
            let annotation = MKPointAnnotation()
            annotation.coordinate = member.location
            annotation.title = member.name
            uiView.addAnnotation(annotation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }
    }
}

// MARK: - AlertView

struct AlertView: View {
    let message: String

    var body: some View {
        Text(message)
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}