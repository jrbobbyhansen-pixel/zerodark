import SwiftUI
import Foundation

// MARK: - HotwashGuide

struct HotwashGuide: View {
    @StateObject private var viewModel = HotwashViewModel()
    
    var body: some View {
        VStack {
            Text("Hotwash Facilitator")
                .font(.largeTitle)
                .padding()
            
            Form {
                Section(header: Text("Structured Feedback")) {
                    ForEach(viewModel.feedback, id: \.self) { feedback in
                        Text(feedback)
                    }
                }
                
                Section(header: Text("Action Items")) {
                    ForEach(viewModel.actionItems, id: \.self) { actionItem in
                        Text(actionItem)
                    }
                }
            }
            
            Button(action: {
                viewModel.generateFeedback()
            }) {
                Text("Generate Feedback")
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - HotwashViewModel

class HotwashViewModel: ObservableObject {
    @Published var feedback: [String] = []
    @Published var actionItems: [String] = []
    
    func generateFeedback() {
        // Placeholder logic for generating feedback and action items
        feedback = [
            "Great teamwork during the exercise.",
            "Could improve communication in high-stress situations.",
            "Effective use of available resources."
        ]
        
        actionItems = [
            "Review communication strategies for high-stress scenarios.",
            "Conduct a debrief on resource management.",
            "Plan a follow-up exercise to practice improved communication."
        ]
    }
}

// MARK: - Preview

struct HotwashGuide_Previews: PreviewProvider {
    static var previews: some View {
        HotwashGuide()
    }
}