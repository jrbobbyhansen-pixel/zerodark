import SwiftUI
import MapKit
import CoreLocation

// MARK: - Models

struct WaterLevel {
    let location: CLLocationCoordinate2D
    let level: Double
}

struct RescueRequest {
    let id: UUID
    let location: CLLocationCoordinate2D
    let status: String
}

struct Resource {
    let id: UUID
    let type: String
    let location: CLLocationCoordinate2D
    let quantity: Int
}

struct Evacuation {
    let id: UUID
    let location: CLLocationCoordinate2D
    let status: String
}

// MARK: - View Models

class FloodDashboardViewModel: ObservableObject {
    @Published var waterLevels: [WaterLevel] = []
    @Published var rescueRequests: [RescueRequest] = []
    @Published var resources: [Resource] = []
    @Published var evacuations: [Evacuation] = []
    @Published var selectedLocation: CLLocationCoordinate2D?
    
    func addWaterLevel(_ level: WaterLevel) {
        waterLevels.append(level)
    }
    
    func addRescueRequest(_ request: RescueRequest) {
        rescueRequests.append(request)
    }
    
    func addResource(_ resource: Resource) {
        resources.append(resource)
    }
    
    func addEvacuation(_ evacuation: Evacuation) {
        evacuations.append(evacuation)
    }
}

// MARK: - Views

struct FloodDashboardView: View {
    @StateObject private var viewModel = FloodDashboardViewModel()
    @State private var showingAddWaterLevel = false
    @State private var showingAddRescueRequest = false
    @State private var showingAddResource = false
    @State private var showingAddEvacuation = false
    
    var body: some View {
        NavigationView {
            VStack {
                $name(viewModel: viewModel)
                    .edgesIgnoringSafeArea(.all)
                
                HStack {
                    Button(action: { showingAddWaterLevel = true }) {
                        Label("Add Water Level", systemImage: "drop.fill")
                    }
                    .sheet(isPresented: $showingAddWaterLevel) {
                        AddWaterLevelView(viewModel: viewModel)
                    }
                    
                    Button(action: { showingAddRescueRequest = true }) {
                        Label("Add Rescue Request", systemImage: "person.fill")
                    }
                    .sheet(isPresented: $showingAddRescueRequest) {
                        AddRescueRequestView(viewModel: viewModel)
                    }
                    
                    Button(action: { showingAddResource = true }) {
                        Label("Add Resource", systemImage: "box.fill")
                    }
                    .sheet(isPresented: $showingAddResource) {
                        AddResourceView(viewModel: viewModel)
                    }
                    
                    Button(action: { showingAddEvacuation = true }) {
                        Label("Add Evacuation", systemImage: "car.fill")
                    }
                    .sheet(isPresented: $showingAddEvacuation) {
                        AddEvacuationView(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("Flood Dashboard")
        }
    }
}

struct FloodMapSnippet: UIViewRepresentable {
    @ObservedObject var viewModel: FloodDashboardViewModel
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        
        viewModel.waterLevels.forEach { level in
            let annotation = MKPointAnnotation()
            annotation.coordinate = level.location
            annotation.title = "Water Level: \(level.level)m"
            uiView.addAnnotation(annotation)
        }
        
        viewModel.rescueRequests.forEach { request in
            let annotation = MKPointAnnotation()
            annotation.coordinate = request.location
            annotation.title = "Rescue Request: \(request.status)"
            uiView.addAnnotation(annotation)
        }
        
        viewModel.resources.forEach { resource in
            let annotation = MKPointAnnotation()
            annotation.coordinate = resource.location
            annotation.title = "\(resource.type): \(resource.quantity)"
            uiView.addAnnotation(annotation)
        }
        
        viewModel.evacuations.forEach { evacuation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = evacuation.location
            annotation.title = "Evacuation: \(evacuation.status)"
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
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation {
                parent.viewModel.selectedLocation = annotation.coordinate
            }
        }
    }
}

struct AddWaterLevelView: View {
    @ObservedObject var viewModel: FloodDashboardViewModel
    @State private var location = CLLocationCoordinate2D()
    @State private var level = 0.0
    
    var body: some View {
        Form {
            Section(header: Text("Location")) {
                MapCoordinatePicker(location: $location)
            }
            
            Section(header: Text("Water Level")) {
                TextField("Level (m)", value: $level, formatter: NumberFormatter())
            }
            
            Button(action: {
                viewModel.addWaterLevel(WaterLevel(location: location, level: level))
                dismiss()
            }) {
                Text("Add Water Level")
            }
        }
        .navigationTitle("Add Water Level")
    }
}

struct AddRescueRequestView: View {
    @ObservedObject var viewModel: FloodDashboardViewModel
    @State private var location = CLLocationCoordinate2D()
    @State private var status = ""
    
    var body: some View {
        Form {
            Section(header: Text("Location")) {
                MapCoordinatePicker(location: $location)
            }
            
            Section(header: Text("Status")) {
                TextField("Status", text: $status)
            }
            
            Button(action: {
                viewModel.addRescueRequest(RescueRequest(id: UUID(), location: location, status: status))
                dismiss()
            }) {
                Text("Add Rescue Request")
            }
        }
        .navigationTitle("Add Rescue Request")
    }
}

struct AddResourceView: View {
    @ObservedObject var viewModel: FloodDashboardViewModel
    @State private var location = CLLocationCoordinate2D()
    @State private var type = ""
    @State private var quantity = 0
    
    var body: some View {
        Form {
            Section(header: Text("Location")) {
                MapCoordinatePicker(location: $location)
            }
            
            Section(header: Text("Resource Type")) {
                TextField("Type", text: $type)
            }
            
            Section(header: Text("Quantity")) {
                TextField("Quantity", value: $quantity, formatter: NumberFormatter())
            }
            
            Button(action: {
                viewModel.addResource(Resource(id: UUID(), type: type, location: location, quantity: quantity))
                dismiss()
            }) {
                Text("Add Resource")
            }
        }
        .navigationTitle("Add Resource")
    }
}

struct AddEvacuationView: View {
    @ObservedObject var viewModel: FloodDashboardViewModel
    @State private var location = CLLocationCoordinate2D()
    @State private var status = ""
    
    var body: some View {
        Form {
            Section(header: Text("Location")) {
                MapCoordinatePicker(location: $location)
            }
            
            Section(header: Text("Status")) {
                TextField("Status", text: $status)
            }
            
            Button(action: {
                viewModel.addEvacuation(Evacuation(id: UUID(), location: location, status: status))
                dismiss()
            }) {
                Text("Add Evacuation")
            }
        }
        .navigationTitle("Add Evacuation")
    }
}

struct MapCoordinatePicker: UIViewRepresentable {
    @Binding var location: CLLocationCoordinate2D
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        let region = MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000)
        uiView.setRegion(region, animated: true)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapCoordinatePicker
        
        init(_ parent: MapCoordinatePicker) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation {
                parent.location = annotation.coordinate
            }
        }
    }
}

// MARK: - Previews

struct FloodDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        FloodDashboardView()
    }
}