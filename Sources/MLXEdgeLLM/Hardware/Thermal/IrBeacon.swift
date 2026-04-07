import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - IrBeacon

class IrBeacon: ObservableObject {
    @Published var pattern: String = "default"
    @Published var batteryStatus: String = "full"
    @Published var lastUpdated: Date = Date()
    
    private let locationManager: CLLocationManager
    private let arSession: ARSession
    
    init(locationManager: CLLocationManager, arSession: ARSession) {
        self.locationManager = locationManager
        self.arSession = arSession
    }
    
    func updatePattern(_ newPattern: String) {
        pattern = newPattern
        lastUpdated = Date()
    }
    
    func updateBatteryStatus(_ newStatus: String) {
        batteryStatus = newStatus
        lastUpdated = Date()
    }
}

// MARK: - IrBeaconViewModel

class IrBeaconViewModel: ObservableObject {
    @Published var beacon: IrBeacon
    
    init(beacon: IrBeacon) {
        self.beacon = beacon
    }
    
    func changePattern(to newPattern: String) {
        beacon.updatePattern(newPattern)
    }
    
    func updateBattery(to newStatus: String) {
        beacon.updateBatteryStatus(newStatus)
    }
}

// MARK: - IrBeaconView

struct IrBeaconView: View {
    @StateObject private var viewModel: IrBeaconViewModel
    
    init(beacon: IrBeacon) {
        _viewModel = StateObject(wrappedValue: IrBeaconViewModel(beacon: beacon))
    }
    
    var body: some View {
        VStack {
            Text("Pattern: \(viewModel.beacon.pattern)")
            Text("Battery: \(viewModel.beacon.batteryStatus)")
            Text("Last Updated: \(viewModel.beacon.lastUpdated, style: .time)")
            
            Button("Change Pattern") {
                viewModel.changePattern(to: "alert")
            }
            
            Button("Update Battery") {
                viewModel.updateBattery(to: "low")
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct IrBeaconView_Previews: PreviewProvider {
    static var previews: some View {
        let locationManager = CLLocationManager()
        let arSession = ARSession()
        let beacon = IrBeacon(locationManager: locationManager, arSession: arSession)
        IrBeaconView(beacon: beacon)
    }
}