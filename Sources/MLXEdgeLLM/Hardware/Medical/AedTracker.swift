import Foundation
import SwiftUI
import CoreLocation

// MARK: - AED Data Model

struct AEDLocation: Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let batteryLevel: Double
    let padExpiration: Date
    let lastSelfTestResult: String
}

// MARK: - AED Tracker Service

class AEDTrackerService: ObservableObject {
    @Published var aedLocations: [AEDLocation] = []
    @Published var nearestAED: AEDLocation?
    
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func updateAEDLocations(_ locations: [AEDLocation]) {
        aedLocations = locations
        updateNearestAED()
    }
    
    private func updateNearestAED() {
        guard let currentLocation = currentLocation else { return }
        nearestAED = aedLocations.min { first, second in
            currentLocation.distance(from: CLLocation(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)) <
            currentLocation.distance(from: CLLocation(latitude: second.coordinate.latitude, longitude: second.coordinate.longitude))
        }
    }
}

extension AEDTrackerService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        updateNearestAED()
    }
}

// MARK: - AED Tracker View Model

class AEDTrackerViewModel: ObservableObject {
    @Published var aedLocations: [AEDLocation] = []
    @Published var nearestAED: AEDLocation?
    
    private let aedTrackerService: AEDTrackerService
    
    init(aedTrackerService: AEDTrackerService) {
        self.aedTrackerService = aedTrackerService
        self.aedLocations = aedTrackerService.aedLocations
        self.nearestAED = aedTrackerService.nearestAED
        aedTrackerService.$aedLocations.sink { [weak self] locations in
            self?.aedLocations = locations
        }.store(in: &cancellables)
        aedTrackerService.$nearestAED.sink { [weak self] nearestAED in
            self?.nearestAED = nearestAED
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - AED Tracker View

struct AEDTrackerView: View {
    @StateObject private var viewModel = AEDTrackerViewModel(aedTrackerService: AEDTrackerService())
    
    var body: some View {
        VStack {
            if let nearestAED = viewModel.nearestAED {
                VStack {
                    Text("Nearest AED: \(nearestAED.name)")
                        .font(.headline)
                    Text("Distance: \(String(format: "%.2f", nearestAED.coordinate.distance(from: viewModel.aedTrackerService.currentLocation ?? CLLocation(latitude: 0, longitude: 0)) / 1000)) km")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(10)
            } else {
                Text("No AEDs found")
                    .font(.headline)
                    .padding()
            }
            
            List(viewModel.aedLocations) { aed in
                VStack(alignment: .leading) {
                    Text(aed.name)
                        .font(.headline)
                    Text("Battery: \(String(format: "%.0f%%", aed.batteryLevel * 100))")
                        .font(.subheadline)
                    Text("Pad Expiration: \(aed.padExpiration, style: .date)")
                        .font(.subheadline)
                    Text("Last Self-Test: \(aed.lastSelfTestResult)")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .navigationTitle("AED Tracker")
    }
}

// MARK: - Preview

struct AEDTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        AEDTrackerView()
    }
}