import Foundation
import SwiftUI

// MARK: - Skill Decay Monitor

class SkillDecayMonitor: ObservableObject {
    @Published var skills: [Skill] = []
    @Published var refresherSkills: [Skill] = []
    
    private let decayRate: TimeInterval = 3600 * 24 // 1 day
    private let perishableThreshold: TimeInterval = 3600 * 24 * 7 // 7 days
    
    init() {
        loadSkills()
        scheduleDecayCheck()
    }
    
    func loadSkills() {
        // Simulate loading skills from a persistent storage
        skills = [
            Skill(name: "Marksmanship", lastPracticed: Date.now - 3600 * 24 * 5), // 5 days ago
            Skill(name: "First Aid", lastPracticed: Date.now - 3600 * 24 * 10), // 10 days ago
            Skill(name: "Navigation", lastPracticed: Date.now - 3600 * 24 * 2) // 2 days ago
        ]
        updateRefresherSkills()
    }
    
    func scheduleDecayCheck() {
        Timer.scheduledTimer(withTimeInterval: decayRate, repeats: true) { [weak self] _ in
            self?.updateRefresherSkills()
        }
    }
    
    func updateRefresherSkills() {
        refresherSkills = skills.filter { skill in
            let timeSinceLastPractice = Date.now.timeIntervalSince(skill.lastPracticed)
            return timeSinceLastPractice > perishableThreshold
        }
    }
    
    func practiceSkill(_ skill: Skill) {
        if let index = skills.firstIndex(of: skill) {
            skills[index].lastPracticed = Date.now
            updateRefresherSkills()
        }
    }
}

// MARK: - Skill Model

struct Skill: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var lastPracticed: Date
}

// MARK: - Skill Decay View

struct SkillDecayView: View {
    @StateObject private var skillMonitor = SkillDecayMonitor()
    
    var body: some View {
        VStack {
            Text("Refresher Skills Needed")
                .font(.headline)
            
            List(skillMonitor.refresherSkills) { skill in
                HStack {
                    Text(skill.name)
                    Spacer()
                    Button("Practice") {
                        skillMonitor.practiceSkill(skill)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct SkillDecayView_Previews: PreviewProvider {
    static var previews: some View {
        SkillDecayView()
    }
}