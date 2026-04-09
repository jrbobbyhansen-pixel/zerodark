import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct Incident: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let location: CLLocationCoordinate2D
    let type: IncidentType
    let description: String
    var photo: UIImage?
    var audio: URL?
}

enum IncidentType: String, Codable {
    case observation
    case incident
    case alert
}

// MARK: - View Models

class IncidentLogViewModel: ObservableObject {
    @Published private(set) var incidents: [Incident] = []
    @Published var newIncidentDescription: String = ""
    @Published var newIncidentType: IncidentType = .observation
    @Published var newIncidentPhoto: UIImage?
    @Published var newIncidentAudio: URL?
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func addIncident() {
        guard let location = locationManager.location?.coordinate else { return }
        let incident = Incident(
            timestamp: Date(),
            location: location,
            type: newIncidentType,
            description: newIncidentDescription,
            photo: newIncidentPhoto,
            audio: newIncidentAudio
        )
        incidents.append(incident)
        clearNewIncidentFields()
    }
    
    private func clearNewIncidentFields() {
        newIncidentDescription = ""
        newIncidentType = .observation
        newIncidentPhoto = nil
        newIncidentAudio = nil
    }
}

extension IncidentLogViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location update handling if needed
    }
}

// MARK: - Views

struct IncidentLogView: View {
    @StateObject private var viewModel = IncidentLogViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                List(viewModel.incidents) { incident in
                    IncidentRow(incident: incident)
                }
                .listStyle(PlainListStyle())
                
                Spacer()
                
                IncidentInputView(viewModel: viewModel)
            }
            .navigationTitle("Incident Log")
            .padding()
        }
    }
}

struct IncidentRow: View {
    let incident: Incident
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(incident.description)
                .font(.headline)
            Text(incident.type.rawValue)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(incident.timestamp, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct IncidentInputView: View {
    @ObservedObject var viewModel: IncidentLogViewModel
    
    var body: some View {
        VStack {
            TextField("Description", text: $viewModel.newIncidentDescription)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Picker("Type", selection: $viewModel.newIncidentType) {
                ForEach(IncidentType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            Button(action: {
                // Add photo functionality
            }) {
                Text("Add Photo")
            }
            .padding()
            
            Button(action: {
                // Add audio functionality
            }) {
                Text("Add Audio")
            }
            .padding()
            
            Button(action: {
                viewModel.addIncident()
            }) {
                Text("Add Incident")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

// MARK: - Preview

struct IncidentLogView_Previews: PreviewProvider {
    static var previews: some View {
        IncidentLogView()
    }
}