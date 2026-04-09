import SwiftUI
import CoreLocation

// MARK: - UsarDashboard

struct UsarDashboard: View {
    @StateObject private var viewModel = UsarDashboardViewModel()
    
    var body: some View {
        VStack {
            $name(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading) {
                Text("Building Assessments")
                    .font(.headline)
                
                List(viewModel.buildingAssessments) { assessment in
                    Text(assessment.description)
                }
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text("Search Status")
                    .font(.headline)
                
                List(viewModel.searchStatus) { status in
                    Text(status.description)
                }
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text("Victim Tracking")
                    .font(.headline)
                
                List(viewModel.victimLocations) { location in
                    Text("Victim at \(location.coordinate.latitude), \(location.coordinate.longitude)")
                }
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text("Hazmat Zones")
                    .font(.headline)
                
                List(viewModel.hazmatZones) { zone in
                    Text("Hazmat Zone at \(zone.coordinate.latitude), \(zone.coordinate.longitude)")
                }
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text("Resources")
                    .font(.headline)
                
                List(viewModel.resources) { resource in
                    Text(resource.description)
                }
            }
            .padding()
        }
        .environmentObject(viewModel)
    }
}

// MARK: - UsarDashboardViewModel

class UsarDashboardViewModel: ObservableObject {
    @Published var buildingAssessments: [BuildingAssessment] = []
    @Published var searchStatus: [SearchStatus] = []
    @Published var victimLocations: [CLLocationCoordinate2D] = []
    @Published var hazmatZones: [CLLocationCoordinate2D] = []
    @Published var resources: [Resource] = []
    
    init() {
        // Simulate data fetching
        fetchBuildingAssessments()
        fetchSearchStatus()
        fetchVictimLocations()
        fetchHazmatZones()
        fetchResources()
    }
    
    private func fetchBuildingAssessments() {
        // Simulate network call
        buildingAssessments = [
            BuildingAssessment(description: "Building A: Safe"),
            BuildingAssessment(description: "Building B: Damaged")
        ]
    }
    
    private func fetchSearchStatus() {
        // Simulate network call
        searchStatus = [
            SearchStatus(description: "Search Team 1: In Progress"),
            SearchStatus(description: "Search Team 2: Completed")
        ]
    }
    
    private func fetchVictimLocations() {
        // Simulate network call
        victimLocations = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195)
        ]
    }
    
    private func fetchHazmatZones() {
        // Simulate network call
        hazmatZones = [
            CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196),
            CLLocationCoordinate2D(latitude: 37.7752, longitude: -122.4197)
        ]
    }
    
    private func fetchResources() {
        // Simulate network call
        resources = [
            Resource(description: "Rescue Team 1"),
            Resource(description: "Medical Kit 2")
        ]
    }
}

// MARK: - Models

struct BuildingAssessment {
    let description: String
}

struct SearchStatus {
    let description: String
}

struct Resource {
    let description: String
}

// MARK: - MapView

struct UsarMapSnippet: UIViewRepresentable {
    @ObservedObject var viewModel: UsarDashboardViewModel
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        
        viewModel.victimLocations.forEach { location in
            let annotation = MKPointAnnotation()
            annotation.coordinate = location
            annotation.title = "Victim"
            uiView.addAnnotation(annotation)
        }
        
        viewModel.hazmatZones.forEach { location in
            let annotation = MKPointAnnotation()
            annotation.coordinate = location
            annotation.title = "Hazmat Zone"
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