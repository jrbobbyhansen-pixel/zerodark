import Foundation
import SwiftUI

// MARK: - Team Member Model

struct TeamMember: Identifiable, Codable {
    let id = UUID()
    var name: String
    var callsign: String
    var role: String
    var radioChannel: Int
    var bloodType: String
    var allergies: [String]
    var emergencyContact: String
}

// MARK: - Team Roster Manager

class TeamRosterManager: ObservableObject {
    @Published var teamMembers: [TeamMember] = []
    
    // Sync via mesh network
    func syncRoster() {
        // Implementation for syncing roster via mesh network
    }
    
    // Add a new team member
    func addTeamMember(_ member: TeamMember) {
        teamMembers.append(member)
    }
    
    // Remove a team member
    func removeTeamMember(_ member: TeamMember) {
        teamMembers.removeAll { $0.id == member.id }
    }
    
    // Update a team member
    func updateTeamMember(_ member: TeamMember) {
        if let index = teamMembers.firstIndex(where: { $0.id == member.id }) {
            teamMembers[index] = member
        }
    }
}

// MARK: - SwiftUI View

struct TeamRosterView: View {
    @StateObject private var viewModel = TeamRosterManager()
    
    var body: some View {
        NavigationView {
            List(viewModel.teamMembers) { member in
                VStack(alignment: .leading) {
                    Text(member.name)
                        .font(.headline)
                    Text("Callsign: \(member.callsign)")
                    Text("Role: \(member.role)")
                    Text("Radio Channel: \(member.radioChannel)")
                    Text("Blood Type: \(member.bloodType)")
                    Text("Allergies: \(member.allergies.joined(separator: ", "))")
                    Text("Emergency Contact: \(member.emergencyContact)")
                }
            }
            .navigationTitle("Team Roster")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new team member
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Previews

struct TeamRosterView_Previews: PreviewProvider {
    static var previews: some View {
        TeamRosterView()
    }
}