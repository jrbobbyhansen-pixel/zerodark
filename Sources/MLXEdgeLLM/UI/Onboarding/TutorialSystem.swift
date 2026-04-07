import SwiftUI
import Foundation

// MARK: - TutorialSystem

class TutorialSystem: ObservableObject {
    @Published var currentStep: Int = 0
    @Published var isCompleted: Bool = false
    @Published var steps: [TutorialStep] = []
    
    init(steps: [TutorialStep]) {
        self.steps = steps
    }
    
    func nextStep() {
        if currentStep < steps.count - 1 {
            currentStep += 1
        } else {
            isCompleted = true
        }
    }
    
    func previousStep() {
        if currentStep > 0 {
            currentStep -= 1
        }
    }
    
    func reset() {
        currentStep = 0
        isCompleted = false
    }
}

// MARK: - TutorialStep

struct TutorialStep {
    let title: String
    let description: String
    let image: String?
    let action: () -> Void
}

// MARK: - TutorialView

struct TutorialView: View {
    @StateObject private var tutorialSystem: TutorialSystem
    
    init(steps: [TutorialStep]) {
        _tutorialSystem = StateObject(wrappedValue: TutorialSystem(steps: steps))
    }
    
    var body: some View {
        VStack {
            if tutorialSystem.isCompleted {
                CompletionView()
            } else {
                StepView(step: tutorialSystem.steps[tutorialSystem.currentStep])
                ControlsView()
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func StepView(step: TutorialStep) -> some View {
        VStack(alignment: .leading) {
            Text(step.title)
                .font(.headline)
                .padding(.bottom, 5)
            Text(step.description)
                .font(.body)
            if let image = step.image {
                Image(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, 10)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 5)
    }
    
    @ViewBuilder
    private func ControlsView() -> some View {
        HStack {
            Button(action: tutorialSystem.previousStep) {
                Text("Previous")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(tutorialSystem.currentStep == 0)
            
            Spacer()
            
            Button(action: {
                tutorialSystem.steps[tutorialSystem.currentStep].action()
                tutorialSystem.nextStep()
            }) {
                Text(tutorialSystem.currentStep == tutorialSystem.steps.count - 1 ? "Finish" : "Next")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }
    
    @ViewBuilder
    private func CompletionView() -> some View {
        VStack {
            Text("Congratulations!")
                .font(.largeTitle)
                .padding(.bottom, 20)
            Text("You have completed the tutorial.")
                .font(.body)
                .padding(.bottom, 30)
            Button(action: tutorialSystem.reset) {
                Text("Restart Tutorial")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

// MARK: - Preview

struct TutorialView_Previews: PreviewProvider {
    static var previews: some View {
        TutorialView(steps: [
            TutorialStep(title: "Step 1", description: "Welcome to ZeroDark!", image: "step1", action: {}),
            TutorialStep(title: "Step 2", description: "This is step 2.", image: "step2", action: {}),
            TutorialStep(title: "Step 3", description: "Final step!", image: "step3", action: {})
        ])
    }
}