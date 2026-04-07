import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

struct MedevacRequest: Identifiable {
    let id = UUID()
    var patientName: String
    var patientCondition: String
    var location: CLLocationCoordinate2D
    var contactNumber: String
    var requestTime: Date
    var status: String
}

class MedevacViewModel: ObservableObject {
    @Published var medevacRequest: MedevacRequest?
    @Published var status: String = "Pending"
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func generateRequest(patientName: String, patientCondition: String, contactNumber: String) {
        guard let location = locationManager.location?.coordinate else { return }
        let request = MedevacRequest(
            patientName: patientName,
            patientCondition: patientCondition,
            location: location,
            contactNumber: contactNumber,
            requestTime: Date(),
            status: status
        )
        medevacRequest = request
        transmitRequest(request)
    }
    
    private func transmitRequest(_ request: MedevacRequest) {
        // Implementation for mesh network transmission
        // Placeholder for actual mesh network code
        status = "Transmitted"
    }
}

extension MedevacViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            medevacRequest?.location = location.coordinate
        }
    }
}

struct MedevacView: View {
    @StateObject private var viewModel = MedevacViewModel()
    @State private var patientName = ""
    @State private var patientCondition = ""
    @State private var contactNumber = ""
    
    var body: some View {
        VStack {
            TextField("Patient Name", text: $patientName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            TextField("Patient Condition", text: $patientCondition)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            TextField("Contact Number", text: $contactNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button(action: {
                viewModel.generateRequest(
                    patientName: patientName,
                    patientCondition: patientCondition,
                    contactNumber: contactNumber
                )
            }) {
                Text("Send MEDEVAC Request")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Text("Status: \(viewModel.status)")
                .padding()
        }
        .padding()
        .navigationTitle("MEDEVAC Request")
    }
}

struct MedevacView_Previews: PreviewProvider {
    static var previews: some View {
        MedevacView()
    }
}