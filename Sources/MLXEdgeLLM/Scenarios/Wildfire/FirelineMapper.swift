import SwiftUI
import MapKit
import CoreLocation
import ARKit
import AVFoundation

// MARK: - FirelineMapper

struct FirelineMapper: View {
    @StateObject private var viewModel = FirelineMapperViewModel()
    
    var body: some View {
        VStack {
            Map(coordinateRegion: $viewModel.region, annotationItems: viewModel.annotations) { annotation in
                MapPin(coordinate: annotation.coordinate, tint: annotation.color)
            }
            .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Completed: \(viewModel.completedPercentage)%")
                    .font(.headline)
                
                Text("Obstacles: \(viewModel.obstacles.count)")
                    .font(.subheadline)
                
                Text("Safety Concerns: \(viewModel.safetyConcerns.count)")
                    .font(.subheadline)
            }
            .padding()
            .background(Color.white.opacity(0.8))
            .cornerRadius(10)
            .shadow(radius: 5)
            
            Button(action: {
                viewModel.addObstacle()
            }) {
                Text("Log Obstacle")
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .onAppear {
            viewModel.startTracking()
        }
    }
}

// MARK: - FirelineMapperViewModel

class FirelineMapperViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
    @Published var annotations: [FirelineAnnotation] = []
    @Published var completedPercentage: Int = 0
    @Published var obstacles: [String] = []
    @Published var safetyConcerns: [String] = []
    
    private var locationManager = CLLocationManager()
    private var arSession = ARSession()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func startTracking() {
        arSession.run(ARWorldTrackingConfiguration())
    }
    
    func addObstacle() {
        obstacles.append("Obstacle at \(region.center.latitude), \(region.center.longitude)")
    }
}

// MARK: - FirelineAnnotation

struct FirelineAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let color: Color
}

// MARK: - CLLocationManagerDelegate

extension FirelineMapperViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        region.center = location.coordinate
    }
}