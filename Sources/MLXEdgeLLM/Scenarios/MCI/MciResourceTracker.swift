import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct MciResource {
    let id: UUID
    let type: ResourceType
    let status: ResourceStatus
    let location: CLLocationCoordinate2D
    let assignedTo: String?
}

enum ResourceType: String, Codable {
    case ambulance
    case personnel
    case equipment
}

enum ResourceStatus: String, Codable {
    case staging
    case deployed
}

// MARK: - View Models

class MciResourceTrackerViewModel: ObservableObject {
    @Published var resources: [MciResource] = []
    @Published var selectedResource: MciResource?
    
    func requestResource(_ resource: MciResource) {
        // Logic to request resource
        if let index = resources.firstIndex(where: { $0.id == resource.id }) {
            resources[index].status = .deployed
        }
    }
    
    func releaseResource(_ resource: MciResource) {
        // Logic to release resource
        if let index = resources.firstIndex(where: { $0.id == resource.id }) {
            resources[index].status = .staging
        }
    }
}

// MARK: - Views

struct MciResourceTrackerView: View {
    @StateObject private var viewModel = MciResourceTrackerViewModel()
    
    var body: some View {
        VStack {
            List(viewModel.resources) { resource in
                HStack {
                    Text(resource.type.rawValue.capitalized)
                        .font(.headline)
                    Spacer()
                    Text(resource.status.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundColor(resource.status == .deployed ? .red : .green)
                }
                .onTapGesture {
                    viewModel.selectedResource = resource
                }
            }
            
            if let selectedResource = viewModel.selectedResource {
                VStack {
                    Text("Details for \(selectedResource.type.rawValue.capitalized)")
                        .font(.title2)
                    
                    HStack {
                        Text("Status:")
                        Text(selectedResource.status.rawValue.capitalized)
                    }
                    
                    HStack {
                        Text("Location:")
                        Text("\(selectedResource.location.latitude), \(selectedResource.location.longitude)")
                    }
                    
                    HStack {
                        Button("Request") {
                            viewModel.requestResource(selectedResource)
                        }
                        .disabled(selectedResource.status == .deployed)
                        
                        Button("Release") {
                            viewModel.releaseResource(selectedResource)
                        }
                        .disabled(selectedResource.status == .staging)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding()
        .navigationTitle("MCI Resource Tracker")
    }
}

// MARK: - Previews

struct MciResourceTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        MciResourceTrackerView()
    }
}