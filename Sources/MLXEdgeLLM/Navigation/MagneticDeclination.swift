import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - Magnetic Declination Service

class MagneticDeclinationService: ObservableObject {
    @Published var magneticDeclination: CLLocationDirection = 0.0
    @Published var manualOverride: CLLocationDirection = 0.0
    @Published var currentLocation: CLLocationCoordinate2D?
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func updateMagneticDeclination() {
        guard let location = currentLocation else { return }
        let geocoder = CLGeocoder()
        geocoder.geocodeLocation(CLLocation(latitude: location.latitude, longitude: location.longitude)) { placemarks, error in
            if let placemark = placemarks?.first, let magneticVariation = placemark.magneticVariation {
                DispatchQueue.main.async {
                    self.magneticDeclination = magneticVariation
                }
            }
        }
    }
    
    func setManualOverride(_ value: CLLocationDirection) {
        manualOverride = value
    }
}

extension MagneticDeclinationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
        updateMagneticDeclination()
    }
}

// MARK: - Magnetic Declination View Model

class MagneticDeclinationViewModel: ObservableObject {
    @ObservedObject private var magneticDeclinationService: MagneticDeclinationService
    
    init(magneticDeclinationService: MagneticDeclinationService) {
        self.magneticDeclinationService = magneticDeclinationService
    }
    
    var magneticDeclination: CLLocationDirection {
        magneticDeclinationService.manualOverride > 0 ? magneticDeclinationService.manualOverride : magneticDeclinationService.magneticDeclination
    }
    
    func setManualOverride(_ value: CLLocationDirection) {
        magneticDeclinationService.setManualOverride(value)
    }
}

// MARK: - Magnetic Declination View

struct MagneticDeclinationView: View {
    @StateObject private var viewModel = MagneticDeclinationViewModel(magneticDeclinationService: MagneticDeclinationService())
    
    var body: some View {
        VStack {
            Text("Magnetic Declination: \(viewModel.magneticDeclination, specifier: "%.2f")°")
                .font(.headline)
            
            Slider(value: Binding(get: { viewModel.magneticDeclination }, set: { viewModel.setManualOverride($0) }), in: 0...360)
                .padding()
            
            Text("Manual Override: \(viewModel.magneticDeclination, specifier: "%.2f")°")
                .font(.subheadline)
        }
        .padding()
        .navigationTitle("Magnetic Declination")
    }
}

// MARK: - Preview

struct MagneticDeclinationView_Previews: PreviewProvider {
    static var previews: some View {
        MagneticDeclinationView()
    }
}