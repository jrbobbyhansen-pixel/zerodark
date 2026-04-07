import Foundation
import SwiftUI

// MARK: - ToolFeedback

class ToolFeedback: ObservableObject {
    @Published var toolPerformance: [String: ToolPerformance] = [:]
    
    func recordExecutionResult(toolName: String, success: Bool) {
        if var performance = toolPerformance[toolName] {
            performance.totalExecutions += 1
            if success {
                performance.successCount += 1
            }
            toolPerformance[toolName] = performance
        } else {
            toolPerformance[toolName] = ToolPerformance(totalExecutions: 1, successCount: success ? 1 : 0)
        }
    }
    
    func userCorrection(toolName: String, success: Bool) {
        if var performance = toolPerformance[toolName] {
            performance.userCorrected = true
            performance.successCount = success ? 1 : 0
            toolPerformance[toolName] = performance
        }
    }
}

// MARK: - ToolPerformance

struct ToolPerformance: Codable {
    var totalExecutions: Int
    var successCount: Int
    var userCorrected: Bool = false
    
    var successRate: Double {
        guard totalExecutions > 0 else { return 0.0 }
        return Double(successCount) / Double(totalExecutions)
    }
}

// MARK: - ToolFeedbackView

struct ToolFeedbackView: View {
    @StateObject private var feedback = ToolFeedback()
    
    var body: some View {
        List {
            ForEach(Array(feedback.toolPerformance.keys), id: \.self) { toolName in
                ToolPerformanceRow(toolName: toolName, performance: feedback.toolPerformance[toolName]!)
            }
        }
        .navigationTitle("Tool Feedback")
    }
}

// MARK: - ToolPerformanceRow

struct ToolPerformanceRow: View {
    let toolName: String
    let performance: ToolPerformance
    
    var body: some View {
        HStack {
            Text(toolName)
            Spacer()
            Text("\(performance.successRate, specifier: "%.2f")")
                .foregroundColor(performance.successRate >= 0.75 ? .green : .red)
        }
        .padding()
        .background(performance.userCorrected ? Color.yellow.opacity(0.3) : Color.clear)
    }
}

// MARK: - Preview

struct ToolFeedbackView_Previews: PreviewProvider {
    static var previews: some View {
        ToolFeedbackView()
    }
}