import Foundation
import SwiftUI
import CoreLocation

// MARK: - Drone Telemetry Model

struct DroneTelemetry {
    var altitude: Double
    var speed: Double
    var heading: Double
    var battery: Double
    var gpsCoordinate: CLLocationCoordinate2D
    var signalStrength: Double
}

// MARK: - Drone Telemetry Service

class DroneTelemetryService: ObservableObject {
    @Published var telemetry: DroneTelemetry
    @Published var warnings: [String] = []
    
    private var flightLog: [DroneTelemetry] = []
    
    init() {
        telemetry = DroneTelemetry(altitude: 0.0, speed: 0.0, heading: 0.0, battery: 100.0, gpsCoordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0), signalStrength: 100.0)
    }
    
    func updateTelemetry(_ newTelemetry: DroneTelemetry) {
        telemetry = newTelemetry
        flightLog.append(newTelemetry)
        checkForWarnings()
    }
    
    private func checkForWarnings() {
        warnings = []
        if telemetry.battery < 20 {
            warnings.append("Low battery: \(telemetry.battery)%")
        }
        if telemetry.signalStrength < 30 {
            warnings.append("Weak signal: \(telemetry.signalStrength)%")
        }
    }
    
    func recordFlightLog() {
        // Implement flight log recording logic here
        // For example, save the flightLog array to a file or database
    }
}

// MARK: - Drone Telemetry View Model

class DroneTelemetryViewModel: ObservableObject {
    @Published var telemetry: DroneTelemetry
    @Published var warnings: [String] = []
    
    private let service: DroneTelemetryService
    
    init(service: DroneTelemetryService) {
        self.service = service
        self.telemetry = service.telemetry
        self.warnings = service.warnings
        service.$telemetry.assign(to: &$telemetry)
        service.$warnings.assign(to: &$warnings)
    }
    
    func updateTelemetry(_ newTelemetry: DroneTelemetry) {
        service.updateTelemetry(newTelemetry)
    }
    
    func recordFlightLog() {
        service.recordFlightLog()
    }
}

// MARK: - Drone Telemetry View

struct DroneTelemetryView: View {
    @StateObject private var viewModel: DroneTelemetryViewModel
    
    init(service: DroneTelemetryService) {
        _viewModel = StateObject(wrappedValue: DroneTelemetryViewModel(service: service))
    }
    
    var body: some View {
        VStack {
            Text("Drone Telemetry")
                .font(.largeTitle)
                .padding()
            
            HStack {
                VStack {
                    Text("Altitude: \(String(format: "%.2f", viewModel.telemetry.altitude)) m")
                    Text("Speed: \(String(format: "%.2f", viewModel.telemetry.speed)) km/h")
                    Text("Heading: \(String(format: "%.2f", viewModel.telemetry.heading))°")
                }
                VStack {
                    Text("Battery: \(String(format: "%.0f", viewModel.telemetry.battery))%")
                    Text("Signal: \(String(format: "%.0f", viewModel.telemetry.signalStrength))%")
                }
            }
            .padding()
            
            if !viewModel.warnings.isEmpty {
                VStack {
                    Text("Warnings:")
                        .font(.headline)
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Text(warning)
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
            
            Button(action: {
                viewModel.recordFlightLog()
            }) {
                Text("Record Flight Log")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
    }
}

// MARK: - Preview

struct DroneTelemetryView_Previews: PreviewProvider {
    static var previews: some View {
        let service = DroneTelemetryService()
        DroneTelemetryView(service: service)
    }
}