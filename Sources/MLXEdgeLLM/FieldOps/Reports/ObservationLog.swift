import SwiftUI
import Foundation
import CoreLocation
import AVFoundation

// MARK: - Observation Model

struct Observation: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let location: CLLocationCoordinate2D
    let details: String
    let photos: [UIImage]
    let category: String
}

// MARK: - Observation Log ViewModel

class ObservationLogViewModel: ObservableObject {
    @Published var observations: [Observation] = []
    @Published var searchText: String = ""
    
    func addObservation(timestamp: Date, location: CLLocationCoordinate2D, details: String, photos: [UIImage], category: String) {
        let newObservation = Observation(timestamp: timestamp, location: location, details: details, photos: photos, category: category)
        observations.append(newObservation)
    }
    
    func filteredObservations() -> [Observation] {
        if searchText.isEmpty {
            return observations
        } else {
            return observations.filter { observation in
                observation.details.lowercased().contains(searchText.lowercased()) ||
                observation.category.lowercased().contains(searchText.lowercased())
            }
        }
    }
}

// MARK: - Observation Log View

struct ObservationLogView: View {
    @StateObject private var viewModel = ObservationLogViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $viewModel.searchText)
                
                List(viewModel.filteredObservations()) { observation in
                    ObservationRow(observation: observation)
                }
            }
            .navigationTitle("Observation Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new observation logic here
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Observation Row View

struct ObservationRow: View {
    let observation: Observation
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(observation.timestamp, style: .date)
                .font(.caption)
            Text(observation.details)
                .font(.body)
            Text(observation.category)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Search Bar View

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            TextField("Search", text: $text)
                .padding(7)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Preview

struct ObservationLogView_Previews: PreviewProvider {
    static var previews: some View {
        ObservationLogView()
    }
}