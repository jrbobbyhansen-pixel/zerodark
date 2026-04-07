import SwiftUI
import Foundation

// MARK: - CompetencyTest

struct CompetencyTest {
    let questions: [Question]
    var currentQuestionIndex: Int = 0
    var selectedAnswer: String? = nil
    var score: Int = 0
    
    mutating func selectAnswer(_ answer: String) {
        selectedAnswer = answer
    }
    
    mutating func nextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
        }
    }
    
    mutating func previousQuestion() {
        if currentQuestionIndex > 0 {
            currentQuestionIndex -= 1
            selectedAnswer = nil
        }
    }
    
    mutating func submitTest() {
        for (index, question) in questions.enumerated() {
            if question.correctAnswer == selectedAnswer {
                score += 1
            }
        }
    }
}

// MARK: - Question

struct Question {
    let text: String
    let options: [String]
    let correctAnswer: String
}

// MARK: - CompetencyTestView

struct CompetencyTestView: View {
    @StateObject private var viewModel = CompetencyTestViewModel()
    
    var body: some View {
        VStack {
            Text(viewModel.currentQuestion.text)
                .font(.headline)
                .padding()
            
            ForEach(viewModel.currentQuestion.options, id: \.self) { option in
                Button(action: {
                    viewModel.selectAnswer(option)
                }) {
                    Text(option)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(viewModel.selectedAnswer == option ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(viewModel.selectedAnswer == option ? Color.white : Color.black)
                        .cornerRadius(8)
                }
            }
            
            HStack {
                Button(action: {
                    viewModel.previousQuestion()
                }) {
                    Text("Previous")
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.nextQuestion()
                }) {
                    Text("Next")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            
            Button(action: {
                viewModel.submitTest()
            }) {
                Text("Submit Test")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
            
            Text("Score: \(viewModel.score)/\(viewModel.test.questions.count)")
                .font(.subheadline)
                .padding()
        }
        .padding()
    }
}

// MARK: - CompetencyTestViewModel

class CompetencyTestViewModel: ObservableObject {
    @Published var test: CompetencyTest
    @Published var currentQuestion: Question
    @Published var selectedAnswer: String? = nil
    @Published var score: Int = 0
    
    init() {
        let questions = [
            Question(text: "What is the capital of France?", options: ["Paris", "London", "Berlin", "Madrid"], correctAnswer: "Paris"),
            Question(text: "What is 2 + 2?", options: ["3", "4", "5", "6"], correctAnswer: "4"),
            Question(text: "What is the largest planet in our solar system?", options: ["Earth", "Mars", "Jupiter", "Saturn"], correctAnswer: "Jupiter")
        ]
        test = CompetencyTest(questions: questions)
        currentQuestion = questions.first!
    }
    
    func selectAnswer(_ answer: String) {
        test.selectAnswer(answer)
        selectedAnswer = answer
    }
    
    func nextQuestion() {
        test.nextQuestion()
        currentQuestion = test.questions[test.currentQuestionIndex]
        selectedAnswer = nil
    }
    
    func previousQuestion() {
        test.previousQuestion()
        currentQuestion = test.questions[test.currentQuestionIndex]
        selectedAnswer = nil
    }
    
    func submitTest() {
        test.submitTest()
        score = test.score
    }
}