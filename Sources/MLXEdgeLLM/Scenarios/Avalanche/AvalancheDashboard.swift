import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct BurialSite: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    var status: String
}

struct Searcher: Identifiable {
    let id = UUID()
    let name: String
    let location: CLLocationCoordinate2D
}

struct ProbeLine: Identifiable {
    let id = UUID()
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
}

struct Dog: Identifiable {
    let id = UUID()
    let name: String
    let location: CLLocationCoordinate2D
}

// MARK: - ViewModel

class AvalancheDashboardViewModel: ObservableObject {
    @Published var burialSites: [BurialSite] = []
    @Published var searchers: [Searcher] = []
    @Published var probeLines: [ProbeLine] = []
    @Published var dogs: [Dog] = []
    
    func addBurialSite(location: CLLocationCoordinate2D, status: String) {
        burialSites.append(BurialSite(location: location, status: status))
    }
    
    func addSearcher(name: String, location: CLLocationCoordinate2D) {
        searchers.append(Searcher(name: name, location: location))
    }
    
    func addProbeLine(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) {
        probeLines.append(ProbeLine(start: start, end: end))
    }
    
    func addDog(name: String, location: CLLocationCoordinate2D) {
        dogs.append(Dog(name: name, location: location))
    }
}

// MARK: - Views

struct AvalancheDashboardView: View {
    @StateObject private var viewModel = AvalancheDashboardViewModel()
    
    var body: some View {
        VStack {
            $name(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
            
            ControlPanel(viewModel: viewModel)
        }
    }
}

struct AvalancheMapSnippet: UIViewRepresentable {
    @ObservedObject var viewModel: AvalancheDashboardViewModel
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        
        viewModel.burialSites.forEach { site in
            let annotation = MKPointAnnotation()
            annotation.coordinate = site.location
            annotation.title = "Burial Site"
            annotation.subtitle = site.status
            uiView.addAnnotation(annotation)
        }
        
        viewModel.searchers.forEach { searcher in
            let annotation = MKPointAnnotation()
            annotation.coordinate = searcher.location
            annotation.title = "Searcher: \(searcher.name)"
            uiView.addAnnotation(annotation)
        }
        
        viewModel.dogs.forEach { dog in
            let annotation = MKPointAnnotation()
            annotation.coordinate = dog.location
            annotation.title = "Dog: \(dog.name)"
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

struct ControlPanel: View {
    @ObservedObject var viewModel: AvalancheDashboardViewModel
    
    var body: some View {
        VStack {
            Text("Avalanche SAR Dashboard")
                .font(.largeTitle)
                .padding()
            
            Button(action: {
                // Add new burial site
                viewModel.addBurialSite(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), status: "Pending")
            }) {
                Text("Add Burial Site")
            }
            .padding()
            
            Button(action: {
                // Add new searcher
                viewModel.addSearcher(name: "John Doe", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            }) {
                Text("Add Searcher")
            }
            .padding()
            
            Button(action: {
                // Add new dog
                viewModel.addDog(name: "Buddy", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            }) {
                Text("Add Dog")
            }
            .padding()
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }
}

// MARK: - Preview

struct AvalancheDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        AvalancheDashboardView()
    }
}