import SwiftUI
import Foundation
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct TriageCategory: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct TransportStatus: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct HospitalDestination: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct Resource: Identifiable {
    let id = UUID()
    let name: String
    let quantity: Int
}

struct StagingArea: Identifiable {
    let id = UUID()
    let name: String
    let location: CLLocationCoordinate2D
}

// MARK: - View Models

class MciDashboardViewModel: ObservableObject {
    @Published var triageCategories: [TriageCategory] = [
        TriageCategory(name: "Minor", count: 10),
        TriageCategory(name: "Moderate", count: 5),
        TriageCategory(name: "Severe", count: 3)
    ]
    
    @Published var transportStatuses: [TransportStatus] = [
        TransportStatus(name: "En Route", count: 8),
        TransportStatus(name: "Awaiting Transport", count: 7)
    ]
    
    @Published var hospitalDestinations: [HospitalDestination] = [
        HospitalDestination(name: "City Hospital", count: 6),
        HospitalDestination(name: "Regional Hospital", count: 4)
    ]
    
    @Published var resources: [Resource] = [
        Resource(name: "Medicines", quantity: 150),
        Resource(name: "Bandages", quantity: 200)
    ]
    
    @Published var stagingAreas: [StagingArea] = [
        StagingArea(name: "Staging Area 1", location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
        StagingArea(name: "Staging Area 2", location: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195))
    ]
}

// MARK: - Views

struct MciDashboardView: View {
    @StateObject private var viewModel = MciDashboardViewModel()
    
    var body: some View {
        VStack {
            Text("Mass Casualty Incident Dashboard")
                .font(.largeTitle)
                .padding()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Section(header: Text("Triage Categories")) {
                        ForEach(viewModel.triageCategories) { category in
                            HStack {
                                Text(category.name)
                                Spacer()
                                Text("\(category.count)")
                            }
                        }
                    }
                    
                    Section(header: Text("Transport Status")) {
                        ForEach(viewModel.transportStatuses) { status in
                            HStack {
                                Text(status.name)
                                Spacer()
                                Text("\(status.count)")
                            }
                        }
                    }
                    
                    Section(header: Text("Hospital Destinations")) {
                        ForEach(viewModel.hospitalDestinations) { destination in
                            HStack {
                                Text(destination.name)
                                Spacer()
                                Text("\(destination.count)")
                            }
                        }
                    }
                    
                    Section(header: Text("Resources")) {
                        ForEach(viewModel.resources) { resource in
                            HStack {
                                Text(resource.name)
                                Spacer()
                                Text("\(resource.quantity)")
                            }
                        }
                    }
                    
                    Section(header: Text("Staging Areas")) {
                        ForEach(viewModel.stagingAreas) { area in
                            HStack {
                                Text(area.name)
                                Spacer()
                                Text("\(area.location.latitude), \(area.location.longitude)")
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct MciDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        MciDashboardView()
    }
}