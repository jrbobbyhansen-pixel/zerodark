import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Mutual Aid Request System

struct MutualAidRequest: Identifiable, Codable {
    let id: UUID
    let resourceType: ResourceType
    let location: CLLocationCoordinate2D
    let status: Status
    let timestamp: Date
    
    enum ResourceType: String, Codable {
        case medical
        case food
        case shelter
        case other
    }
    
    enum Status: String, Codable {
        case pending
        case inProgress
        case completed
        case cancelled
    }
}

class MutualAidService: ObservableObject {
    @Published private(set) var requests: [MutualAidRequest] = []
    
    func addRequest(_ request: MutualAidRequest) {
        requests.append(request)
    }
    
    func updateRequestStatus(_ id: UUID, to status: MutualAidRequest.Status) {
        if let index = requests.firstIndex(where: { $0.id == id }) {
            requests[index].status = status
        }
    }
    
    func removeRequest(_ id: UUID) {
        requests.removeAll { $0.id == id }
    }
}

// MARK: - SwiftUI View

struct MutualAidView: View {
    @StateObject private var viewModel = MutualAidViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.requests) { request in
                MutualAidRequestRow(request: request)
            }
            .navigationTitle("Mutual Aid Requests")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: viewModel.addNewRequest) {
                        Label("New Request", systemImage: "plus")
                    }
                }
            }
        }
    }
}

class MutualAidViewModel: ObservableObject {
    @Published var requests: [MutualAidRequest] = []
    private let service: MutualAidService
    
    init(service: MutualAidService = MutualAidService()) {
        self.service = service
        self.requests = service.requests
    }
    
    func addNewRequest() {
        let newRequest = MutualAidRequest(
            id: UUID(),
            resourceType: .medical,
            location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            status: .pending,
            timestamp: Date()
        )
        service.addRequest(newRequest)
        requests.append(newRequest)
    }
}

struct MutualAidRequestRow: View {
    let request: MutualAidRequest
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Resource: \(request.resourceType.rawValue.capitalized)")
                .font(.headline)
            Text("Location: \(request.location.latitude), \(request.location.longitude)")
                .font(.subheadline)
            Text("Status: \(request.status.rawValue.capitalized)")
                .font(.subheadline)
            Text("Timestamp: \(request.timestamp, style: .date)")
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

struct MutualAidView_Previews: PreviewProvider {
    static var previews: some View {
        MutualAidView()
    }
}