import Foundation
import SwiftUI

// MARK: - TeamSkills

struct TeamSkills {
    var members: [TeamMember]
    
    func aggregateSkills() -> [Skill: Int] {
        var skillCounts: [Skill: Int] = [:]
        
        for member in members {
            for skill in member.skills {
                skillCounts[skill, default: 0] += 1
            }
        }
        
        return skillCounts
    }
    
    func identifyGaps() -> [Skill] {
        let skillCounts = aggregateSkills()
        let requiredSkills = Skill.allCases
        var gaps: [Skill] = []
        
        for skill in requiredSkills {
            if skillCounts[skill] == nil || skillCounts[skill]! < 1 {
                gaps.append(skill)
            }
        }
        
        return gaps
    }
    
    func identifyRedundancies() -> [Skill] {
        let skillCounts = aggregateSkills()
        var redundancies: [Skill] = []
        
        for (skill, count) in skillCounts {
            if count > 1 {
                redundancies.append(skill)
            }
        }
        
        return redundancies
    }
    
    func trainingPriorityRecommendations() -> [Skill] {
        let gaps = identifyGaps()
        let redundancies = identifyRedundancies()
        
        // Prioritize gaps over redundancies
        return gaps + redundancies
    }
    
    func coverageAnalysis() -> String {
        let skillCounts = aggregateSkills()
        let requiredSkills = Skill.allCases
        var coverage: [String] = []
        
        for skill in requiredSkills {
            let count = skillCounts[skill] ?? 0
            coverage.append("\(skill): \(count)")
        }
        
        return coverage.joined(separator: ", ")
    }
}

// MARK: - TeamMember

struct TeamMember {
    let name: String
    let skills: [Skill]
}

// MARK: - Skill

enum Skill: String, CaseIterable {
    case swift
    case uiKit
    case swiftUI
    case coreLocation
    case arKit
    case avFoundation
    case machineLearning
    case networking
    case security
    case design
}

// MARK: - TeamSkillsViewModel

class TeamSkillsViewModel: ObservableObject {
    @Published var teamSkills: TeamSkills
    
    init(teamSkills: TeamSkills) {
        self.teamSkills = teamSkills
    }
    
    func aggregateSkills() -> [Skill: Int] {
        teamSkills.aggregateSkills()
    }
    
    func identifyGaps() -> [Skill] {
        teamSkills.identifyGaps()
    }
    
    func identifyRedundancies() -> [Skill] {
        teamSkills.identifyRedundancies()
    }
    
    func trainingPriorityRecommendations() -> [Skill] {
        teamSkills.trainingPriorityRecommendations()
    }
    
    func coverageAnalysis() -> String {
        teamSkills.coverageAnalysis()
    }
}

// MARK: - TeamSkillsView

struct TeamSkillsView: View {
    @StateObject private var viewModel: TeamSkillsViewModel
    
    init(teamSkills: TeamSkills) {
        _viewModel = StateObject(wrappedValue: TeamSkillsViewModel(teamSkills: teamSkills))
    }
    
    var body: some View {
        VStack {
            Text("Team Skills")
                .font(.largeTitle)
                .padding()
            
            Section(header: Text("Aggregate Skills")) {
                ForEach(viewModel.aggregateSkills().sorted(by: { $0.key.rawValue < $1.key.rawValue }), id: \.key) { skill, count in
                    HStack {
                        Text("\(skill.rawValue): \(count)")
                    }
                }
            }
            
            Section(header: Text("Gaps")) {
                ForEach(viewModel.identifyGaps(), id: \.self) { skill in
                    HStack {
                        Text(skill.rawValue)
                    }
                }
            }
            
            Section(header: Text("Redundancies")) {
                ForEach(viewModel.identifyRedundancies(), id: \.self) { skill in
                    HStack {
                        Text(skill.rawValue)
                    }
                }
            }
            
            Section(header: Text("Training Priority Recommendations")) {
                ForEach(viewModel.trainingPriorityRecommendations(), id: \.self) { skill in
                    HStack {
                        Text(skill.rawValue)
                    }
                }
            }
            
            Section(header: Text("Coverage Analysis")) {
                Text(viewModel.coverageAnalysis())
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct TeamSkillsView_Previews: PreviewProvider {
    static var previews: some View {
        let teamSkills = TeamSkills(members: [
            TeamMember(name: "Alice", skills: [.swift, .swiftUI, .coreLocation]),
            TeamMember(name: "Bob", skills: [.swift, .uiKit, .arKit]),
            TeamMember(name: "Charlie", skills: [.swift, .avFoundation, .machineLearning])
        ])
        
        TeamSkillsView(teamSkills: teamSkills)
    }
}