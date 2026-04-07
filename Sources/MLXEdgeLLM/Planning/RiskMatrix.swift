import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - RiskMatrix

struct RiskMatrix: Identifiable {
    let id = UUID()
    let hazard: String
    let probability: Probability
    let severity: Severity
    let mitigation: String
}

// MARK: - Probability

enum Probability: String, CaseIterable {
    case low
    case medium
    case high
}

// MARK: - Severity

enum Severity: String, CaseIterable {
    case minor
    case moderate
    case critical
}

// MARK: - RiskMatrixViewModel

class RiskMatrixViewModel: ObservableObject {
    @Published var risks: [RiskMatrix] = [
        RiskMatrix(hazard: "Battery Depletion", probability: .medium, severity: .critical, mitigation: "Implement low-power mode and optimize app performance."),
        RiskMatrix(hazard: "Data Loss", probability: .high, severity: .critical, mitigation: "Regularly back up data and implement encryption."),
        RiskMatrix(hazard: "Navigation Error", probability: .medium, severity: .moderate, mitigation: "Use GPS and ARKit for accurate navigation."),
        RiskMatrix(hazard: "Communication Failure", probability: .medium, severity: .moderate, mitigation: "Use redundant communication channels."),
        RiskMatrix(hazard: "Software Glitch", probability: .low, severity: .moderate, mitigation: "Regularly update software and perform QA testing.")
    ]
}

// MARK: - RiskMatrixView

struct RiskMatrixView: View {
    @StateObject private var viewModel = RiskMatrixViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.risks) { risk in
                VStack(alignment: .leading) {
                    Text(risk.hazard)
                        .font(.headline)
                    HStack {
                        Text("Probability: \(risk.probability.rawValue.capitalized)")
                            .font(.subheadline)
                        Text("Severity: \(risk.severity.rawValue.capitalized)")
                            .font(.subheadline)
                    }
                    Text("Mitigation: \(risk.mitigation)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Operational Risk Assessment")
        }
    }
}

// MARK: - Preview

struct RiskMatrixView_Previews: PreviewProvider {
    static var previews: some View {
        RiskMatrixView()
    }
}