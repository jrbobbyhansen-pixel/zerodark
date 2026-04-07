import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - SwiftWaterProtocol

struct SwiftWaterProtocol {
    var checklist: [ChecklistItem]
    var procedures: [ProcedureStep]
    var hazardIdentifications: [Hazard]
    var victimApproachTechniques: [ApproachTechnique]
}

// MARK: - ChecklistItem

struct ChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    var isCompleted: Bool
}

// MARK: - ProcedureStep

struct ProcedureStep: Identifiable {
    let id = UUID()
    let stepNumber: Int
    let description: String
}

// MARK: - Hazard

struct Hazard: Identifiable {
    let id = UUID()
    let type: String
    let description: String
    let location: CLLocationCoordinate2D?
}

// MARK: - ApproachTechnique

struct ApproachTechnique: Identifiable {
    let id = UUID()
    let technique: String
    let description: String
}

// MARK: - ViewModel

class SwiftWaterProtocolViewModel: ObservableObject {
    @Published var protocolData: SwiftWaterProtocol
    
    init() {
        let checklist = [
            ChecklistItem(title: "Assess Situation", description: "Evaluate the water conditions and potential hazards.", isCompleted: false),
            ChecklistItem(title: "Check Equipment", description: "Ensure all rescue equipment is available and in working order.", isCompleted: false),
            ChecklistItem(title: "Communicate", description: "Inform team members of the plan and any changes.", isCompleted: false)
        ]
        
        let procedures = [
            ProcedureStep(stepNumber: 1, description: "Identify the victim's location."),
            ProcedureStep(stepNumber: 2, description: "Establish a safe approach path."),
            ProcedureStep(stepNumber: 3, description: "Deploy rescue equipment as needed."),
            ProcedureStep(stepNumber: 4, description: "Rescue the victim and provide immediate medical attention if necessary.")
        ]
        
        let hazardIdentifications = [
            Hazard(type: "Strong Currents", description: "Water moving rapidly can be dangerous.", location: nil),
            Hazard(type: "Debris", description: "Floating objects can pose a risk to rescuers and victims.", location: nil)
        ]
        
        let victimApproachTechniques = [
            ApproachTechnique(technique: "Throw-Row-Go", description: "Use a throw rope to reach the victim, then row or swim to them."),
            ApproachTechnique(technique: "Swim Approach", description: "Swim directly to the victim, maintaining a safe distance.")
        ]
        
        self.protocolData = SwiftWaterProtocol(checklist: checklist, procedures: procedures, hazardIdentifications: hazardIdentifications, victimApproachTechniques: victimApproachTechniques)
    }
}

// MARK: - View

struct SwiftWaterProtocolView: View {
    @StateObject private var viewModel = SwiftWaterProtocolViewModel()
    
    var body: some View {
        VStack {
            Text("Swift Water Rescue Protocol")
                .font(.largeTitle)
                .padding()
            
            // Checklist
            Section(header: Text("Checklist")) {
                ForEach($viewModel.protocolData.checklist) { $item in
                    HStack {
                        Text(item.title)
                        Spacer()
                        Toggle(isOn: $item.isCompleted) {
                            Text(item.description)
                        }
                    }
                }
            }
            
            // Procedures
            Section(header: Text("Procedures")) {
                ForEach(viewModel.protocolData.procedures) { step in
                    Text("\(step.stepNumber). \(step.description)")
                }
            }
            
            // Hazards
            Section(header: Text("Hazard Identification")) {
                ForEach(viewModel.protocolData.hazardIdentifications) { hazard in
                    VStack(alignment: .leading) {
                        Text(hazard.type)
                        Text(hazard.description)
                    }
                }
            }
            
            // Victim Approach Techniques
            Section(header: Text("Victim Approach Techniques")) {
                ForEach(viewModel.protocolData.victimApproachTechniques) { technique in
                    VStack(alignment: .leading) {
                        Text(technique.technique)
                        Text(technique.description)
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Swift Water Rescue")
    }
}

// MARK: - Preview

struct SwiftWaterProtocolView_Previews: PreviewProvider {
    static var previews: some View {
        SwiftWaterProtocolView()
    }
}