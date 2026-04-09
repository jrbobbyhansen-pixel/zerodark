import Foundation
import SwiftUI

// MARK: - Models

struct TeamMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var role: String
    var skills: [String]
    var qualifications: [String]
    var contactInfo: ContactInfo
    var status: Status
}

struct ContactInfo: Codable {
    var email: String
    var phoneNumber: String
    var address: String
}

enum Status: String, Codable {
    case active
    case onLeave
    case inactive
}

// MARK: - View Models

class TeamRosterViewModel: ObservableObject {
    @Published var teamMembers: [TeamMember] = []
    @Published var isOffline: Bool = false
    
    private let fileManager = FileManager.default
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let rosterFileName = "teamRoster.json"
    
    init() {
        loadTeamRoster()
    }
    
    func addTeamMember(_ member: TeamMember) {
        teamMembers.append(member)
        saveTeamRoster()
    }
    
    func updateTeamMember(_ member: TeamMember) {
        if let index = teamMembers.firstIndex(where: { $0.id == member.id }) {
            teamMembers[index] = member
            saveTeamRoster()
        }
    }
    
    func removeTeamMember(_ member: TeamMember) {
        teamMembers.removeAll { $0.id == member.id }
        saveTeamRoster()
    }
    
    private func saveTeamRoster() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(teamMembers)
            let url = documentsDirectory.appendingPathComponent(rosterFileName)
            try data.write(to: url)
        } catch {
            print("Failed to save team roster: \(error)")
        }
    }
    
    private func loadTeamRoster() {
        let decoder = JSONDecoder()
        let url = documentsDirectory.appendingPathComponent(rosterFileName)
        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                teamMembers = try decoder.decode([TeamMember].self, from: data)
            } catch {
                print("Failed to load team roster: \(error)")
            }
        }
    }
}

// MARK: - Views

struct TeamRosterView: View {
    @StateObject private var viewModel = TeamRosterViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.teamMembers) { member in
                TeamMemberRow(member: member)
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

struct TeamMemberRow: View {
    let member: TeamMember
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(member.name)
                .font(.headline)
            Text(member.role)
                .font(.subheadline)
            Text(member.status.rawValue)
                .font(.caption)
        }
    }
}

// MARK: - Previews

struct TeamRosterView_Previews: PreviewProvider {
    static var previews: some View {
        TeamRosterView()
    }
}