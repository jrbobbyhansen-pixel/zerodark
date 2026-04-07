import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ObjectiveManager

class ObjectiveManager: ObservableObject {
    @Published var objectives: [Objective] = []
    @Published var currentObjective: Objective?
    
    func addObjective(_ objective: Objective) {
        objectives.append(objective)
        objectives.sort { $0.priority < $1.priority }
        updateCurrentObjective()
    }
    
    func removeObjective(_ objective: Objective) {
        objectives.removeAll { $0.id == objective.id }
        updateCurrentObjective()
    }
    
    func updateObjective(_ objective: Objective) {
        if let index = objectives.firstIndex(where: { $0.id == objective.id }) {
            objectives[index] = objective
            objectives.sort { $0.priority < $1.priority }
            updateCurrentObjective()
        }
    }
    
    private func updateCurrentObjective() {
        currentObjective = objectives.first
    }
}

// MARK: - Objective

struct Objective: Identifiable, Comparable {
    let id = UUID()
    var title: String
    var priority: Int
    var completionCriteria: String
    var dependencies: [Objective]
    var progress: Double
    
    static func < (lhs: Objective, rhs: Objective) -> Bool {
        lhs.priority < rhs.priority
    }
}

// MARK: - ObjectiveView

struct ObjectiveView: View {
    @StateObject private var viewModel = ObjectiveManager()
    
    var body: some View {
        VStack {
            if let currentObjective = viewModel.currentObjective {
                ObjectiveDetailView(objective: currentObjective)
            } else {
                Text("No objectives available")
            }
        }
        .navigationTitle("Mission Objectives")
        .toolbar {
            Button(action: {
                let newObjective = Objective(title: "New Objective", priority: 1, completionCriteria: "Complete task", dependencies: [], progress: 0.0)
                viewModel.addObjective(newObjective)
            }) {
                Label("Add Objective", systemImage: "plus")
            }
        }
    }
}

// MARK: - ObjectiveDetailView

struct ObjectiveDetailView: View {
    let objective: Objective
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(objective.title)
                .font(.headline)
            
            Text("Priority: \(objective.priority)")
                .font(.subheadline)
            
            Text("Completion Criteria: \(objective.completionCriteria)")
                .font(.subheadline)
            
            Text("Dependencies: \(objective.dependencies.map { $0.title }.joined(separator: ", "))")
                .font(.subheadline)
            
            ProgressView(value: objective.progress)
                .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct ObjectiveView_Previews: PreviewProvider {
    static var previews: some View {
        ObjectiveView()
    }
}