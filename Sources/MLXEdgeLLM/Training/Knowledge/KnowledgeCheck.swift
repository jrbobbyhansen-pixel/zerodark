import SwiftUI
import Foundation

struct KnowledgeCheckView: View {
    @StateObject private var viewModel = KnowledgeCheckViewModel()
    
    var body: some View {
        VStack {
            Text("Knowledge Check")
                .font(.largeTitle)
                .padding()
            
            ForEach(viewModel.questions, id: \.id) { question in
                VStack(alignment: .leading) {
                    Text(question.text)
                        .font(.headline)
                    
                    ForEach(question.options, id: \.self) { option in
                        Button(action: {
                            viewModel.selectAnswer(question: question, answer: option)
                        }) {
                            Text(option)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(viewModel.selectedAnswer(for: question) == option ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(viewModel.selectedAnswer(for: question) == option ? .white : .black)
                                .cornerRadius(8)
                        }
                    }
                    
                    if let feedback = viewModel.feedback(for: question) {
                        Text(feedback)
                            .font(.caption)
                            .foregroundColor(viewModel.isCorrect(for: question) ? .green : .red)
                    }
                }
                .padding()
            }
            
            Button(action: {
                viewModel.submitAnswers()
            }) {
                Text("Submit")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(!viewModel.canSubmit)
            .padding()
        }
        .padding()
    }
}

class KnowledgeCheckViewModel: ObservableObject {
    @Published var questions: [Question] = [
        Question(id: 1, text: "What is the primary function of ARKit?", options: ["To capture audio", "To render 3D models", "To track user location", "To process images"], correctAnswer: "To render 3D models"),
        Question(id: 2, text: "Which SwiftUI modifier is used to apply a background color?", options: ["background(Color.blue)", "backgroundColor(Color.blue)", "bg(Color.blue)", "color(Color.blue)"], correctAnswer: "background(Color.blue)")
    ]
    
    @Published var selectedAnswers: [Int: String] = [:]
    
    var canSubmit: Bool {
        questions.allSatisfy { selectedAnswers[$0.id] != nil }
    }
    
    func selectAnswer(question: Question, answer: String) {
        selectedAnswers[question.id] = answer
    }
    
    func selectedAnswer(for question: Question) -> String? {
        selectedAnswers[question.id]
    }
    
    func feedback(for question: Question) -> String? {
        if let selectedAnswer = selectedAnswers[question.id] {
            return selectedAnswer == question.correctAnswer ? "Correct!" : "Incorrect. Try again."
        }
        return nil
    }
    
    func isCorrect(for question: Question) -> Bool {
        selectedAnswers[question.id] == question.correctAnswer
    }
    
    func submitAnswers() {
        // Handle submission logic here
    }
}

struct Question: Identifiable {
    let id: Int
    let text: String
    let options: [String]
    let correctAnswer: String
}