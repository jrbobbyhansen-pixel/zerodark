import SwiftUI
import Foundation

// MARK: - SkillTracker Model

struct Skill: Identifiable {
    let id = UUID()
    let name: String
    let certification: String
    let expirationDate: Date
    let isExpired: Bool {
        expirationDate < Date()
    }
}

class SkillTracker: ObservableObject {
    @Published var skills: [Skill] = []
    
    func addSkill(name: String, certification: String, expirationDate: Date) {
        let newSkill = Skill(name: name, certification: certification, expirationDate: expirationDate)
        skills.append(newSkill)
    }
    
    func removeSkill(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }
    }
    
    func updateSkill(_ skill: Skill, newName: String, newCertification: String, newExpirationDate: Date) {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index] = Skill(id: skill.id, name: newName, certification: newCertification, expirationDate: newExpirationDate)
        }
    }
}

// MARK: - SkillTracker View

struct SkillTrackerView: View {
    @StateObject private var viewModel = SkillTracker()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.skills) { skill in
                    VStack(alignment: .leading) {
                        Text(skill.name)
                            .font(.headline)
                        Text(skill.certification)
                            .font(.subheadline)
                        Text(skill.expirationDate, style: .date)
                            .font(.caption)
                            .foregroundColor(skill.isExpired ? .red : .black)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.removeSkill(skill)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Skill Tracker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new skill logic here
                    }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct SkillTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        SkillTrackerView()
    }
}