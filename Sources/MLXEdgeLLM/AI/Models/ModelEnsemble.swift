import Foundation
import SwiftUI

// MARK: - ModelEnsemble

class ModelEnsemble: ObservableObject {
    @Published var models: [Model] = []
    @Published var consensusOutput: String = ""

    func addModel(_ model: Model) {
        models.append(model)
    }

    func removeModel(_ model: Model) {
        models.removeAll { $0.id == model.id }
    }

    func evaluateModels(input: String) async {
        let results = await withTaskGroup(of: String.self) { group in
            for model in models {
                group.addTask {
                    await model.evaluate(input: input)
                }
            }
            return await group.reduce(into: [String]()) { $0.append($1) }
        }

        consensusOutput = determineConsensus(from: results)
    }

    private func determineConsensus(from results: [String]) -> String {
        // Simple majority voting
        let frequencyDict = Dictionary(grouping: results) { $0 }
        let mostFrequent = frequencyDict.max { a, b in a.value.count < b.value.count }
        return mostFrequent?.key ?? ""
    }
}

// MARK: - Model

class Model: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let evaluate: (String) async -> String

    init(name: String, evaluate: @escaping (String) async -> String) {
        self.name = name
        self.evaluate = evaluate
    }
}

// MARK: - Example Usage

struct ModelEnsembleView: View {
    @StateObject private var ensemble = ModelEnsemble()

    var body: some View {
        VStack {
            Text("Consensus Output: \(ensemble.consensusOutput)")
                .padding()

            Button("Evaluate Models") {
                Task {
                    await ensemble.evaluateModels(input: "Sample Input")
                }
            }
            .padding()

            ForEach(ensemble.models) { model in
                Text("Model: \(model.name)")
            }
            .padding()
        }
        .onAppear {
            ensemble.addModel(Model(name: "Model A") { input in
                return "Output from Model A"
            })
            ensemble.addModel(Model(name: "Model B") { input in
                return "Output from Model B"
            })
            ensemble.addModel(Model(name: "Model C") { input in
                return "Output from Model C"
            })
        }
    }
}

struct ModelEnsembleView_Previews: PreviewProvider {
    static var previews: some View {
        ModelEnsembleView()
    }
}