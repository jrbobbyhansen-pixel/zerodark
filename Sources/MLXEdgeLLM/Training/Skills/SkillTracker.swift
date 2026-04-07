import Foundation
import SwiftUI

// MARK: - SkillTracker

class SkillTracker: ObservableObject {
    @Published var skills: [Skill] = []
    @Published var certifications: [Certification] = []
    
    func addSkill(_ skill: Skill) {
        skills.append(skill)
    }
    
    func addCertification(_ certification: Certification) {
        certifications.append(certification)
    }
    
    func removeSkill(at index: Int) {
        skills.remove(at: index)
    }
    
    func removeCertification(at index: Int) {
        certifications.remove(at: index)
    }
    
    func updateSkill(at index: Int, with skill: Skill) {
        skills[index] = skill
    }
    
    func updateCertification(at index: Int, with certification: Certification) {
        certifications[index] = certification
    }
    
    func gapAnalysis() -> [String] {
        var gaps: [String] = []
        
        for skill in skills {
            if skill.expirationDate < Date() {
                gaps.append("Skill \(skill.name) is expired.")
            }
        }
        
        for certification in certifications {
            if certification.expirationDate < Date() {
                gaps.append("Certification \(certification.name) is expired.")
            }
        }
        
        return gaps
    }
}

// MARK: - Skill

struct Skill: Identifiable {
    let id = UUID()
    var name: String
    var level: Int
    var expirationDate: Date
}

// MARK: - Certification

struct Certification: Identifiable {
    let id = UUID()
    var name: String
    var expirationDate: Date
}

// MARK: - SkillView

struct SkillView: View {
    @StateObject private var viewModel = SkillTracker()
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("Skills")) {
                        ForEach(viewModel.skills) { skill in
                            HStack {
                                Text(skill.name)
                                Spacer()
                                Text("Level: \(skill.level)")
                            }
                        }
                        .onDelete { indexSet in
                            viewModel.skills.remove(atOffsets: indexSet)
                        }
                    }
                    
                    Section(header: Text("Certifications")) {
                        ForEach(viewModel.certifications) { certification in
                            HStack {
                                Text(certification.name)
                                Spacer()
                                Text("Expires: \(certification.expirationDate, formatter: dateFormatter)")
                            }
                        }
                        .onDelete { indexSet in
                            viewModel.certifications.remove(atOffsets: indexSet)
                        }
                    }
                }
                
                Button(action: {
                    // Add new skill or certification
                }) {
                    Text("Add Skill/Certification")
                }
                .padding()
            }
            .navigationTitle("Skill Tracker")
        }
    }
}

// MARK: - DateFormatter

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()