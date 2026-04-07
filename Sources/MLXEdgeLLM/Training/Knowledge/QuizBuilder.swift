import Foundation
import SwiftUI

// MARK: - QuizBuilder

struct QuizBuilder {
    var questions: [Question] = []
    
    mutating func addQuestion(_ question: Question) {
        questions.append(question)
    }
    
    func randomizeQuestions() -> [Question] {
        return questions.shuffled()
    }
}

// MARK: - Question

enum QuestionType {
    case multipleChoice
    case trueFalse
    case matching
}

struct Question {
    let id: UUID
    let text: String
    let type: QuestionType
    let options: [String]
    let correctAnswer: String
}

// MARK: - QuizViewModel

class QuizViewModel: ObservableObject {
    @Published var quizBuilder = QuizBuilder()
    @Published var currentQuestionIndex = 0
    @Published var selectedAnswer: String?
    @Published var isCorrect = false
    
    var currentQuestion: Question? {
        quizBuilder.questions.indices.contains(currentQuestionIndex) ? quizBuilder.questions[currentQuestionIndex] : nil
    }
    
    func selectAnswer(_ answer: String) {
        selectedAnswer = answer
        isCorrect = answer == currentQuestion?.correctAnswer
    }
    
    func nextQuestion() {
        if currentQuestionIndex < quizBuilder.questions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
            isCorrect = false
        }
    }
    
    func previousQuestion() {
        if currentQuestionIndex > 0 {
            currentQuestionIndex -= 1
            selectedAnswer = nil
            isCorrect = false
        }
    }
    
    func randomizeQuestions() {
        quizBuilder.questions = quizBuilder.randomizeQuestions()
        currentQuestionIndex = 0
        selectedAnswer = nil
        isCorrect = false
    }
}

// MARK: - QuizView

struct QuizView: View {
    @StateObject private var viewModel = QuizViewModel()
    
    var body: some View {
        VStack {
            if let currentQuestion = viewModel.currentQuestion {
                Text(currentQuestion.text)
                    .font(.headline)
                    .padding()
                
                VStack {
                    ForEach(currentQuestion.options, id: \.self) { option in
                        Button(action: {
                            viewModel.selectAnswer(option)
                        }) {
                            HStack {
                                Text(option)
                                Spacer()
                                if viewModel.selectedAnswer == option {
                                    Image(systemName: viewModel.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(viewModel.isCorrect ? .green : .red)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                HStack {
                    Button(action: viewModel.previousQuestion) {
                        Text("Previous")
                    }
                    .disabled(viewModel.currentQuestionIndex == 0)
                    
                    Spacer()
                    
                    Button(action: viewModel.nextQuestion) {
                        Text("Next")
                    }
                    .disabled(viewModel.currentQuestionIndex == viewModel.quizBuilder.questions.count - 1)
                }
                .padding()
            } else {
                Text("No questions available")
            }
        }
        .navigationTitle("Quiz")
    }
}

// MARK: - Preview

struct QuizView_Previews: PreviewProvider {
    static var previews: some View {
        QuizView()
            .environmentObject(QuizViewModel())
    }
}