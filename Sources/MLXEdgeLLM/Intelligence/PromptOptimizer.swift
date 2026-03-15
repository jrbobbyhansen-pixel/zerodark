import Foundation

// MARK: - Prompt Optimizer

/// Enhances prompts for better model performance
public struct PromptOptimizer {
    
    // MARK: - Optimization Strategies
    
    public enum Strategy: String, CaseIterable {
        case none = "None"
        case clarify = "Clarify"
        case expand = "Expand"
        case constrain = "Constrain"
        case chainOfThought = "Chain of Thought"
        case fewShot = "Few-Shot Examples"
        case roleplay = "Roleplay Setup"
        case structured = "Structured Output"
    }
    
    // MARK: - Optimize
    
    /// Automatically optimize a prompt based on detected intent
    public static func optimize(
        _ prompt: String,
        for taskType: ModelRouter.TaskType,
        strategy: Strategy? = nil
    ) -> String {
        let effectiveStrategy = strategy ?? recommendStrategy(for: taskType)
        
        switch effectiveStrategy {
        case .none:
            return prompt
            
        case .clarify:
            return clarifyPrompt(prompt)
            
        case .expand:
            return expandPrompt(prompt)
            
        case .constrain:
            return constrainPrompt(prompt)
            
        case .chainOfThought:
            return addChainOfThought(prompt)
            
        case .fewShot:
            return addFewShotExamples(prompt, taskType: taskType)
            
        case .roleplay:
            return setupRoleplay(prompt)
            
        case .structured:
            return requestStructuredOutput(prompt)
        }
    }
    
    // MARK: - Strategy Recommendation
    
    private static func recommendStrategy(for taskType: ModelRouter.TaskType) -> Strategy {
        switch taskType {
        case .code:
            return .structured
        case .reasoning, .math:
            return .chainOfThought
        case .creative:
            return .expand
        case .roleplay:
            return .roleplay
        case .summarization:
            return .constrain
        default:
            return .clarify
        }
    }
    
    // MARK: - Clarify
    
    private static func clarifyPrompt(_ prompt: String) -> String {
        // Add clarifying structure
        """
        Please help me with the following request. Be thorough and accurate.
        
        REQUEST: \(prompt)
        
        Provide a clear, well-organized response.
        """
    }
    
    // MARK: - Expand
    
    private static func expandPrompt(_ prompt: String) -> String {
        """
        \(prompt)
        
        Please be creative and expansive in your response. Include:
        - Rich details and descriptions
        - Multiple perspectives or approaches
        - Engaging narrative elements where appropriate
        
        Take your time and craft something memorable.
        """
    }
    
    // MARK: - Constrain
    
    private static func constrainPrompt(_ prompt: String) -> String {
        """
        \(prompt)
        
        Keep your response:
        - Concise and focused
        - Under 200 words if possible
        - Bullet points for key information
        - No unnecessary elaboration
        """
    }
    
    // MARK: - Chain of Thought
    
    private static func addChainOfThought(_ prompt: String) -> String {
        """
        \(prompt)
        
        Think through this step-by-step:
        1. First, understand what's being asked
        2. Break down the problem into parts
        3. Solve each part systematically
        4. Verify your reasoning
        5. Provide the final answer
        
        Show your work clearly.
        """
    }
    
    // MARK: - Few-Shot Examples
    
    private static func addFewShotExamples(_ prompt: String, taskType: ModelRouter.TaskType) -> String {
        let examples: String
        
        switch taskType {
        case .code:
            examples = """
            Example 1:
            Q: Write a function to check if a number is prime
            A: ```python
            def is_prime(n):
                if n < 2:
                    return False
                for i in range(2, int(n**0.5) + 1):
                    if n % i == 0:
                        return False
                return True
            ```
            
            Example 2:
            Q: Reverse a string
            A: ```python
            def reverse_string(s):
                return s[::-1]
            ```
            """
            
        case .summarization:
            examples = """
            Example:
            Text: "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet and is often used for typing practice."
            Summary: A pangram sentence used for typing practice.
            """
            
        default:
            examples = ""
        }
        
        if examples.isEmpty {
            return prompt
        }
        
        return """
        Here are some examples of the format I'm looking for:
        
        \(examples)
        
        Now, please handle this:
        \(prompt)
        """
    }
    
    // MARK: - Roleplay Setup
    
    private static func setupRoleplay(_ prompt: String) -> String {
        """
        You are about to engage in a roleplay scenario. Fully embody the character or role.
        Stay in character throughout. Be creative and responsive to the scenario.
        
        \(prompt)
        
        Begin the roleplay now. Do not break character or add meta-commentary.
        """
    }
    
    // MARK: - Structured Output
    
    private static func requestStructuredOutput(_ prompt: String) -> String {
        """
        \(prompt)
        
        Format your response with clear structure:
        - Use headers for major sections
        - Use code blocks for any code (with language tags)
        - Use bullet points for lists
        - Include comments explaining complex parts
        
        Make the output easy to read and copy.
        """
    }
}

// MARK: - Prompt Templates

public extension PromptOptimizer {
    
    /// Pre-built prompts for common tasks
    enum Template: String, CaseIterable {
        case codeReview = "Code Review"
        case bugFix = "Bug Fix"
        case explain = "Explain Concept"
        case compare = "Compare Options"
        case brainstorm = "Brainstorm Ideas"
        case rewrite = "Rewrite Text"
        case translate = "Translate"
        case summarize = "Summarize"
        
        public func apply(to content: String, additionalContext: String? = nil) -> String {
            switch self {
            case .codeReview:
                return """
                Review this code for:
                1. Bugs or errors
                2. Performance issues
                3. Best practices violations
                4. Security concerns
                5. Readability improvements
                
                Code:
                ```
                \(content)
                ```
                
                Provide specific, actionable feedback.
                """
                
            case .bugFix:
                return """
                This code has a bug. Find and fix it:
                
                ```
                \(content)
                ```
                
                \(additionalContext.map { "Error/Symptom: \($0)" } ?? "")
                
                Explain what was wrong and show the corrected code.
                """
                
            case .explain:
                return """
                Explain this concept clearly: \(content)
                
                Include:
                - Simple definition
                - Why it matters
                - Real-world example
                - Common misconceptions
                
                Make it understandable to someone new to the topic.
                """
                
            case .compare:
                return """
                Compare and contrast: \(content)
                
                Structure:
                | Aspect | Option A | Option B |
                |--------|----------|----------|
                
                Include pros/cons and when to choose each.
                """
                
            case .brainstorm:
                return """
                Brainstorm ideas for: \(content)
                
                Generate at least 10 diverse ideas. Include:
                - Conventional approaches
                - Creative/unconventional options
                - Quick wins
                - Long-term strategies
                
                Don't self-censor - include wild ideas too.
                """
                
            case .rewrite:
                return """
                Rewrite this text to be clearer and more engaging:
                
                Original:
                \(content)
                
                \(additionalContext.map { "Style/tone: \($0)" } ?? "Make it professional but approachable.")
                """
                
            case .translate:
                let targetLang = additionalContext ?? "Spanish"
                return """
                Translate to \(targetLang):
                
                \(content)
                
                Maintain the meaning and tone. Adapt idioms appropriately.
                """
                
            case .summarize:
                return """
                Summarize the following:
                
                \(content)
                
                Provide:
                1. One-sentence summary
                2. 3-5 key points
                3. Any important caveats or context
                """
            }
        }
    }
}

// MARK: - Response Enhancer

public struct ResponseEnhancer {
    
    /// Clean up model output
    public static func clean(_ response: String) -> String {
        var cleaned = response
        
        // Remove thinking tags if present
        let (_, answer) = ThinkingParser.parse(cleaned)
        cleaned = answer
        
        // Remove excessive whitespace
        cleaned = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        
        // Collapse multiple blank lines
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Extract code blocks from response
    public static func extractCode(_ response: String) -> [(language: String?, code: String)] {
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let range = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, range: range)
        
        return matches.compactMap { match in
            guard let codeRange = Range(match.range(at: 2), in: response) else { return nil }
            let langRange = Range(match.range(at: 1), in: response)
            let language = langRange.flatMap { String(response[$0]) }
            let code = String(response[codeRange])
            return (language?.isEmpty == true ? nil : language, code)
        }
    }
    
    /// Format response for display
    public static func formatForDisplay(_ response: String, maxLength: Int? = nil) -> String {
        var formatted = clean(response)
        
        if let max = maxLength, formatted.count > max {
            let truncated = String(formatted.prefix(max))
            if let lastSpace = truncated.lastIndex(of: " ") {
                formatted = String(truncated[..<lastSpace]) + "..."
            } else {
                formatted = truncated + "..."
            }
        }
        
        return formatted
    }
}
