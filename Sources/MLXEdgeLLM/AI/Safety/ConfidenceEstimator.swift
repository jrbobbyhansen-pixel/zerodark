import Foundation
import SwiftUI

// MARK: - ConfidenceEstimator

class ConfidenceEstimator: ObservableObject {
    @Published var confidence: Double = 0.0
    @Published var tokenProbabilities: [String: Double] = [:]
    @Published var consistencyScore: Double = 0.0

    func estimateConfidence(response: String, tokens: [String]) {
        // Placeholder for actual confidence estimation logic
        // This should be replaced with actual ML model inference
        confidence = 0.85
        tokenProbabilities = tokens.reduce(into: [:]) { $0[$1] = Double.random(in: 0.0...1.0) }
        consistencyScore = 0.90
    }
}

// MARK: - ConfidenceView

struct ConfidenceView: View {
    @StateObject private var estimator = ConfidenceEstimator()

    var body: some View {
        VStack {
            Text("Confidence: \(String(format: "%.2f", estimator.confidence))")
                .font(.headline)
            
            Text("Consistency Score: \(String(format: "%.2f", estimator.consistencyScore))")
                .font(.subheadline)
            
            List(estimator.tokenProbabilities.sorted(by: { $0.key < $1.key }), id: \.key) { token, probability in
                HStack {
                    Text(token)
                    Spacer()
                    Text("\(String(format: "%.2f", probability))")
                }
            }
            .listStyle(PlainListStyle())
        }
        .padding()
        .onAppear {
            // Simulate fetching a response and tokens
            let response = "Sample response from LLM"
            let tokens = ["token1", "token2", "token3"]
            estimator.estimateConfidence(response: response, tokens: tokens)
        }
    }
}

// MARK: - Preview

struct ConfidenceView_Previews: PreviewProvider {
    static var previews: some View {
        ConfidenceView()
    }
}