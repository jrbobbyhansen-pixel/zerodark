import SwiftUI
import CoreLocation

// MARK: - BuddySystem Model

struct BuddySystem: Identifiable {
    let id = UUID()
    let name: String
    let location: CLLocationCoordinate2D
    var isAccountable: Bool
    var isSupporting: Bool
}

// MARK: - BuddySystemViewModel

class BuddySystemViewModel: ObservableObject {
    @Published var buddies: [BuddySystem] = [
        BuddySystem(name: "Alpha", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), isAccountable: true, isSupporting: false),
        BuddySystem(name: "Bravo", location: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), isAccountable: false, isSupporting: true),
        BuddySystem(name: "Charlie", location: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196), isAccountable: false, isSupporting: false)
    ]
    
    @Published var currentLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    
    func updateAccountability(for buddy: BuddySystem) {
        if let index = buddies.firstIndex(where: { $0.id == buddy.id }) {
            buddies[index].isAccountable.toggle()
        }
    }
    
    func updateSupport(for buddy: BuddySystem) {
        if let index = buddies.firstIndex(where: { $0.id == buddy.id }) {
            buddies[index].isSupporting.toggle()
        }
    }
}

// MARK: - BuddySystemView

struct BuddySystemView: View {
    @StateObject private var viewModel = BuddySystemViewModel()
    
    var body: some View {
        VStack {
            $name(currentLocation: $viewModel.currentLocation, buddies: viewModel.buddies)
                .edgesIgnoringSafeArea(.all)
            
            List(viewModel.buddies) { buddy in
                HStack {
                    Text(buddy.name)
                        .font(.headline)
                    
                    Spacer()
                    
                    Toggle("Accountable", isOn: Binding(
                        get: { buddy.isAccountable },
                        set: { newValue in
                            viewModel.updateAccountability(for: buddy)
                        }
                    ))
                    
                    Toggle("Supporting", isOn: Binding(
                        get: { buddy.isSupporting },
                        set: { newValue in
                            viewModel.updateSupport(for: buddy)
                        }
                    ))
                }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("Buddy System Trainer")
    }
}

// MARK: - MapView

struct TrainingBuddyMapSnippet: UIViewRepresentable {
    @Binding var currentLocation: CLLocationCoordinate2D
    let buddies: [BuddySystem]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MK$name()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(MKCoordinateRegion(center: currentLocation, latitudinalMeters: 1000, longitudinalMeters: 1000), animated: true)
        
        uiView.removeAnnotations(uiView.annotations)
        for buddy in buddies {
            let annotation = MKPointAnnotation()
            annotation.coordinate = buddy.location
            annotation.title = buddy.name
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

// MARK: - Preview

struct BuddySystemView_Previews: PreviewProvider {
    static var previews: some View {
        BuddySystemView()
    }
}