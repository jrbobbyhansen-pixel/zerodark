import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - DebriefManager

class DebriefManager: ObservableObject {
    @Published var scheduledSessions: [DebriefSession] = []
    @Published var currentSession: DebriefSession?
    @Published var attendance: [String: Bool] = [:]
    @Published var documentation: String = ""

    func scheduleSession(date: Date, location: CLLocationCoordinate2D, talkingPoints: [String]) {
        let session = DebriefSession(date: date, location: location, talkingPoints: talkingPoints)
        scheduledSessions.append(session)
    }

    func startSession(session: DebriefSession) {
        currentSession = session
        attendance = session.talkingPoints.reduce(into: [:]) { $0[$1] = false }
    }

    func markAttendance(participant: String, attended: Bool) {
        attendance[participant] = attended
    }

    func updateDocumentation(text: String) {
        documentation = text
    }
}

// MARK: - DebriefSession

struct DebriefSession: Identifiable {
    let id = UUID()
    let date: Date
    let location: CLLocationCoordinate2D
    let talkingPoints: [String]
}

// MARK: - DebriefView

struct DebriefView: View {
    @StateObject private var viewModel = DebriefManager()

    var body: some View {
        NavigationView {
            List(viewModel.scheduledSessions) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    Text("Session on \(session.date, formatter: dateFormatter)")
                }
            }
            .navigationTitle("Debrief Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addSession) {
                        Label("Add Session", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func addSession() {
        // Placeholder for adding a new session
        let date = Date()
        let location = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let talkingPoints = ["Objective", "Actions", "Outcome"]
        viewModel.scheduleSession(date: date, location: location, talkingPoints: talkingPoints)
    }
}

// MARK: - SessionDetailView

struct SessionDetailView: View {
    let session: DebriefSession
    @StateObject private var viewModel = DebriefManager()

    var body: some View {
        VStack {
            Text("Session on \(session.date, formatter: dateFormatter)")
                .font(.headline)
            $name(location: session.location)
                .frame(height: 300)
            List(session.talkingPoints, id: \.self) { point in
                HStack {
                    Text(point)
                    Spacer()
                    Toggle(isOn: Binding(get: {
                        viewModel.attendance[point] ?? false
                    }, set: { value in
                        viewModel.markAttendance(participant: point, attended: value)
                    })) {
                        Text("Attended")
                    }
                }
            }
            TextEditor(text: Binding(get: {
                viewModel.documentation
            }, set: { value in
                viewModel.updateDocumentation(text: value)
            }))
                .frame(height: 200)
                .padding()
        }
        .navigationTitle("Session Details")
    }
}

// MARK: - MapView

struct DebriefMapSnippet: UIViewRepresentable {
    let location: CLLocationCoordinate2D

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        let annotation = MKPointAnnotation()
        annotation.coordinate = location
        mapView.addAnnotation(annotation)
        mapView.setRegion(MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000), animated: true)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // No update needed
    }
}

// MARK: - DateFormatter

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()