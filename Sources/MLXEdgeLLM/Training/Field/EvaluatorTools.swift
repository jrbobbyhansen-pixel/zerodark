import SwiftUI
import Foundation

// MARK: - Evaluator Tools

struct EvaluatorToolsView: View {
    @StateObject private var viewModel = EvaluatorToolsViewModel()
    
    var body: some View {
        VStack {
            EvaluationChecklistView(checklist: $viewModel.checklist)
            ScoringRubricView(rubric: $viewModel.rubric)
            RealTimeNotesView(notes: $viewModel.notes)
            SummaryReportsView(reports: viewModel.reports)
        }
        .padding()
        .navigationTitle("Evaluator Tools")
    }
}

// MARK: - View Models

class EvaluatorToolsViewModel: ObservableObject {
    @Published var checklist: [ChecklistItem] = []
    @Published var rubric: [RubricItem] = []
    @Published var notes: String = ""
    @Published var reports: [Report] = []
    
    init() {
        loadChecklist()
        loadRubric()
    }
    
    private func loadChecklist() {
        // Simulate loading checklist items
        checklist = [
            ChecklistItem(title: "Objective Achieved", isCompleted: false),
            ChecklistItem(title: "Safety Protocols Followed", isCompleted: false),
            ChecklistItem(title: "Team Coordination", isCompleted: false)
        ]
    }
    
    private func loadRubric() {
        // Simulate loading rubric items
        rubric = [
            RubricItem(criteria: "Performance", score: 0),
            RubricItem(criteria: "Efficiency", score: 0),
            RubricItem(criteria: "Innovation", score: 0)
        ]
    }
}

// MARK: - Models

struct ChecklistItem: Identifiable {
    let id = UUID()
    var title: String
    var isCompleted: Bool
}

struct RubricItem: Identifiable {
    let id = UUID()
    var criteria: String
    var score: Int
}

struct Report {
    let title: String
    let content: String
}

// MARK: - Subviews

struct EvaluationChecklistView: View {
    @Binding var checklist: [ChecklistItem]
    
    var body: some View {
        Section(header: Text("Evaluation Checklist")) {
            ForEach($checklist) { $item in
                Toggle(item.title, isOn: $item.isCompleted)
            }
        }
    }
}

struct ScoringRubricView: View {
    @Binding var rubric: [RubricItem]
    
    var body: some View {
        Section(header: Text("Scoring Rubric")) {
            ForEach($rubric) { $item in
                HStack {
                    Text(item.criteria)
                    Spacer()
                    Stepper("\(item.score)", value: Binding(
                        get: { item.score },
                        set: { item.score = $0.clamped(to: 0...10) }
                    ))
                }
            }
        }
    }
}

struct RealTimeNotesView: View {
    @Binding var notes: String
    
    var body: some View {
        Section(header: Text("Real-Time Notes")) {
            TextEditor(text: $notes)
                .frame(height: 100)
        }
    }
}

struct SummaryReportsView: View {
    let reports: [Report]
    
    var body: some View {
        Section(header: Text("Summary Reports")) {
            ForEach(reports) { report in
                VStack(alignment: .leading) {
                    Text(report.title)
                        .font(.headline)
                    Text(report.content)
                        .font(.subheadline)
                }
            }
        }
    }
}