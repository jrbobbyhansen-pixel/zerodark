import Foundation
import SwiftUI

// MARK: - DecisionLogger

class DecisionLogger: ObservableObject {
    @Published var decisions: [Decision] = []
    
    func logDecision(decision: Decision) {
        decisions.append(decision)
    }
}

// MARK: - Decision

struct Decision: Identifiable {
    let id = UUID()
    let timestamp: Date
    let rationale: String
    let alternatives: [String]
    let outcome: String
}

// MARK: - DecisionView

struct DecisionView: View {
    @StateObject private var viewModel = DecisionLogger()
    
    var body: some View {
        NavigationView {
            List(viewModel.decisions) { decision in
                VStack(alignment: .leading) {
                    Text("Decision \(decision.id.uuidString)")
                        .font(.headline)
                    Text("Timestamp: \(decision.timestamp, style: .date)")
                    Text("Rationale: \(decision.rationale)")
                    Text("Alternatives: \(decision.alternatives.joined(separator: ", "))")
                    Text("Outcome: \(decision.outcome)")
                }
                .padding()
            }
            .navigationTitle("Decision Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        let newDecision = Decision(
                            timestamp: Date(),
                            rationale: "Example rationale",
                            alternatives: ["Alternative 1", "Alternative 2"],
                            outcome: "Example outcome"
                        )
                        viewModel.logDecision(decision: newDecision)
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct DecisionView_Previews: PreviewProvider {
    static var previews: some View {
        DecisionView()
    }
}