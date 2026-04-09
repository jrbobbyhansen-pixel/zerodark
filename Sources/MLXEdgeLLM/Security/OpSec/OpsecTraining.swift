import SwiftUI
import Foundation

// MARK: - OpsecTrainingView

struct OpsecTrainingView: View {
    @StateObject private var viewModel = OpsecTrainingViewModel()
    
    var body: some View {
        VStack {
            Text("OPSEC Training")
                .font(.largeTitle)
                .padding()
            
            ScrollView {
                ForEach(viewModel.scenarios, id: \.id) { scenario in
                    ScenarioView(scenario: scenario)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.vertical, 5)
                }
            }
            .padding()
            
            Button(action: {
                viewModel.startTraining()
            }) {
                Text("Start Training")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .onAppear {
            viewModel.loadScenarios()
        }
    }
}

// MARK: - ScenarioView

struct ScenarioView: View {
    let scenario: Scenario
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(scenario.title)
                .font(.title2)
            
            Text(scenario.description)
                .font(.body)
                .foregroundColor(.secondary)
            
            ForEach(scenario.mistakes, id: \.self) { mistake in
                Text("- \(mistake)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            ForEach(scenario.bestPractices, id: \.self) { bestPractice in
                Text("- \(bestPractice)")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - OpsecTrainingViewModel

class OpsecTrainingViewModel: ObservableObject {
    @Published var scenarios: [Scenario] = []
    
    func loadScenarios() {
        // Load scenarios from a data source
        scenarios = [
            Scenario(id: 1, title: "Scenario 1", description: "Description of scenario 1", mistakes: ["Mistake 1", "Mistake 2"], bestPractices: ["Best Practice 1", "Best Practice 2"]),
            Scenario(id: 2, title: "Scenario 2", description: "Description of scenario 2", mistakes: ["Mistake 3", "Mistake 4"], bestPractices: ["Best Practice 3", "Best Practice 4"])
        ]
    }
    
    func startTraining() {
        // Start the training process
        print("Training started")
    }
}

// MARK: - Scenario

struct Scenario: Identifiable {
    let id: Int
    let title: String
    let description: String
    let mistakes: [String]
    let bestPractices: [String]
}