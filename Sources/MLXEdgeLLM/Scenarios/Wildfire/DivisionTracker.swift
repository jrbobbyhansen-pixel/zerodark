import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct Division: Identifiable {
    let id = UUID()
    var name: String
    var supervisor: String
    var radioChannel: String
    var resources: [Resource]
    var currentActivity: String
    var location: CLLocationCoordinate2D
}

struct Resource: Identifiable {
    let id = UUID()
    var name: String
    var status: String
}

// MARK: - View Models

class DivisionTrackerViewModel: ObservableObject {
    @Published var divisions: [Division] = []
    @Published var selectedDivision: Division? = nil
    
    func addDivision(_ division: Division) {
        divisions.append(division)
    }
    
    func updateDivision(_ division: Division) {
        if let index = divisions.firstIndex(where: { $0.id == division.id }) {
            divisions[index] = division
        }
    }
    
    func removeDivision(_ division: Division) {
        divisions.removeAll { $0.id == division.id }
    }
}

// MARK: - Views

struct DivisionTrackerView: View {
    @StateObject private var viewModel = DivisionTrackerViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.divisions) { division in
                NavigationLink(value: division) {
                    DivisionRow(division: division)
                }
            }
            .navigationDestination(for: Division.self) { division in
                DivisionDetailView(division: division)
            }
            .navigationTitle("Division Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new division logic
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct DivisionRow: View {
    let division: Division
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(division.name)
                .font(.headline)
            Text("Supervisor: \(division.supervisor)")
            Text("Radio Channel: \(division.radioChannel)")
            Text("Current Activity: \(division.currentActivity)")
        }
    }
}

struct DivisionDetailView: View {
    let division: Division
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(division.name)
                .font(.largeTitle)
                .padding()
            
            Text("Supervisor: \(division.supervisor)")
                .padding()
            
            Text("Radio Channel: \(division.radioChannel)")
                .padding()
            
            Text("Current Activity: \(division.currentActivity)")
                .padding()
            
            Text("Location: \(division.location.latitude), \(division.location.longitude)")
                .padding()
            
            Text("Resources")
                .font(.headline)
                .padding()
            
            ForEach(division.resources) { resource in
                Text("\(resource.name) - \(resource.status)")
                    .padding()
            }
        }
        .navigationTitle("Division Details")
    }
}

// MARK: - Previews

struct DivisionTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        DivisionTrackerView()
    }
}