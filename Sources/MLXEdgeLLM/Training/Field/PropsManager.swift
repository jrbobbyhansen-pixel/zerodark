import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - PropsManager

class PropsManager: ObservableObject {
    @Published var victimCards: [VictimCard] = []
    @Published var moulageInstructions: [MoulageInstruction] = []
    @Published var inventory: [String: Int] = [:]
    
    func addVictimCard(card: VictimCard) {
        victimCards.append(card)
    }
    
    func removeVictimCard(card: VictimCard) {
        if let index = victimCards.firstIndex(of: card) {
            victimCards.remove(at: index)
        }
    }
    
    func addMoulageInstruction(instruction: MoulageInstruction) {
        moulageInstructions.append(instruction)
    }
    
    func removeMoulageInstruction(instruction: MoulageInstruction) {
        if let index = moulageInstructions.firstIndex(of: instruction) {
            moulageInstructions.remove(at: index)
        }
    }
    
    func updateInventory(item: String, quantity: Int) {
        inventory[item] = quantity
    }
}

// MARK: - VictimCard

struct VictimCard: Identifiable {
    let id = UUID()
    let name: String
    let symptoms: [String]
    let location: CLLocationCoordinate2D
}

// MARK: - MoulageInstruction

struct MoulageInstruction: Identifiable {
    let id = UUID()
    let description: String
    let steps: [String]
}

// MARK: - PropsManagerView

struct PropsManagerView: View {
    @StateObject private var propsManager = PropsManager()
    
    var body: some View {
        NavigationView {
            VStack {
                List(propsManager.victimCards) { card in
                    VStack(alignment: .leading) {
                        Text(card.name)
                            .font(.headline)
                        Text("Symptoms: \(card.symptoms.joined(separator: ", "))")
                            .font(.subheadline)
                        Text("Location: \(card.location.latitude), \(card.location.longitude)")
                            .font(.subheadline)
                    }
                }
                .navigationTitle("Victim Cards")
                
                List(propsManager.moulageInstructions) { instruction in
                    VStack(alignment: .leading) {
                        Text(instruction.description)
                            .font(.headline)
                        Text("Steps: \(instruction.steps.joined(separator: ", "))")
                            .font(.subheadline)
                    }
                }
                .navigationTitle("Moulage Instructions")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new victim card
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct PropsManagerView_Previews: PreviewProvider {
    static var previews: some View {
        PropsManagerView()
    }
}