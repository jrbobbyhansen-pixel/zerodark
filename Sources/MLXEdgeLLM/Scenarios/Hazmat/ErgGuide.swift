import Foundation
import SwiftUI

// MARK: - Models

struct HazardousMaterial: Identifiable {
    let id = UUID()
    let unNumber: String
    let name: String
    let placard: String
    let safetyDistance: String
    let fireResponse: String
    let spillResponse: String
}

// MARK: - ViewModel

class ErgGuideViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var filteredHazards: [HazardousMaterial] = []
    @Published var selectedHazard: HazardousMaterial? = nil
    
    private let hazards: [HazardousMaterial] = [
        HazardousMaterial(unNumber: "UN0001", name: "Acetylene", placard: "Red and white", safetyDistance: "10 meters", fireResponse: "Evacuate area", spillResponse: "Contain spill"),
        HazardousMaterial(unNumber: "UN0002", name: "Ammonia", placard: "Yellow and black", safetyDistance: "20 meters", fireResponse: "Use water", spillResponse: "Absorb with dry materials"),
        // Add more hazardous materials as needed
    ]
    
    init() {
        filteredHazards = hazards
    }
    
    func searchHazards() {
        if searchQuery.isEmpty {
            filteredHazards = hazards
        } else {
            filteredHazards = hazards.filter { hazard in
                hazard.unNumber.contains(searchQuery) || hazard.name.contains(searchQuery) || hazard.placard.contains(searchQuery)
            }
        }
    }
}

// MARK: - Views

struct ErgGuideView: View {
    @StateObject private var viewModel = ErgGuideViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $viewModel.searchQuery, onSearch: viewModel.searchHazards)
                
                List(viewModel.filteredHazards) { hazard in
                    NavigationLink(value: hazard) {
                        HazardRow(hazard: hazard)
                    }
                }
                .navigationDestination(for: HazardousMaterial.self) { hazard in
                    HazardDetailView(hazard: hazard)
                }
            }
            .navigationTitle("Emergency Response Guide")
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let onSearch: () -> Void
    
    var body: some View {
        HStack {
            TextField("Search by UN number, name, or placard", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .padding()
            }
        }
    }
}

struct HazardRow: View {
    let hazard: HazardousMaterial
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(hazard.name)
                    .font(.headline)
                Text("UN: \(hazard.unNumber)")
                    .font(.subheadline)
                Text("Placard: \(hazard.placard)")
                    .font(.subheadline)
            }
        }
    }
}

struct HazardDetailView: View {
    let hazard: HazardousMaterial
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(hazard.name)
                .font(.largeTitle)
                .padding()
            
            HStack {
                Text("UN Number:")
                Spacer()
                Text(hazard.unNumber)
            }
            .padding()
            
            HStack {
                Text("Placard:")
                Spacer()
                Text(hazard.placard)
            }
            .padding()
            
            HStack {
                Text("Safety Distance:")
                Spacer()
                Text(hazard.safetyDistance)
            }
            .padding()
            
            HStack {
                Text("Fire Response:")
                Spacer()
                Text(hazard.fireResponse)
            }
            .padding()
            
            HStack {
                Text("Spill Response:")
                Spacer()
                Text(hazard.spillResponse)
            }
            .padding()
        }
        .navigationTitle("Hazard Details")
    }
}

// MARK: - Preview

struct ErgGuideView_Previews: PreviewProvider {
    static var previews: some View {
        ErgGuideView()
    }
}