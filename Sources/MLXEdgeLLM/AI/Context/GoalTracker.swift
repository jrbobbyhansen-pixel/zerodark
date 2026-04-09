import Foundation
import SwiftUI

// MARK: - GoalTracker

class GoalTracker: ObservableObject {
    @Published var activeGoals: [Goal] = []
    @Published var completedGoals: [Goal] = []
    
    func addGoal(_ goal: Goal) {
        activeGoals.append(goal)
        activeGoals.sort { $0.priority > $1.priority }
    }
    
    func removeGoal(_ goal: Goal) {
        if let index = activeGoals.firstIndex(of: goal) {
            activeGoals.remove(at: index)
        }
    }
    
    func completeGoal(_ goal: Goal) {
        if let index = activeGoals.firstIndex(of: goal) {
            let completedGoal = activeGoals.remove(at: index)
            completedGoals.append(completedGoal)
        }
    }
    
    func switchToGoal(_ goal: Goal) {
        if let index = activeGoals.firstIndex(of: goal) {
            activeGoals.move(from: index, to: 0)
        }
    }
}

// MARK: - Goal

struct Goal: Identifiable, Comparable {
    let id = UUID()
    let description: String
    let priority: Int
    let completionCriteria: () -> Bool
    
    static func < (lhs: Goal, rhs: Goal) -> Bool {
        lhs.priority < rhs.priority
    }
}

// MARK: - GoalTrackerView

struct GoalTrackerView: View {
    @StateObject private var goalTracker = GoalTracker()
    
    var body: some View {
        VStack {
            List(goalTracker.activeGoals) { goal in
                Text(goal.description)
                    .font(.headline)
                    .padding()
            }
            .listStyle(PlainListStyle())
            
            Button("Add Goal") {
                let newGoal = Goal(description: "New Goal", priority: 1, completionCriteria: { false })
                goalTracker.addGoal(newGoal)
            }
            .padding()
        }
        .navigationTitle("Goal Tracker")
    }
}

// MARK: - Preview

struct GoalTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        GoalTrackerView()
    }
}