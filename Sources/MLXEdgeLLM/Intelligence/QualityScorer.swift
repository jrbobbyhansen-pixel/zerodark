import Foundation
import NaturalLanguage

// MARK: - Quality Scorer

/// Scores response quality and learns from feedback
@MainActor
public final class QualityScorer: ObservableObject {
    
    public static let shared = QualityScorer()
    
    // MARK: - Quality Dimensions
    
    public struct QualityScore {
        public let overall: Float
        public let relevance: Float
        public let coherence: Float
        public let completeness: Float
        public let accuracy: Float  // Based on historical feedback
        public let helpfulness: Float
        
        public var summary: String {
            let percentage = Int(overall * 100)
            let grade: String
            switch overall {
            case 0.9...1.0: grade = "A+"
            case 0.8..<0.9: grade = "A"
            case 0.7..<0.8: grade = "B"
            case 0.6..<0.7: grade = "C"
            case 0.5..<0.6: grade = "D"
            default: grade = "F"
            }
            return "\(grade) (\(percentage)%)"
        }
        
        public var detailedBreakdown: String {
            """
            Overall: \(Int(overall * 100))%
            ├─ Relevance: \(Int(relevance * 100))%
            ├─ Coherence: \(Int(coherence * 100))%
            ├─ Completeness: \(Int(completeness * 100))%
            ├─ Accuracy: \(Int(accuracy * 100))%
            └─ Helpfulness: \(Int(helpfulness * 100))%
            """
        }
    }
    
    // MARK: - Feedback
    
    public struct Feedback: Codable {
        let responseHash: Int
        let modelUsed: String
        let taskType: String
        let userRating: Rating
        let timestamp: Date
        
        public enum Rating: Int, Codable {
            case terrible = 1
            case poor = 2
            case okay = 3
            case good = 4
            case excellent = 5
            
            var weight: Float {
                Float(rawValue) / 5.0
            }
        }
    }
    
    // MARK: - State
    
    private var feedbackHistory: [Feedback] = []
    private var modelAccuracyScores: [String: (total: Float, count: Int)] = [:]
    private let feedbackFile: URL
    
    // MARK: - Init
    
    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZeroDark", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.feedbackFile = base.appendingPathComponent("feedback.json")
        
        loadFeedback()
    }
    
    // MARK: - Score Response
    
    public func score(
        response: String,
        prompt: String,
        model: Model,
        taskType: ModelRouter.TaskType
    ) -> QualityScore {
        // Relevance: Does the response address the prompt?
        let relevance = scoreRelevance(response: response, prompt: prompt)
        
        // Coherence: Is the response well-structured?
        let coherence = scoreCoherence(response: response)
        
        // Completeness: Does it fully answer?
        let completeness = scoreCompleteness(response: response, prompt: prompt)
        
        // Accuracy: Based on historical feedback for this model/task
        let accuracy = getHistoricalAccuracy(model: model, taskType: taskType)
        
        // Helpfulness: Heuristic based on content
        let helpfulness = scoreHelpfulness(response: response, taskType: taskType)
        
        // Weighted overall score
        let overall = (
            relevance * 0.25 +
            coherence * 0.20 +
            completeness * 0.20 +
            accuracy * 0.15 +
            helpfulness * 0.20
        )
        
        return QualityScore(
            overall: overall,
            relevance: relevance,
            coherence: coherence,
            completeness: completeness,
            accuracy: accuracy,
            helpfulness: helpfulness
        )
    }
    
    // MARK: - Scoring Components
    
    private func scoreRelevance(response: String, prompt: String) -> Float {
        let promptWords = Set(
            prompt.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
        
        let responseWords = Set(
            response.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
        
        guard !promptWords.isEmpty else { return 0.5 }
        
        let overlap = Float(promptWords.intersection(responseWords).count)
        let relevance = overlap / Float(promptWords.count)
        
        return min(relevance * 1.5, 1.0) // Scale up, cap at 1
    }
    
    private func scoreCoherence(response: String) -> Float {
        var score: Float = 0.5
        
        // Has proper sentence structure
        let sentences = response.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if sentences.count > 0 {
            score += 0.1
        }
        
        // Reasonable sentence length
        let avgLength = response.count / max(sentences.count, 1)
        if avgLength > 20 && avgLength < 200 {
            score += 0.1
        }
        
        // Has structure (paragraphs, lists, code blocks)
        if response.contains("\n\n") || response.contains("- ") || response.contains("```") {
            score += 0.15
        }
        
        // Doesn't have weird artifacts
        let artifacts = ["```\n\n```", "...", "????", "!!!!"]
        for artifact in artifacts {
            if response.contains(artifact) {
                score -= 0.1
            }
        }
        
        // Ends properly
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.last?.isPunctuation == true || trimmed.hasSuffix("```") {
            score += 0.1
        }
        
        return max(0, min(score, 1.0))
    }
    
    private func scoreCompleteness(response: String, prompt: String) -> Float {
        var score: Float = 0.5
        
        // Length relative to prompt complexity
        let promptComplexity = prompt.split(separator: " ").count
        let responseLength = response.split(separator: " ").count
        
        let expectedLength = promptComplexity * 10 // Rough heuristic
        let lengthRatio = Float(responseLength) / Float(max(expectedLength, 1))
        
        if lengthRatio > 0.5 && lengthRatio < 5 {
            score += 0.2
        }
        
        // Addresses question words
        let questionWords = ["what", "why", "how", "when", "where", "who", "which"]
        let promptLower = prompt.lowercased()
        
        for word in questionWords {
            if promptLower.contains(word) {
                // Check if response attempts to answer
                if responseLength > 20 {
                    score += 0.05
                }
            }
        }
        
        // Has conclusion or summary
        let conclusionIndicators = ["in summary", "therefore", "in conclusion", "to summarize", "overall"]
        for indicator in conclusionIndicators {
            if response.lowercased().contains(indicator) {
                score += 0.1
                break
            }
        }
        
        return min(score, 1.0)
    }
    
    private func scoreHelpfulness(response: String, taskType: ModelRouter.TaskType) -> Float {
        var score: Float = 0.5
        
        switch taskType {
        case .code:
            // Has code block
            if response.contains("```") {
                score += 0.3
            }
            // Has explanation
            if response.count > 200 {
                score += 0.1
            }
            
        case .reasoning, .math:
            // Shows work
            if response.contains("step") || response.contains("1.") || response.contains("first") {
                score += 0.2
            }
            // Has conclusion
            if response.contains("therefore") || response.contains("answer") || response.contains("result") {
                score += 0.1
            }
            
        case .creative, .roleplay:
            // Length indicates engagement
            if response.count > 300 {
                score += 0.2
            }
            // Dialogue or narrative elements
            if response.contains("\"") || response.contains("\n") {
                score += 0.1
            }
            
        default:
            // General helpfulness - substantial response
            if response.count > 100 {
                score += 0.2
            }
        }
        
        // Penalize refusals
        let refusalPhrases = ["i cannot", "i can't", "i'm unable", "as an ai", "i don't have the ability"]
        for phrase in refusalPhrases {
            if response.lowercased().contains(phrase) {
                score -= 0.4
                break
            }
        }
        
        return max(0, min(score, 1.0))
    }
    
    // MARK: - Historical Accuracy
    
    private func getHistoricalAccuracy(model: Model, taskType: ModelRouter.TaskType) -> Float {
        let key = "\(model.rawValue)_\(taskType.rawValue)"
        
        if let scores = modelAccuracyScores[key], scores.count > 0 {
            return scores.total / Float(scores.count)
        }
        
        // Default based on model tier
        if model.approximateSizeMB > 7000 {
            return 0.8 // 14B+ models
        } else if model.approximateSizeMB > 4000 {
            return 0.7 // 8B models
        } else {
            return 0.6 // Smaller models
        }
    }
    
    // MARK: - Feedback
    
    public func recordFeedback(
        response: String,
        model: Model,
        taskType: ModelRouter.TaskType,
        rating: Feedback.Rating
    ) {
        let feedback = Feedback(
            responseHash: response.hashValue,
            modelUsed: model.rawValue,
            taskType: taskType.rawValue,
            userRating: rating,
            timestamp: Date()
        )
        
        feedbackHistory.append(feedback)
        
        // Update accuracy scores
        let key = "\(model.rawValue)_\(taskType.rawValue)"
        var scores = modelAccuracyScores[key, default: (0, 0)]
        scores.total += rating.weight
        scores.count += 1
        modelAccuracyScores[key] = scores
        
        // Prune old feedback
        if feedbackHistory.count > 1000 {
            feedbackHistory.removeFirst(100)
        }
        
        saveFeedback()
    }
    
    // MARK: - Persistence
    
    private func saveFeedback() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(feedbackHistory) {
            try? data.write(to: feedbackFile)
        }
    }
    
    private func loadFeedback() {
        guard let data = try? Data(contentsOf: feedbackFile),
              let loaded = try? JSONDecoder().decode([Feedback].self, from: data) else {
            return
        }
        
        feedbackHistory = loaded
        
        // Rebuild accuracy scores
        for feedback in feedbackHistory {
            let key = "\(feedback.modelUsed)_\(feedback.taskType)"
            var scores = modelAccuracyScores[key, default: (0, 0)]
            scores.total += feedback.userRating.weight
            scores.count += 1
            modelAccuracyScores[key] = scores
        }
    }
    
    // MARK: - Analytics
    
    public var feedbackStats: (total: Int, avgRating: Float, byModel: [String: Float]) {
        var byModel: [String: (total: Float, count: Int)] = [:]
        var totalRating: Float = 0
        
        for feedback in feedbackHistory {
            totalRating += Float(feedback.userRating.rawValue)
            
            var modelStats = byModel[feedback.modelUsed, default: (0, 0)]
            modelStats.total += Float(feedback.userRating.rawValue)
            modelStats.count += 1
            byModel[feedback.modelUsed] = modelStats
        }
        
        let avg = feedbackHistory.isEmpty ? 0 : totalRating / Float(feedbackHistory.count)
        
        let modelAverages = byModel.mapValues { stats in
            stats.count > 0 ? stats.total / Float(stats.count) : 0
        }
        
        return (feedbackHistory.count, avg, modelAverages)
    }
}
