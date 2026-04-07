import SwiftUI
import Foundation
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ProcedureTrainer

struct ProcedureTrainer: View {
    @StateObject private var viewModel = ProcedureTrainerViewModel()
    
    var body: some View {
        VStack {
            Text("Procedure Trainer")
                .font(.largeTitle)
                .padding()
            
            Text(viewModel.currentStep.description)
                .padding()
            
            Button(action: viewModel.nextStep) {
                Text("Next Step")
            }
            .disabled(!viewModel.hasNextStep)
            .padding()
            
            Button(action: viewModel.verifyStep) {
                Text("Verify Step")
            }
            .disabled(!viewModel.canVerifyStep)
            .padding()
            
            Text("Errors: \(viewModel.errorCount)")
                .foregroundColor(.red)
                .padding()
        }
        .padding()
    }
}

// MARK: - ProcedureTrainerViewModel

class ProcedureTrainerViewModel: ObservableObject {
    @Published private(set) var currentStep: TrainingStep
    @Published private(set) var hasNextStep: Bool
    @Published private(set) var canVerifyStep: Bool
    @Published private(set) var errorCount: Int
    
    private let procedure: [TrainingStep]
    private var stepIndex: Int
    
    init(procedure: [TrainingStep] = []) {
        self.procedure = procedure
        self.stepIndex = 0
        self.currentStep = procedure.first ?? TrainingStep(description: "No steps available")
        self.hasNextStep = procedure.count > 1
        self.canVerifyStep = false
        self.errorCount = 0
    }
    
    func nextStep() {
        if stepIndex < procedure.count - 1 {
            stepIndex += 1
            currentStep = procedure[stepIndex]
            hasNextStep = stepIndex < procedure.count - 1
            canVerifyStep = true
        }
    }
    
    func verifyStep() {
        if currentStep.isCorrect {
            canVerifyStep = false
        } else {
            errorCount += 1
        }
    }
}

// MARK: - TrainingStep

struct TrainingStep {
    let description: String
    let isCorrect: Bool
    
    init(description: String, isCorrect: Bool = false) {
        self.description = description
        self.isCorrect = isCorrect
    }
}