import Foundation
import SwiftUI

// MARK: - FewShotManager

class FewShotManager: ObservableObject {
    @Published private(set) var examples: [FewShotExample] = []
    
    func addExample(_ example: FewShotExample) {
        examples.append(example)
        examples.sort { $0.querySimilarity > $1.querySimilarity }
    }
    
    func removeExample(at index: Int) {
        examples.remove(at: index)
    }
    
    func selectExample(for query: String) -> FewShotExample? {
        examples.first { $0.querySimilarity > 0.5 }
    }
}

// MARK: - FewShotExample

struct FewShotExample: Identifiable {
    let id = UUID()
    let query: String
    let response: String
    let querySimilarity: Double
}

// MARK: - FewShotExampleView

struct FewShotExampleView: View {
    @StateObject private var manager = FewShotManager()
    
    var body: some View {
        VStack {
            List(manager.examples) { example in
                VStack(alignment: .leading) {
                    Text(example.query)
                        .font(.headline)
                    Text(example.response)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { manager.removeExample(at: $0) }
            }
            
            Button(action: {
                let newExample = FewShotExample(query: "Example Query", response: "Example Response", querySimilarity: 0.8)
                manager.addExample(newExample)
            }) {
                Text("Add Example")
            }
            .padding()
        }
        .navigationTitle("Few-Shot Examples")
    }
}

// MARK: - Preview

struct FewShotExampleView_Previews: PreviewProvider {
    static var previews: some View {
        FewShotExampleView()
    }
}