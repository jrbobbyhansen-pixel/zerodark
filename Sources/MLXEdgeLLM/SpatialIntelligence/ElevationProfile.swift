import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - ElevationProfile

struct ElevationProfile: View {
    @StateObject private var viewModel = ElevationProfileViewModel()
    
    var body: some View {
        VStack {
            Map(coordinateRegion: $viewModel.region, annotationItems: viewModel.annotations) { annotation in
                MapPin(coordinate: annotation.coordinate, tint: annotation.color)
            }
            .edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Cumulative Gain: \(viewModel.cumulativeGain)m")
                Text("Cumulative Loss: \(viewModel.cumulativeLoss)m")
                Text("High Points: \(viewModel.highPoints.count)")
                Text("Saddles: \(viewModel.saddles.count)")
            }
            .padding()
            .background(Color.white.opacity(0.8))
            .cornerRadius(10)
        }
        .onAppear {
            viewModel.fetchElevationProfile()
        }
    }
}

// MARK: - ElevationProfileViewModel

class ElevationProfileViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), latitudinalMeters: 1000, longitudinalMeters: 1000)
    @Published var annotations: [ElevationAnnotation] = []
    @Published var cumulativeGain: Double = 0
    @Published var cumulativeLoss: Double = 0
    @Published var highPoints: [CLLocationCoordinate2D] = []
    @Published var saddles: [CLLocationCoordinate2D] = []
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    func fetchElevationProfile() {
        // Placeholder for fetching elevation data
        // This should be replaced with actual API calls or Core Location services
        let coordinates = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195),
            CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196)
        ]
        
        for coordinate in coordinates {
            let annotation = ElevationAnnotation(coordinate: coordinate, color: .blue)
            annotations.append(annotation)
        }
        
        // Calculate cumulative gain and loss
        for i in 1..<coordinates.count {
            let previous = coordinates[i - 1]
            let current = coordinates[i]
            let elevationDifference = current.altitude - previous.altitude
            
            if elevationDifference > 0 {
                cumulativeGain += elevationDifference
            } else {
                cumulativeLoss -= elevationDifference
            }
        }
        
        // Identify high points and saddles
        for i in 1..<coordinates.count - 1 {
            let previous = coordinates[i - 1]
            let current = coordinates[i]
            let next = coordinates[i + 1]
            
            if current.altitude > previous.altitude && current.altitude > next.altitude {
                highPoints.append(current)
            } else if current.altitude < previous.altitude && current.altitude < next.altitude {
                saddles.append(current)
            }
        }
    }
}

// MARK: - ElevationAnnotation

struct ElevationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let color: Color
}

// MARK: - CLLocationManagerDelegate

extension ElevationProfileViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        region.center = location.coordinate
    }
}