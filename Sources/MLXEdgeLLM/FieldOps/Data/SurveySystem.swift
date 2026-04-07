import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Survey System

struct Survey {
    let id: UUID
    let title: String
    let questions: [Question]
}

struct Question {
    let id: UUID
    let text: String
    let type: QuestionType
    let skipLogic: SkipLogic?
}

enum QuestionType {
    case singleChoice([String])
    case multipleChoice([String])
    case text
    case number
}

struct SkipLogic {
    let condition: String
    let nextQuestionID: UUID
}

class SurveyViewModel: ObservableObject {
    @Published var surveys: [Survey] = []
    @Published var currentSurvey: Survey?
    @Published var currentQuestionIndex: Int = 0
    @Published var answers: [UUID: Any] = [:]
    
    func loadSurveys() {
        // Load surveys from local storage or network
        surveys = [
            Survey(id: UUID(), title: "Field Survey", questions: [
                Question(id: UUID(), text: "What is your location?", type: .text, skipLogic: nil),
                Question(id: UUID(), text: "How many people are in the area?", type: .number, skipLogic: nil)
            ])
        ]
    }
    
    func nextQuestion() {
        guard let currentSurvey = currentSurvey else { return }
        currentQuestionIndex += 1
        if currentQuestionIndex < currentSurvey.questions.count {
            applySkipLogic()
        } else {
            submitSurvey()
        }
    }
    
    func applySkipLogic() {
        guard let currentSurvey = currentSurvey else { return }
        let currentQuestion = currentSurvey.questions[currentQuestionIndex]
        if let skipLogic = currentQuestion.skipLogic {
            // Implement skip logic based on condition
            // For example, if condition is "answer == 'yes'", check if the answer is "yes"
            // and if so, set currentQuestionIndex to the index of the nextQuestionID
        }
    }
    
    func submitSurvey() {
        // Submit survey data to server or save locally
        print("Survey submitted with answers: \(answers)")
    }
}

// MARK: - SwiftUI Views

struct SurveyView: View {
    @StateObject private var viewModel = SurveyViewModel()
    
    var body: some View {
        VStack {
            if let currentSurvey = viewModel.currentSurvey {
                Text(currentSurvey.title)
                    .font(.largeTitle)
                    .padding()
                
                if viewModel.currentQuestionIndex < currentSurvey.questions.count {
                    let currentQuestion = currentSurvey.questions[viewModel.currentQuestionIndex]
                    QuestionView(question: currentQuestion, answers: $viewModel.answers)
                }
                
                Button(action: {
                    viewModel.nextQuestion()
                }) {
                    Text("Next")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(viewModel.currentQuestionIndex >= currentSurvey.questions.count)
            } else {
                Text("No surveys available")
            }
        }
        .onAppear {
            viewModel.loadSurveys()
            viewModel.currentSurvey = viewModel.surveys.first
        }
    }
}

struct QuestionView: View {
    let question: Question
    @Binding var answers: [UUID: Any]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(question.text)
                .font(.headline)
            
            switch question.type {
            case .singleChoice(let options):
                Picker("Choose an option", selection: Binding(
                    get: { answers[question.id] as? String ?? "" },
                    set: { answers[question.id] = $0 }
                )) {
                    ForEach(options, id: \.self) { option in
                        Text(option)
                    }
                }
                .pickerStyle(RadioGroupPickerStyle())
            
            case .multipleChoice(let options):
                ForEach(options, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: { (answers[question.id] as? [String])?.contains(option) ?? false },
                        set: { newValue in
                            if newValue {
                                answers[question.id] = (answers[question.id] as? [String] ?? []) + [option]
                            } else {
                                answers[question.id] = (answers[question.id] as? [String] ?? []).filter { $0 != option }
                            }
                        }
                    ))
                }
            
            case .text:
                TextField("Enter your answer", text: Binding(
                    get: { answers[question.id] as? String ?? "" },
                    set: { answers[question.id] = $0 }
                ))
            
            case .number:
                TextField("Enter a number", value: Binding(
                    get: { answers[question.id] as? Int ?? 0 },
                    set: { answers[question.id] = $0 }
                ), formatter: NumberFormatter())
            }
        }
    }
}

// MARK: - Preview

struct SurveyView_Previews: PreviewProvider {
    static var previews: some View {
        SurveyView()
    }
}