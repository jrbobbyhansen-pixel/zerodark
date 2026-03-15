// ProactiveIntelligence.swift
// AI that ANTICIPATES what you need before you ask
// ABSURD MODE

import Foundation

// MARK: - Proactive Intelligence

public actor ProactiveIntelligence {
    
    public static let shared = ProactiveIntelligence()
    
    // MARK: - Types
    
    public struct Suggestion: Identifiable, Sendable {
        public let id: UUID
        public let type: SuggestionType
        public let title: String
        public let description: String
        public let action: SuggestedAction
        public let confidence: Float  // 0.0 - 1.0
        public let expiresAt: Date?
        public let createdAt: Date
        
        public init(type: SuggestionType, title: String, description: String, action: SuggestedAction, confidence: Float, expiresAt: Date? = nil) {
            self.id = UUID()
            self.type = type
            self.title = title
            self.description = description
            self.action = action
            self.confidence = confidence
            self.expiresAt = expiresAt
            self.createdAt = Date()
        }
    }
    
    public enum SuggestionType: String, Sendable {
        case reminder = "Reminder"
        case routine = "Routine"
        case information = "Information"
        case action = "Action"
        case warning = "Warning"
        case opportunity = "Opportunity"
    }
    
    public enum SuggestedAction: Sendable {
        case runRoutine(String)
        case createReminder(String)
        case sendMessage(to: String, message: String)
        case openApp(String)
        case speak(String)
        case dismiss
        case custom(String)
    }
    
    public struct Pattern: Codable, Identifiable, Sendable {
        public let id: UUID
        public let type: PatternType
        public let description: String
        public let occurrences: Int
        public let lastOccurred: Date
        public let predictedNext: Date?
        public let confidence: Float
        
        public enum PatternType: String, Codable, Sendable {
            case timeOfDay = "Time of Day"
            case dayOfWeek = "Day of Week"
            case location = "Location"
            case appUsage = "App Usage"
            case conversation = "Conversation"
            case action = "Action"
        }
    }
    
    // MARK: - State
    
    private var patterns: [Pattern] = []
    private var pendingSuggestions: [Suggestion] = []
    private var dismissedSuggestions: Set<String> = []  // By type+title hash
    
    // Activity tracking
    private var activityLog: [ActivityEntry] = []
    private let maxActivityLog = 1000
    
    private struct ActivityEntry: Codable {
        let timestamp: Date
        let type: String
        let details: String
    }
    
    private init() {
        Task {
            await loadPatterns()
        }
    }
    
    // MARK: - Activity Logging
    
    /// Log an activity for pattern learning
    public func logActivity(type: String, details: String) async {
        let entry = ActivityEntry(timestamp: Date(), type: type, details: details)
        activityLog.append(entry)
        
        if activityLog.count > maxActivityLog {
            activityLog.removeFirst(activityLog.count - maxActivityLog)
        }
        
        // Analyze for patterns
        await analyzePatterns()
    }
    
    // MARK: - Pattern Analysis
    
    private func analyzePatterns() async {
        // Time-of-day patterns
        await analyzeTimePatterns()
        
        // Day-of-week patterns
        await analyzeDayPatterns()
        
        // Action sequence patterns
        await analyzeActionPatterns()
    }
    
    private func analyzeTimePatterns() async {
        // Group activities by hour
        var hourCounts: [Int: [String: Int]] = [:]
        
        for entry in activityLog {
            let hour = Calendar.current.component(.hour, from: entry.timestamp)
            hourCounts[hour, default: [:]][entry.type, default: 0] += 1
        }
        
        // Find strong patterns (same action at same hour multiple times)
        for (hour, types) in hourCounts {
            for (type, count) in types where count >= 3 {
                let confidence = min(Float(count) / 10.0, 0.9)
                
                // Check if pattern already exists
                if !patterns.contains(where: { $0.type == .timeOfDay && $0.description.contains(type) && $0.description.contains("\(hour)") }) {
                    let pattern = Pattern(
                        id: UUID(),
                        type: .timeOfDay,
                        description: "User often does '\(type)' around \(hour):00",
                        occurrences: count,
                        lastOccurred: Date(),
                        predictedNext: nextOccurrence(hour: hour),
                        confidence: confidence
                    )
                    patterns.append(pattern)
                }
            }
        }
    }
    
    private func analyzeDayPatterns() async {
        // Similar analysis for days of week
        var dayCounts: [Int: [String: Int]] = [:]
        
        for entry in activityLog {
            let day = Calendar.current.component(.weekday, from: entry.timestamp)
            dayCounts[day, default: [:]][entry.type, default: 0] += 1
        }
        
        for (day, types) in dayCounts {
            for (type, count) in types where count >= 2 {
                let dayName = Calendar.current.weekdaySymbols[day - 1]
                let confidence = min(Float(count) / 5.0, 0.85)
                
                if !patterns.contains(where: { $0.type == .dayOfWeek && $0.description.contains(type) && $0.description.contains(dayName) }) {
                    let pattern = Pattern(
                        id: UUID(),
                        type: .dayOfWeek,
                        description: "User often does '\(type)' on \(dayName)s",
                        occurrences: count,
                        lastOccurred: Date(),
                        predictedNext: nil,
                        confidence: confidence
                    )
                    patterns.append(pattern)
                }
            }
        }
    }
    
    private func analyzeActionPatterns() async {
        // Look for action sequences (A followed by B)
        for i in 0..<(activityLog.count - 1) {
            let current = activityLog[i]
            let next = activityLog[i + 1]
            
            let timeDiff = next.timestamp.timeIntervalSince(current.timestamp)
            if timeDiff < 300 {  // Within 5 minutes
                // This is a potential sequence
                // In production: track and count sequences
            }
        }
    }
    
    private func nextOccurrence(hour: Int) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        
        if let date = calendar.date(from: components) {
            if date > now {
                return date
            } else {
                return calendar.date(byAdding: .day, value: 1, to: date)
            }
        }
        return nil
    }
    
    // MARK: - Suggestion Generation
    
    /// Generate suggestions based on current context
    public func generateSuggestions() async -> [Suggestion] {
        var suggestions: [Suggestion] = []
        
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)
        
        // Check patterns for relevant suggestions
        for pattern in patterns {
            switch pattern.type {
            case .timeOfDay:
                if let predicted = pattern.predictedNext,
                   abs(predicted.timeIntervalSince(now)) < 1800 {  // Within 30 min
                    let suggestion = Suggestion(
                        type: .routine,
                        title: "Time for \(pattern.description.components(separatedBy: "'")[1])?",
                        description: "You usually do this around now",
                        action: .custom(pattern.description),
                        confidence: pattern.confidence
                    )
                    suggestions.append(suggestion)
                }
                
            case .dayOfWeek:
                let dayName = calendar.weekdaySymbols[weekday - 1]
                if pattern.description.contains(dayName) {
                    let suggestion = Suggestion(
                        type: .reminder,
                        title: pattern.description,
                        description: "It's \(dayName)",
                        action: .custom(pattern.description),
                        confidence: pattern.confidence
                    )
                    suggestions.append(suggestion)
                }
                
            default:
                break
            }
        }
        
        // Time-based default suggestions
        if hour >= 6 && hour < 9 {
            suggestions.append(Suggestion(
                type: .routine,
                title: "Run morning routine?",
                description: "Start your day with weather, calendar, and news",
                action: .runRoutine("Morning Routine"),
                confidence: 0.7
            ))
        }
        
        if hour >= 17 && hour < 19 {
            suggestions.append(Suggestion(
                type: .information,
                title: "Daily summary available",
                description: "Review what you accomplished today",
                action: .speak("Here's your daily summary"),
                confidence: 0.6
            ))
        }
        
        // Filter out dismissed suggestions
        suggestions = suggestions.filter { suggestion in
            let hash = "\(suggestion.type.rawValue)|\(suggestion.title)"
            return !dismissedSuggestions.contains(hash)
        }
        
        // Sort by confidence
        suggestions.sort { $0.confidence > $1.confidence }
        
        pendingSuggestions = suggestions
        return suggestions
    }
    
    /// Dismiss a suggestion (won't show again for this session)
    public func dismissSuggestion(_ suggestion: Suggestion) async {
        let hash = "\(suggestion.type.rawValue)|\(suggestion.title)"
        dismissedSuggestions.insert(hash)
        pendingSuggestions.removeAll { $0.id == suggestion.id }
    }
    
    /// Accept and execute a suggestion
    public func acceptSuggestion(_ suggestion: Suggestion) async -> String {
        await dismissSuggestion(suggestion)
        
        switch suggestion.action {
        case .runRoutine(let name):
            do {
                let result = try await RoutineEngine.shared.runRoutineByName(name) { _, _, _ in }
                return "Routine '\(name)' completed: \(result.success ? "Success" : "Failed")"
            } catch {
                return "Failed to run routine: \(error.localizedDescription)"
            }
            
        case .speak(let text):
            await VoiceSynthesisEngine.shared.speak(text)
            return "Speaking: \(text)"
            
        case .createReminder(let text):
            return "Created reminder: \(text)"
            
        case .openApp(let app):
            return "Opening \(app)"
            
        case .sendMessage(let to, let message):
            return "Sending message to \(to)"
            
        case .custom(let description):
            return "Executing: \(description)"
            
        case .dismiss:
            return "Dismissed"
        }
    }
    
    // MARK: - Persistence
    
    private func loadPatterns() async {
        // Load from UserDefaults or CoreData
    }
    
    private func savePatterns() async {
        // Save to persistence
    }
}
