import Foundation
import SwiftUI

// MARK: - Mission Briefing Model

struct MissionBriefing {
    let missionName: String
    let objective: String
    let enemy: String
    let weather: String
    let terrain: String
    let teamAssignments: [String: [String]]
}

// MARK: - Mission Briefing ViewModel

class MissionBriefingViewModel: ObservableObject {
    @Published var briefing: MissionBriefing
    
    init(briefing: MissionBriefing) {
        self.briefing = briefing
    }
    
    func generateSMEAC() -> String {
        return """
        Mission Name: \(briefing.missionName)
        Objective: \(briefing.objective)
        Enemy: \(briefing.enemy)
        Weather: \(briefing.weather)
        Terrain: \(briefing.terrain)
        Team Assignments: \(teamAssignmentsToString())
        """
    }
    
    private func teamAssignmentsToString() -> String {
        var assignmentsString = ""
        for (role, members) in briefing.teamAssignments {
            assignmentsString += "\(role): \(members.joined(separator: ", "))\n"
        }
        return assignmentsString
    }
}

// MARK: - Mission Briefing View

struct MissionBriefingView: View {
    @StateObject private var viewModel: MissionBriefingViewModel
    
    init(briefing: MissionBriefing) {
        self._viewModel = StateObject(wrappedValue: MissionBriefingViewModel(briefing: briefing))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mission Briefing")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(viewModel.generateSMEAC())
                .font(.body)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
        }
        .padding()
    }
}

// MARK: - Preview

struct MissionBriefingView_Previews: PreviewProvider {
    static var previews: some View {
        MissionBriefingView(briefing: MissionBriefing(
            missionName: "Operation Swift Strike",
            objective: "Capture the objective point",
            enemy: "Hostile forces",
            weather: "Clear skies",
            terrain: "Urban environment",
            teamAssignments: [
                "Leader": ["Alice", "Bob"],
                "Support": ["Charlie", "Delta"]
            ]
        ))
    }
}