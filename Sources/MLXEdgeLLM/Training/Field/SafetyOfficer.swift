import SwiftUI
import Foundation
import CoreLocation
import ARKit
import AVFoundation

// MARK: - SafetyOfficerViewModel

class SafetyOfficerViewModel: ObservableObject {
    @Published var location: CLLocationCoordinate2D?
    @Published var riskAssessment: String = ""
    @Published var incidentReport: String = ""
    @Published var emergencyProcedures: String = ""
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func performRiskAssessment() {
        // Placeholder for actual risk assessment logic
        riskAssessment = "Risk assessment completed."
    }
    
    func reportIncident(description: String) {
        incidentReport = "Incident reported: \(description)"
    }
    
    func updateEmergencyProcedures(procedures: String) {
        emergencyProcedures = procedures
    }
}

extension SafetyOfficerViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location.coordinate
    }
}

// MARK: - SafetyOfficerView

struct SafetyOfficerView: View {
    @StateObject private var viewModel = SafetyOfficerViewModel()
    
    var body: some View {
        VStack {
            Text("Safety Officer Tools")
                .font(.largeTitle)
                .padding()
            
            if let location = viewModel.location {
                Text("Current Location: \(location.latitude), \(location.longitude)")
                    .padding()
            } else {
                Text("Location not available")
                    .padding()
            }
            
            Button(action: {
                viewModel.performRiskAssessment()
            }) {
                Text("Perform Risk Assessment")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            Text("Risk Assessment: \(viewModel.riskAssessment)")
                .padding()
            
            Button(action: {
                viewModel.reportIncident(description: "Sample incident description")
            }) {
                Text("Report Incident")
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            Text("Incident Report: \(viewModel.incidentReport)")
                .padding()
            
            Button(action: {
                viewModel.updateEmergencyProcedures(procedures: "Sample emergency procedures")
            }) {
                Text("Update Emergency Procedures")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            
            Text("Emergency Procedures: \(viewModel.emergencyProcedures)")
                .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct SafetyOfficerView_Previews: PreviewProvider {
    static var previews: some View {
        SafetyOfficerView()
    }
}