import SwiftUI
import Foundation
import CoreLocation

// MARK: - MissionPlanner

struct MissionPlanner: View {
    @StateObject private var viewModel = MissionPlannerViewModel()
    
    var body: some View {
        VStack {
            MissionListView(missions: $viewModel.missions)
                .padding()

            Button(action: {
                viewModel.addNewMission()
            }) {
                Text("Add New Mission")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Mission Planner")
        .sheet(isPresented: $viewModel.isEditingMission) {
            MissionEditorView(mission: $viewModel.selectedMission)
        }
    }
}

// MARK: - MissionPlannerViewModel

class MissionPlannerViewModel: ObservableObject {
    @Published var missions: [Mission] = []
    @Published var isEditingMission = false
    @Published var selectedMission: Mission?
    
    func addNewMission() {
        let newMission = Mission(id: UUID(), name: "New Mission", phases: [])
        missions.append(newMission)
        selectedMission = newMission
        isEditingMission = true
    }
}

// MARK: - Mission

struct Mission: Identifiable {
    let id: UUID
    var name: String
    var phases: [Phase]
}

// MARK: - Phase

struct Phase {
    var name: String
    var objectives: [Objective]
    var timeline: TimeInterval
}

// MARK: - Objective

struct Objective {
    var description: String
    var location: CLLocationCoordinate2D?
    var riskAssessment: RiskAssessment
}

// MARK: - RiskAssessment

struct RiskAssessment {
    var level: RiskLevel
    var notes: String
}

// MARK: - RiskLevel

enum RiskLevel: String, CaseIterable {
    case low
    case medium
    case high
}

// MARK: - MissionListView

struct MissionListView: View {
    @Binding var missions: [Mission]
    
    var body: some View {
        List($missions) { $mission in
            MissionRow(mission: $mission)
        }
    }
}

// MARK: - MissionRow

struct MissionRow: View {
    @Binding var mission: Mission
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(mission.name)
                .font(.headline)
            Text("\(mission.phases.count) phases")
                .font(.subheadline)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - MissionEditorView

struct MissionEditorView: View {
    @Binding var mission: Mission
    
    var body: some View {
        VStack {
            TextField("Mission Name", text: $mission.name)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            ForEach($mission.phases) { $phase in
                PhaseEditorView(phase: $phase)
            }
            
            Button(action: {
                mission.phases.append(Phase(name: "New Phase", objectives: [], timeline: 0))
            }) {
                Text("Add New Phase")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .padding()
        .navigationTitle("Edit Mission")
    }
}

// MARK: - PhaseEditorView

struct PhaseEditorView: View {
    @Binding var phase: Phase
    
    var body: some View {
        VStack {
            TextField("Phase Name", text: $phase.name)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            ForEach($phase.objectives) { $objective in
                ObjectiveEditorView(objective: $objective)
            }
            
            Button(action: {
                phase.objectives.append(Objective(description: "New Objective", location: nil, riskAssessment: RiskAssessment(level: .low, notes: "")))
            }) {
                Text("Add New Objective")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .padding()
        .navigationTitle("Edit Phase")
    }
}

// MARK: - ObjectiveEditorView

struct ObjectiveEditorView: View {
    @Binding var objective: Objective
    
    var body: some View {
        VStack {
            TextField("Objective Description", text: $objective.description)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                Text("Risk Level:")
                Picker("Risk Level", selection: $objective.riskAssessment.level) {
                    ForEach(RiskLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding()
            
            TextField("Risk Notes", text: $objective.riskAssessment.notes)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding()
        .navigationTitle("Edit Objective")
    }
}