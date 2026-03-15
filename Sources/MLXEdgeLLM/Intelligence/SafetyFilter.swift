import Foundation
import Combine

// MARK: - Safety Filter

/// Optional safety layer for enterprise/sensitive deployments
/// Can be completely disabled for uncensored use
public final class SafetyFilter: ObservableObject {
    
    public static let shared = SafetyFilter()
    
    // MARK: - Safety Level
    
    public enum Level: String, CaseIterable, Hashable {
        case off = "Off (Uncensored)"
        case minimal = "Minimal"
        case standard = "Standard"
        case strict = "Strict"
        case enterprise = "Enterprise"
        
        public var description: String {
            switch self {
            case .off: return "No filtering. Full uncensored access."
            case .minimal: return "Block only illegal content."
            case .standard: return "Block harmful + illegal content."
            case .strict: return "Block harmful, illegal, and sensitive content."
            case .enterprise: return "Maximum filtering for business use."
            }
        }
    }
    
    // MARK: - Filter Result
    
    public struct FilterResult {
        public let isAllowed: Bool
        public let flaggedCategories: [Category]
        public let confidence: Float
        public let sanitizedContent: String?
        
        public var reason: String? {
            guard !isAllowed else { return nil }
            return "Content flagged: \(flaggedCategories.map(\.rawValue).joined(separator: ", "))"
        }
    }
    
    public enum Category: String, CaseIterable {
        case violence = "Violence"
        case hateSpeech = "Hate Speech"
        case sexualContent = "Sexual Content"
        case illegalActivity = "Illegal Activity"
        case personalInfo = "Personal Information"
        case misinformation = "Misinformation"
        case selfHarm = "Self-Harm"
        case malware = "Malware/Hacking"
    }
    
    // MARK: - State
    
    @Published public var level: Level = .off
    @Published public var customBlocklist: Set<String> = []
    @Published public var customAllowlist: Set<String> = []
    
    // Pattern storage
    private var categoryPatterns: [Category: [String]] = [:]
    
    // MARK: - Init
    
    private init() {
        loadDefaultPatterns()
    }
    
    // MARK: - Filter Input
    
    public func filterInput(_ input: String) -> FilterResult {
        guard level != .off else {
            return FilterResult(
                isAllowed: true,
                flaggedCategories: [],
                confidence: 1.0,
                sanitizedContent: nil
            )
        }
        
        return analyze(input)
    }
    
    // MARK: - Filter Output
    
    public func filterOutput(_ output: String) -> FilterResult {
        guard level != .off else {
            return FilterResult(
                isAllowed: true,
                flaggedCategories: [],
                confidence: 1.0,
                sanitizedContent: nil
            )
        }
        
        return analyze(output)
    }
    
    // MARK: - Analysis
    
    private func analyze(_ content: String) -> FilterResult {
        let lower = content.lowercased()
        var flagged: [Category] = []
        var totalConfidence: Float = 0
        
        // Check custom blocklist first
        for blocked in customBlocklist {
            if lower.contains(blocked.lowercased()) {
                return FilterResult(
                    isAllowed: false,
                    flaggedCategories: [],
                    confidence: 1.0,
                    sanitizedContent: sanitize(content, removing: [blocked])
                )
            }
        }
        
        // Check custom allowlist
        for allowed in customAllowlist {
            if lower.contains(allowed.lowercased()) {
                return FilterResult(
                    isAllowed: true,
                    flaggedCategories: [],
                    confidence: 1.0,
                    sanitizedContent: nil
                )
            }
        }
        
        // Check each category based on level
        let categoriesToCheck = categoriesForLevel(level)
        
        for category in categoriesToCheck {
            if let patterns = categoryPatterns[category] {
                let (detected, confidence) = checkPatterns(patterns, in: lower)
                if detected {
                    flagged.append(category)
                    totalConfidence = max(totalConfidence, confidence)
                }
            }
        }
        
        let isAllowed = flagged.isEmpty
        
        return FilterResult(
            isAllowed: isAllowed,
            flaggedCategories: flagged,
            confidence: totalConfidence,
            sanitizedContent: isAllowed ? nil : sanitize(content, categories: flagged)
        )
    }
    
    private func categoriesForLevel(_ level: Level) -> [Category] {
        switch level {
        case .off:
            return []
        case .minimal:
            return [.illegalActivity, .malware]
        case .standard:
            return [.illegalActivity, .malware, .violence, .selfHarm]
        case .strict:
            return [.illegalActivity, .malware, .violence, .selfHarm, .hateSpeech, .sexualContent]
        case .enterprise:
            return Category.allCases
        }
    }
    
    private func checkPatterns(_ patterns: [String], in content: String) -> (Bool, Float) {
        var matchCount = 0
        
        for pattern in patterns {
            if content.contains(pattern) {
                matchCount += 1
            }
        }
        
        let confidence = Float(matchCount) / Float(max(patterns.count, 1))
        return (matchCount > 0, min(confidence * 3, 1.0)) // Scale up confidence
    }
    
    // MARK: - Sanitization
    
    private func sanitize(_ content: String, removing words: [String]) -> String {
        var result = content
        for word in words {
            result = result.replacingOccurrences(
                of: word,
                with: String(repeating: "*", count: word.count),
                options: .caseInsensitive
            )
        }
        return result
    }
    
    private func sanitize(_ content: String, categories: [Category]) -> String {
        var result = content
        
        for category in categories {
            if let patterns = categoryPatterns[category] {
                for pattern in patterns {
                    result = result.replacingOccurrences(
                        of: pattern,
                        with: "[FILTERED]",
                        options: .caseInsensitive
                    )
                }
            }
        }
        
        return result
    }
    
    // MARK: - Default Patterns
    
    private func loadDefaultPatterns() {
        // Note: These are simplified examples. Production would need comprehensive lists.
        
        categoryPatterns[.illegalActivity] = [
            "how to make a bomb",
            "how to synthesize",
            "buy drugs online",
            "hack into",
            "steal identity"
        ]
        
        categoryPatterns[.malware] = [
            "ransomware code",
            "keylogger",
            "backdoor access",
            "exploit code",
            "zero day"
        ]
        
        categoryPatterns[.violence] = [
            "kill someone",
            "murder",
            "torture",
            "mass shooting"
        ]
        
        categoryPatterns[.selfHarm] = [
            "suicide methods",
            "how to hurt myself",
            "end my life"
        ]
        
        categoryPatterns[.hateSpeech] = [
            // Intentionally minimal - this is a sensitive area
        ]
        
        categoryPatterns[.sexualContent] = [
            // Context-dependent - minimal patterns
        ]
        
        categoryPatterns[.personalInfo] = [
            "social security number",
            "credit card number",
            "bank account"
        ]
        
        categoryPatterns[.misinformation] = [
            // Very hard to detect automatically
        ]
    }
    
    // MARK: - Configuration
    
    public func addToBlocklist(_ term: String) {
        customBlocklist.insert(term)
    }
    
    public func removeFromBlocklist(_ term: String) {
        customBlocklist.remove(term)
    }
    
    public func addToAllowlist(_ term: String) {
        customAllowlist.insert(term)
    }
    
    public func removeFromAllowlist(_ term: String) {
        customAllowlist.remove(term)
    }
    
    public func setLevel(_ newLevel: Level) {
        level = newLevel
    }
}

// MARK: - Safe Response Wrapper

public extension SafetyFilter {
    
    /// Wrap AI response with safety check
    func safeResponse(_ response: String) -> (content: String, wasSanitized: Bool) {
        let result = filterOutput(response)
        
        if result.isAllowed {
            return (response, false)
        } else if let sanitized = result.sanitizedContent {
            return (sanitized, true)
        } else {
            return ("[Response filtered due to safety policy]", true)
        }
    }
}
