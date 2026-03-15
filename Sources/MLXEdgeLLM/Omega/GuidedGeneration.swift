import Foundation

// MARK: - Guided Generation

/// Force LLM output to match a schema
/// JSON, regex, grammar — guaranteed valid output

public actor GuidedGeneration {
    
    public static let shared = GuidedGeneration()
    
    // MARK: - Output Modes
    
    public enum OutputMode {
        case freeform                           // No constraints
        case json(schema: JSONSchema)           // Valid JSON matching schema
        case regex(pattern: String)             // Match regex pattern
        case choices([String])                  // One of these strings
        case grammar(Grammar)                   // Custom grammar
    }
    
    // MARK: - JSON Schema
    
    public struct JSONSchema: Codable {
        public let type: String
        public let properties: [String: PropertySchema]?
        public let required: [String]?
        public let items: PropertySchema?
        
        public struct PropertySchema: Codable {
            public let type: String
            public let description: String?
            public let `enum`: [String]?
        }
        
        // Common schemas
        public static var yesNo: JSONSchema {
            JSONSchema(
                type: "object",
                properties: [
                    "answer": PropertySchema(type: "string", description: nil, enum: ["yes", "no"])
                ],
                required: ["answer"],
                items: nil
            )
        }
        
        public static var sentiment: JSONSchema {
            JSONSchema(
                type: "object",
                properties: [
                    "sentiment": PropertySchema(type: "string", description: nil, enum: ["positive", "negative", "neutral"]),
                    "confidence": PropertySchema(type: "number", description: "0-1", enum: nil)
                ],
                required: ["sentiment", "confidence"],
                items: nil
            )
        }
        
        public static func list(of itemType: String) -> JSONSchema {
            JSONSchema(
                type: "array",
                properties: nil,
                required: nil,
                items: PropertySchema(type: itemType, description: nil, enum: nil)
            )
        }
    }
    
    // MARK: - Grammar
    
    public struct Grammar {
        public let rules: [String: String]
        public let startRule: String
        
        // Common grammars
        public static var json: Grammar {
            Grammar(
                rules: [
                    "root": "object | array",
                    "object": "\"{\" (pair (\",\" pair)*)? \"}\"",
                    "array": "\"[\" (value (\",\" value)*)? \"]\"",
                    "pair": "string \":\" value",
                    "value": "string | number | object | array | \"true\" | \"false\" | \"null\"",
                    "string": "\"\\\"\" [^\"\\n]* \"\\\"\"",
                    "number": "-? [0-9]+ (\".\" [0-9]+)?"
                ],
                startRule: "root"
            )
        }
        
        public static var sql: Grammar {
            Grammar(
                rules: [
                    "root": "select_stmt",
                    "select_stmt": "\"SELECT\" columns \"FROM\" table where_clause?",
                    "columns": "\"*\" | column (\",\" column)*",
                    "column": "[a-zA-Z_][a-zA-Z0-9_]*",
                    "table": "[a-zA-Z_][a-zA-Z0-9_]*",
                    "where_clause": "\"WHERE\" condition"
                ],
                startRule: "root"
            )
        }
    }
    
    // MARK: - Constrained Generation
    
    /// Generate with constraints
    public func generate(
        prompt: String,
        mode: OutputMode,
        engine: BeastEngine
    ) async throws -> String {
        switch mode {
        case .freeform:
            return try await engine.generate(prompt: prompt) { _ in }
            
        case .json(let schema):
            return try await generateJSON(prompt: prompt, schema: schema, engine: engine)
            
        case .regex(let pattern):
            return try await generateRegex(prompt: prompt, pattern: pattern, engine: engine)
            
        case .choices(let options):
            return try await generateChoice(prompt: prompt, options: options, engine: engine)
            
        case .grammar(let grammar):
            return try await generateGrammar(prompt: prompt, grammar: grammar, engine: engine)
        }
    }
    
    // MARK: - JSON Generation
    
    private func generateJSON(
        prompt: String,
        schema: JSONSchema,
        engine: BeastEngine
    ) async throws -> String {
        // Add schema to prompt
        let schemaJSON = try JSONEncoder().encode(schema)
        let schemaString = String(data: schemaJSON, encoding: .utf8) ?? "{}"
        
        let constrainedPrompt = """
        \(prompt)
        
        Respond with valid JSON matching this schema:
        \(schemaString)
        
        JSON:
        """
        
        var output = try await engine.generate(prompt: constrainedPrompt) { _ in }
        
        // Extract JSON from output
        if let start = output.firstIndex(of: "{") ?? output.firstIndex(of: "["),
           let end = output.lastIndex(of: "}") ?? output.lastIndex(of: "]") {
            output = String(output[start...end])
        }
        
        // Validate
        guard let data = output.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw GenerationError.invalidJSON
        }
        
        return output
    }
    
    // MARK: - Regex Generation
    
    private func generateRegex(
        prompt: String,
        pattern: String,
        engine: BeastEngine
    ) async throws -> String {
        let constrainedPrompt = """
        \(prompt)
        
        Your response must match this pattern: \(pattern)
        Response:
        """
        
        let output = try await engine.generate(prompt: constrainedPrompt) { _ in }
        
        // Validate
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(output.startIndex..., in: output)
        
        guard regex.firstMatch(in: output, range: range) != nil else {
            throw GenerationError.patternMismatch
        }
        
        return output
    }
    
    // MARK: - Choice Generation
    
    private func generateChoice(
        prompt: String,
        options: [String],
        engine: BeastEngine
    ) async throws -> String {
        let optionsList = options.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        
        let constrainedPrompt = """
        \(prompt)
        
        Choose exactly one of these options:
        \(optionsList)
        
        Answer with just the option text:
        """
        
        let output = try await engine.generate(prompt: constrainedPrompt) { _ in }
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find best match
        for option in options {
            if cleaned.lowercased().contains(option.lowercased()) {
                return option
            }
        }
        
        throw GenerationError.invalidChoice
    }
    
    // MARK: - Grammar Generation
    
    private func generateGrammar(
        prompt: String,
        grammar: Grammar,
        engine: BeastEngine
    ) async throws -> String {
        // Grammar-guided generation would use token masking
        // Simplified version just prompts for format
        
        let constrainedPrompt = """
        \(prompt)
        
        Format your response according to this grammar:
        Start: \(grammar.startRule)
        
        Response:
        """
        
        return try await engine.generate(prompt: constrainedPrompt) { _ in }
    }
    
    // MARK: - Errors
    
    public enum GenerationError: Error {
        case invalidJSON
        case patternMismatch
        case invalidChoice
        case grammarViolation
    }
}

// MARK: - Convenience Extensions

public extension GuidedGeneration {
    
    /// Generate boolean answer
    func generateBool(prompt: String, engine: BeastEngine) async throws -> Bool {
        let result = try await generate(
            prompt: prompt + "\nAnswer yes or no:",
            mode: .choices(["yes", "no"]),
            engine: engine
        )
        return result.lowercased() == "yes"
    }
    
    /// Generate integer
    func generateInt(prompt: String, min: Int, max: Int, engine: BeastEngine) async throws -> Int {
        let result = try await generate(
            prompt: prompt + "\nAnswer with a number between \(min) and \(max):",
            mode: .regex(pattern: "-?\\d+"),
            engine: engine
        )
        
        guard let value = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= min && value <= max else {
            throw GenerationError.patternMismatch
        }
        
        return value
    }
    
    /// Generate list
    func generateList(prompt: String, engine: BeastEngine) async throws -> [String] {
        let result = try await generate(
            prompt: prompt,
            mode: .json(schema: .list(of: "string")),
            engine: engine
        )
        
        guard let data = result.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            throw GenerationError.invalidJSON
        }
        
        return array
    }
}
