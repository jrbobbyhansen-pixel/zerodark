import SwiftUI
import CoreLocation

// MARK: - WildfireDashboard

struct WildfireDashboard: View {
    @StateObject private var viewModel = WildfireViewModel()
    
    var body: some View {
        VStack {
            $name(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading) {
                Text("Fire Perimeter")
                    .font(.headline)
                
                List(viewModel.firePerimeter, id: \.self) { coordinate in
                    Text("\(coordinate.latitude), \(coordinate.longitude)")
                }
                
                Button(action: {
                    viewModel.addFirePerimeterCoordinate()
                }) {
                    Text("Add Coordinate")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text("Resources Deployed")
                    .font(.headline)
                
                List(viewModel.resourcesDeployed, id: \.self) { resource in
                    Text(resource)
                }
                
                Button(action: {
                    viewModel.addResourceDeployed()
                }) {
                    Text("Add Resource")
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text("Evacuation Zones")
                    .font(.headline)
                
                List(viewModel.evacuationZones, id: \.self) { zone in
                    Text(zone)
                }
                
                Button(action: {
                    viewModel.addEvacuationZone()
                }) {
                    Text("Add Zone")
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
            
            VStack(alignment: .leading) {
                Text("Safety Zones")
                    .font(.headline)
                
                List(viewModel.safetyZones, id: \.self) { zone in
                    Text(zone)
                }
                
                Button(action: {
                    viewModel.addSafetyZone()
                }) {
                    Text("Add Zone")
                }
                .padding()
                .background(Color.yellow)
                .foregroundColor(.black)
                .cornerRadius(8)
            }
            .padding()
        }
    }
}

// MARK: - WildfireViewModel

class WildfireViewModel: ObservableObject {
    @Published var firePerimeter: [CLLocationCoordinate2D] = []
    @Published var resourcesDeployed: [String] = []
    @Published var evacuationZones: [String] = []
    @Published var safetyZones: [String] = []
    
    func addFirePerimeterCoordinate() {
        // Add a new coordinate to the fire perimeter
        let newCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // Example coordinate
        firePerimeter.append(newCoordinate)
    }
    
    func addResourceDeployed() {
        // Add a new resource to the deployed resources
        resourcesDeployed.append("Fire Truck \(resourcesDeployed.count + 1)")
    }
    
    func addEvacuationZone() {
        // Add a new evacuation zone
        evacuationZones.append("Zone \(evacuationZones.count + 1)")
    }
    
    func addSafetyZone() {
        // Add a new safety zone
        safetyZones.append("Zone \(safetyZones.count + 1)")
    }
}

// MARK: - MapView

struct WildfireMapSnippet: UIViewRepresentable {
    @ObservedObject var viewModel: WildfireViewModel
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update the map view with the latest data
        uiView.removeAnnotations(uiView.annotations)
        
        for coordinate in viewModel.firePerimeter {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = "Fire Perimeter"
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