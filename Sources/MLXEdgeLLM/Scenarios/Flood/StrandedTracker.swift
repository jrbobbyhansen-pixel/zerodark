import Foundation
import SwiftUI
import CoreLocation

// MARK: - StrandedTracker

class StrandedTracker: ObservableObject {
    @Published var strandedPersons: [StrandedPerson] = []
    @Published var rescueTeams: [RescueTeam] = []
    @Published var activeScenario: Scenario?
    
    func reportStrandedPerson(location: CLLocationCoordinate2D, priority: RiskLevel) {
        let strandedPerson = StrandedPerson(location: location, priority: priority)
        strandedPersons.append(strandedPerson)
        assignToRescueTeam(strandedPerson)
    }
    
    func updateStatus(of strandedPerson: StrandedPerson, to status: Status) {
        if let index = strandedPersons.firstIndex(of: strandedPerson) {
            strandedPersons[index].status = status
        }
    }
    
    func assignToRescueTeam(_ strandedPerson: StrandedPerson) {
        guard let team = rescueTeams.first(where: { $0.isAvailable }) else { return }
        team.assign(strandedPerson)
    }
    
    func completeScenario() {
        activeScenario?.isCompleted = true
    }
}

// MARK: - StrandedPerson

struct StrandedPerson: Identifiable {
    let id = UUID()
    var location: CLLocationCoordinate2D
    var priority: RiskLevel
    var status: Status = .reported
}

// MARK: - RescueTeam

class RescueTeam: ObservableObject, Identifiable {
    let id = UUID()
    @Published var assignedStrandedPersons: [StrandedPerson] = []
    
    var isAvailable: Bool {
        assignedStrandedPersons.isEmpty
    }
    
    func assign(_ strandedPerson: StrandedPerson) {
        assignedStrandedPersons.append(strandedPerson)
    }
}

// MARK: - Scenario

class Scenario: ObservableObject {
    @Published var isCompleted: Bool = false
}

// MARK: - RiskLevel

enum RiskLevel: Int, Comparable {
    case low
    case medium
    case high
    
    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Status

enum Status {
    case reported
    case inProgress
    case completed
}

// MARK: - StrandedTrackerView

struct StrandedTrackerView: View {
    @StateObject private var viewModel = StrandedTracker()
    
    var body: some View {
        VStack {
            $name(strandedPersons: $viewModel.strandedPersons)
                .edgesIgnoringSafeArea(.all)
            
            Button("Report Stranded Person") {
                // Implement reporting logic
            }
            
            List(viewModel.strandedPersons) { strandedPerson in
                StrandedPersonRow(strandedPerson: strandedPerson)
            }
        }
        .environmentObject(viewModel)
    }
}

// MARK: - MapView

struct StrandedMapSnippet: UIViewRepresentable {
    @Binding var strandedPersons: [StrandedPerson]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.addAnnotations(strandedPersons.map { StrandedPersonAnnotation(strandedPerson: $0) })
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? StrandedPersonAnnotation else { return nil }
            let view = MKPinAnnotationView(annotation: annotation, reuseIdentifier: "StrandedPerson")
            view.canShowCallout = true
            view.calloutOffset = CGPoint(x: 0, y: 5)
            return view
        }
    }
}

// MARK: - StrandedPersonAnnotation

class StrandedPersonAnnotation: NSObject, MKAnnotation {
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?
    
    init(strandedPerson: StrandedPerson) {
        self.coordinate = strandedPerson.location
        self.title = "Stranded Person"
        self.subtitle = "Priority: \(strandedPerson.priority.rawValue)"
    }
}

// MARK: - StrandedPersonRow

struct StrandedPersonRow: View {
    let strandedPerson: StrandedPerson
    
    var body: some View {
        HStack {
            Text("Stranded Person")
            Spacer()
            Text("Priority: \(strandedPerson.priority.rawValue)")
            Text("Status: \(strandedPerson.status.rawValue)")
        }
    }
}