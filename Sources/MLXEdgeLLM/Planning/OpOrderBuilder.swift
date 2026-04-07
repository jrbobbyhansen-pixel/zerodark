import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Operations Order Builder

class OpOrderBuilder: ObservableObject {
    @Published var missionType: MissionType = .reconnaissance
    @Published var objectives: [Objective] = []
    @Published var acknowledgments: [String] = []
    
    func addObjective(_ objective: Objective) {
        objectives.append(objective)
    }
    
    func removeObjective(at index: Int) {
        objectives.remove(at: index)
    }
    
    func exportOrder() -> String {
        var order = "Operations Order\n"
        order += "Mission Type: \(missionType.rawValue)\n"
        order += "Objectives:\n"
        for (index, objective) in objectives.enumerated() {
            order += "\(index + 1). \(objective.description)\n"
        }
        return order
    }
    
    func trackAcknowledgment(_ acknowledgment: String) {
        acknowledgments.append(acknowledgment)
    }
}

// MARK: - Mission Types

enum MissionType: String, CaseIterable {
    case reconnaissance = "Reconnaissance"
    case assault = "Assault"
    case extraction = "Extraction"
    case support = "Support"
    case patrol = "Patrol"
}

// MARK: - Objective

struct Objective: Identifiable {
    let id = UUID()
    let description: String
}

// MARK: - SwiftUI View

struct OpOrderBuilderView: View {
    @StateObject private var viewModel = OpOrderBuilder()
    
    var body: some View {
        VStack {
            Picker("Mission Type", selection: $viewModel.missionType) {
                ForEach(MissionType.allCases, id: \.self) { type in
                    Text(type.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            List {
                ForEach(viewModel.objectives) { objective in
                    Text(objective.description)
                }
                .onDelete { indexSet in
                    viewModel.removeObjective(at: indexSet.first!)
                }
            }
            .listStyle(PlainListStyle())
            
            TextField("Add Objective", text: Binding(
                get: { "" },
                set: { viewModel.addObjective(Objective(description: $0)) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding()
            
            Button("Export Order") {
                let order = viewModel.exportOrder()
                print(order)
                // Implement export logic here
            }
            .padding()
            
            Text("Acknowledgments:")
                .font(.headline)
            
            List(viewModel.acknowledgments, id: \.self) { acknowledgment in
                Text(acknowledgment)
            }
            .listStyle(PlainListStyle())
        }
        .padding()
        .navigationTitle("Operations Order Builder")
    }
}

// MARK: - Preview

struct OpOrderBuilderView_Previews: PreviewProvider {
    static var previews: some View {
        OpOrderBuilderView()
    }
}