import Foundation
import SwiftUI

// MARK: - LoadCalculator

class LoadCalculator: ObservableObject {
    @Published var teamMembers: [TeamMember] = []
    @Published var overloadedMembers: [TeamMember] = []
    
    init() {
        // Initial setup or load data
    }
    
    func calculateLoad() {
        overloadedMembers = teamMembers.filter { $0.load > $0.maxLoad }
    }
    
    func suggestRedistribution() -> [RedistributionSuggestion] {
        var suggestions: [RedistributionSuggestion] = []
        
        for overloaded in overloadedMembers {
            let excessWeight = overloaded.load - overloaded.maxLoad
            for member in teamMembers where member != overloaded && member.load < member.maxLoad {
                let possibleReduction = min(excessWeight, member.maxLoad - member.load)
                suggestions.append(RedistributionSuggestion(from: overloaded, to: member, weight: possibleReduction))
                excessWeight -= possibleReduction
                if excessWeight == 0 {
                    break
                }
            }
        }
        
        return suggestions
    }
}

// MARK: - TeamMember

struct TeamMember: Identifiable {
    let id = UUID()
    var name: String
    var load: Double
    var maxLoad: Double
}

// MARK: - RedistributionSuggestion

struct RedistributionSuggestion {
    let from: TeamMember
    let to: TeamMember
    let weight: Double
}

// MARK: - LoadCalculatorView

struct LoadCalculatorView: View {
    @StateObject private var viewModel = LoadCalculator()
    
    var body: some View {
        VStack {
            List(viewModel.teamMembers) { member in
                HStack {
                    Text(member.name)
                    Spacer()
                    Text("\(member.load, specifier: "%.1f") kg")
                    Text("/ \(member.maxLoad, specifier: "%.1f") kg")
                }
                .foregroundColor(member.load > member.maxLoad ? .red : .black)
            }
            
            Button("Calculate Load") {
                viewModel.calculateLoad()
            }
            
            if !viewModel.overloadedMembers.isEmpty {
                Text("Overloaded Members:")
                    .font(.headline)
                
                List(viewModel.overloadedMembers) { member in
                    Text("\(member.name) - \(member.load, specifier: "%.1f") kg")
                }
            }
            
            Button("Suggest Redistribution") {
                let suggestions = viewModel.suggestRedistribution()
                for suggestion in suggestions {
                    print("\(suggestion.from.name) -> \(suggestion.to.name): \(suggestion.weight) kg")
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct LoadCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        LoadCalculatorView()
    }
}