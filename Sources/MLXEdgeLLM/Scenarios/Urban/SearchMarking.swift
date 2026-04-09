import SwiftUI
import CoreLocation
import ARKit

// MARK: - SearchMarkingViewModel

class SearchMarkingViewModel: ObservableObject {
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var searchStatus: String = ""
    @Published var hazards: [String] = []
    @Published var victims: [String] = []
    @Published var photos: [UIImage] = []
    
    private let locationManager = CLLocationManager()
    private let arSession = ARSession()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func addPhoto(_ image: UIImage) {
        photos.append(image)
    }
    
    func updateSearchStatus(_ status: String) {
        searchStatus = status
    }
    
    func addHazard(_ hazard: String) {
        hazards.append(hazard)
    }
    
    func addVictim(_ victim: String) {
        victims.append(victim)
    }
}

// MARK: - CLLocationManagerDelegate

extension SearchMarkingViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }
}

// MARK: - SearchMarkingView

struct SearchMarkingView: View {
    @StateObject private var viewModel = SearchMarkingViewModel()
    
    var body: some View {
        VStack {
            $name(location: $viewModel.currentLocation)
                .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading) {
                Text("Search Status: \(viewModel.searchStatus)")
                Text("Hazards: \(viewModel.hazards.joined(separator: ", "))")
                Text("Victims: \(viewModel.victims.joined(separator: ", "))")
            }
            .padding()
            
            Button(action: {
                // Logic to take a photo
                let image = UIImage(named: "placeholder") ?? UIImage()
                viewModel.addPhoto(image)
            }) {
                Text("Take Photo")
            }
            .padding()
            
            Button(action: {
                viewModel.updateSearchStatus("Completed")
            }) {
                Text("Mark as Completed")
            }
            .padding()
            
            Button(action: {
                viewModel.addHazard("Fire")
            }) {
                Text("Add Hazard: Fire")
            }
            .padding()
            
            Button(action: {
                viewModel.addVictim("Victim 1")
            }) {
                Text("Add Victim: Victim 1")
            }
            .padding()
        }
    }
}

// MARK: - MapView

struct SearchMarkMapSnippet: UIViewRepresentable {
    @Binding var location: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let location = location {
            let region = MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000)
            uiView.setRegion(region, animated: true)
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

// MARK: - Preview

struct SearchMarkingView_Previews: PreviewProvider {
    static var previews: some View {
        SearchMarkingView()
    }
}