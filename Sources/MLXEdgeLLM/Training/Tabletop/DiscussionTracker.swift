import Foundation
import SwiftUI

// MARK: - DiscussionPoint

struct DiscussionPoint: Identifiable {
    let id = UUID()
    let topic: String
    let decision: String
    let concerns: [String]
    let actionItems: [String]
}

// MARK: - DiscussionTrackerViewModel

class DiscussionTrackerViewModel: ObservableObject {
    @Published var discussionPoints: [DiscussionPoint] = []
    @Published var currentTopic: String = ""
    @Published var currentDecision: String = ""
    @Published var currentConcerns: [String] = []
    @Published var currentActionItems: [String] = []

    func addDiscussionPoint() {
        let newPoint = DiscussionPoint(
            topic: currentTopic,
            decision: currentDecision,
            concerns: currentConcerns,
            actionItems: currentActionItems
        )
        discussionPoints.append(newPoint)
        clearCurrentFields()
    }

    func clearCurrentFields() {
        currentTopic = ""
        currentDecision = ""
        currentConcerns = []
        currentActionItems = []
    }
}

// MARK: - DiscussionTrackerView

struct DiscussionTrackerView: View {
    @StateObject private var viewModel = DiscussionTrackerViewModel()

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Discussion Point")) {
                        TextField("Topic", text: $viewModel.currentTopic)
                        TextField("Decision", text: $viewModel.currentDecision)
                    }

                    Section(header: Text("Concerns")) {
                        ForEach(viewModel.currentConcerns.indices, id: \.self) { index in
                            TextField("Concern \(index + 1)", text: Binding(
                                get: { viewModel.currentConcerns[index] },
                                set: { viewModel.currentConcerns[index] = $0 }
                            ))
                        }
                        Button(action: { viewModel.currentConcerns.append("") }) {
                            Text("Add Concern")
                        }
                    }

                    Section(header: Text("Action Items")) {
                        ForEach(viewModel.currentActionItems.indices, id: \.self) { index in
                            TextField("Action Item \(index + 1)", text: Binding(
                                get: { viewModel.currentActionItems[index] },
                                set: { viewModel.currentActionItems[index] = $0 }
                            ))
                        }
                        Button(action: { viewModel.currentActionItems.append("") }) {
                            Text("Add Action Item")
                        }
                    }
                }

                Button(action: viewModel.addDiscussionPoint) {
                    Text("Add Discussion Point")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .navigationTitle("Discussion Tracker")
        }
    }
}

// MARK: - Preview

struct DiscussionTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        DiscussionTrackerView()
    }
}