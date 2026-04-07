import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Models

struct Victim {
    let id: UUID
    var location: CLLocationCoordinate2D
    var timeInRubble: TimeInterval
    var medicalStatus: String
    var equipmentNeeds: [String]
    var personnelAssigned: [String]
}

// MARK: - ViewModel

class VictimExtricationViewModel: ObservableObject {
    @Published var victims: [Victim] = []
    @Published var selectedVictim: Victim?
    
    func addVictim(location: CLLocationCoordinate2D, medicalStatus: String, equipmentNeeds: [String], personnelAssigned: [String]) {
        let newVictim = Victim(id: UUID(), location: location, timeInRubble: 0, medicalStatus: medicalStatus, equipmentNeeds: equipmentNeeds, personnelAssigned: personnelAssigned)
        victims.append(newVictim)
    }
    
    func updateVictim(victim: Victim, medicalStatus: String, equipmentNeeds: [String], personnelAssigned: [String]) {
        if let index = victims.firstIndex(where: { $0.id == victim.id }) {
            victims[index] = Victim(id: victim.id, location: victim.location, timeInRubble: victim.timeInRubble, medicalStatus: medicalStatus, equipmentNeeds: equipmentNeeds, personnelAssigned: personnelAssigned)
        }
    }
    
    func removeVictim(victim: Victim) {
        victims.removeAll { $0.id == victim.id }
    }
}

// MARK: - Views

struct VictimExtricationView: View {
    @StateObject private var viewModel = VictimExtricationViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.victims) { victim in
                VStack(alignment: .leading) {
                    Text("Victim ID: \(victim.id.uuidString)")
                        .font(.headline)
                    Text("Location: \(victim.location.latitude), \(victim.location.longitude)")
                        .font(.subheadline)
                    Text("Time in Rubble: \(String(format: "%.2f", victim.timeInRubble)) seconds")
                        .font(.subheadline)
                    Text("Medical Status: \(victim.medicalStatus)")
                        .font(.subheadline)
                    Text("Equipment Needs: \(victim.equipmentNeeds.joined(separator: ", "))")
                        .font(.subheadline)
                    Text("Personnel Assigned: \(victim.personnelAssigned.joined(separator: ", "))")
                        .font(.subheadline)
                }
                .onTapGesture {
                    viewModel.selectedVictim = victim
                }
            }
            .navigationTitle("Victim Extrication Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new victim
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $viewModel.selectedVictim) { victim in
                VictimDetailView(victim: victim, viewModel: viewModel)
            }
        }
    }
}

struct VictimDetailView: View {
    let victim: Victim
    @ObservedObject var viewModel: VictimExtricationViewModel
    
    var body: some View {
        Form {
            Section(header: Text("Victim Details")) {
                TextField("Medical Status", text: Binding(
                    get: { victim.medicalStatus },
                    set: { viewModel.updateVictim(victim: victim, medicalStatus: $0, equipmentNeeds: victim.equipmentNeeds, personnelAssigned: victim.personnelAssigned) }
                ))
                
                TextField("Equipment Needs", text: Binding(
                    get: { victim.equipmentNeeds.joined(separator: ", ") },
                    set: { viewModel.updateVictim(victim: victim, medicalStatus: victim.medicalStatus, equipmentNeeds: $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }, personnelAssigned: victim.personnelAssigned) }
                ))
                
                TextField("Personnel Assigned", text: Binding(
                    get: { victim.personnelAssigned.joined(separator: ", ") },
                    set: { viewModel.updateVictim(victim: victim, medicalStatus: victim.medicalStatus, equipmentNeeds: victim.equipmentNeeds, personnelAssigned: $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }) }
                ))
            }
        }
        .navigationTitle("Victim \(victim.id.uuidString)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.removeVictim(victim: victim)
                }) {
                    Image(systemName: "trash")
                }
            }
        }
    }
}

// MARK: - Preview

struct VictimExtricationView_Previews: PreviewProvider {
    static var previews: some View {
        VictimExtricationView()
    }
}