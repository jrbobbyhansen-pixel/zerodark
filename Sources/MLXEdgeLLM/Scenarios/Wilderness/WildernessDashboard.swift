import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct SearchArea {
    let name: String
    let coordinates: CLLocationCoordinate2D
    let probabilityOfDetection: Double
}

struct TeamMember {
    let name: String
    let role: String
    let location: CLLocationCoordinate2D
}

struct Clue {
    let description: String
    let location: CLLocationCoordinate2D
}

// MARK: - View Models

class WildernessDashboardViewModel: ObservableObject {
    @Published var searchAreas: [SearchArea] = []
    @Published var teamMembers: [TeamMember] = []
    @Published var clues: [Clue] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        // Sample data
        searchAreas = [
            SearchArea(name: "Area 1", coordinates: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), probabilityOfDetection: 0.8),
            SearchArea(name: "Area 2", coordinates: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4195), probabilityOfDetection: 0.6)
        ]
        
        teamMembers = [
            TeamMember(name: "John Doe", role: "Leader", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
            TeamMember(name: "Jane Smith", role: "Navigator", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4195))
        ]
        
        clues = [
            Clue(description: "Broken compass", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
            Clue(description: "Ripped map", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4195))
        ]
    }
}

extension WildernessDashboardViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }
}

// MARK: - Views

struct WildernessDashboardView: View {
    @StateObject private var viewModel = WildernessDashboardViewModel()
    
    var body: some View {
        VStack {
            $name(searchAreas: viewModel.searchAreas, teamMembers: viewModel.teamMembers, clues: viewModel.clues, currentLocation: viewModel.currentLocation)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Search Areas")
                        .font(.headline)
                    
                    ForEach(viewModel.searchAreas) { area in
                        SearchAreaRow(area: area)
                    }
                    
                    Text("Team Members")
                        .font(.headline)
                    
                    ForEach(viewModel.teamMembers) { member in
                        TeamMemberRow(member: member)
                    }
                    
                    Text("Clues Found")
                        .font(.headline)
                    
                    ForEach(viewModel.clues) { clue in
                        ClueRow(clue: clue)
                    }
                }
                .padding()
            }
        }
    }
}

struct WildernessMapSnippet: UIViewRepresentable {
    let searchAreas: [SearchArea]
    let teamMembers: [TeamMember]
    let clues: [Clue]
    let currentLocation: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        
        if let currentLocation = currentLocation {
            let region = MKCoordinateRegion(center: currentLocation, latitudinalMeters: 1000, longitudinalMeters: 1000)
            mapView.setRegion(region, animated: true)
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        
        searchAreas.forEach { area in
            let annotation = MKPointAnnotation()
            annotation.coordinate = area.coordinates
            annotation.title = area.name
            uiView.addAnnotation(annotation)
        }
        
        teamMembers.forEach { member in
            let annotation = MKPointAnnotation()
            annotation.coordinate = member.location
            annotation.title = member.name
            annotation.subtitle = member.role
            uiView.addAnnotation(annotation)
        }
        
        clues.forEach { clue in
            let annotation = MKPointAnnotation()
            annotation.coordinate = clue.location
            annotation.title = "Clue"
            annotation.subtitle = clue.description
            uiView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
    }
}

struct SearchAreaRow: View {
    let area: SearchArea
    
    var body: some View {
        HStack {
            Text(area.name)
            Spacer()
            Text("Detection: \(String(format: "%.0f%%", area.probabilityOfDetection * 100))")
        }
    }
}

struct TeamMemberRow: View {
    let member: TeamMember
    
    var body: some View {
        HStack {
            Text(member.name)
            Spacer()
            Text(member.role)
        }
    }
}

struct ClueRow: View {
    let clue: Clue
    
    var body: some View {
        HStack {
            Text("Clue")
            Spacer()
            Text(clue.description)
        }
    }
}

// MARK: - Preview

struct WildernessDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        WildernessDashboardView()
    }
}