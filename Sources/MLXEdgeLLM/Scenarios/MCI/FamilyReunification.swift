import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct Victim: Identifiable {
    let id = UUID()
    let photo: UIImage
    let description: String
    let location: CLLocationCoordinate2D
    var status: String
}

// MARK: - ViewModel

class FamilyReunificationViewModel: ObservableObject {
    @Published var victims: [Victim] = []
    @Published var searchQuery: String = ""
    @Published var selectedVictim: Victim? = nil
    
    func addVictim(photo: UIImage, description: String, location: CLLocationCoordinate2D, status: String) {
        let newVictim = Victim(photo: photo, description: description, location: location, status: status)
        victims.append(newVictim)
    }
    
    func updateVictimStatus(victim: Victim, newStatus: String) {
        if let index = victims.firstIndex(of: victim) {
            victims[index].status = newStatus
        }
    }
    
    func searchVictims(by query: String) -> [Victim] {
        return victims.filter { $0.description.lowercased().contains(query.lowercased()) }
    }
}

// MARK: - Views

struct FamilyReunificationView: View {
    @StateObject private var viewModel = FamilyReunificationViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $viewModel.searchQuery)
                    .padding()
                
                List(viewModel.searchVictims(by: viewModel.searchQuery), id: \.id) { victim in
                    VStack(alignment: .leading) {
                        Image(uiImage: victim.photo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                        
                        Text(victim.description)
                            .font(.headline)
                        
                        Text(victim.status)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        viewModel.selectedVictim = victim
                    }
                }
            }
            .navigationTitle("Family Reunification")
            .sheet(item: $viewModel.selectedVictim) { victim in
                VictimDetailView(victim: victim, viewModel: viewModel)
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            TextField("Search by description", text: $text)
                .padding(8)
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
    }
}

struct VictimDetailView: View {
    let victim: Victim
    @ObservedObject var viewModel: FamilyReunificationViewModel
    
    var body: some View {
        VStack {
            Image(uiImage: victim.photo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
            
            Text(victim.description)
                .font(.headline)
                .padding()
            
            Text(victim.status)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
            
            Button(action: {
                viewModel.updateVictimStatus(victim: victim, newStatus: "Reunited")
            }) {
                Text("Mark as Reunited")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .navigationTitle("Victim Details")
    }
}

// MARK: - Preview

struct FamilyReunificationView_Previews: PreviewProvider {
    static var previews: some View {
        FamilyReunificationView()
    }
}