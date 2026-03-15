import Foundation
import JavaScriptCore

// MARK: - Code Execution Sandbox

/// On-device code execution for JavaScript (and pseudo-Python via transpilation)
public actor CodeSandbox {
    
    public static let shared = CodeSandbox()
    
    // MARK: - Types
    
    public enum Language: String, CaseIterable {
        case javascript = "JavaScript"
        case python = "Python"  // Transpiled to JS
        case json = "JSON"
        case regex = "Regex"
    }
    
    public struct ExecutionResult {
        public let success: Bool
        public let output: String
        public let error: String?
        public let executionTime: TimeInterval
        public let memoryUsed: Int?
    }
    
    // MARK: - JavaScript Context
    
    private var jsContext: JSContext?
    private var executionCount = 0
    private let maxExecutions = 1000 // Reset context periodically
    
    // MARK: - Init
    
    private init() {
        setupContext()
    }
    
    private func setupContext() {
        jsContext = JSContext()
        
        guard let ctx = jsContext else { return }
        
        // Add console.log
        let consoleLog: @convention(block) (String) -> Void = { message in
            print("[JS Console]: \(message)")
        }
        ctx.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        
        // Create console object
        ctx.evaluateScript("""
            var console = {
                log: function() {
                    var args = Array.prototype.slice.call(arguments);
                    log(args.map(function(a) { 
                        return typeof a === 'object' ? JSON.stringify(a) : String(a); 
                    }).join(' '));
                },
                error: function() { this.log.apply(this, arguments); },
                warn: function() { this.log.apply(this, arguments); },
                info: function() { this.log.apply(this, arguments); }
            };
        """)
        
        // Add math utilities
        ctx.evaluateScript("""
            var Math = Math || {};
            function range(start, end, step) {
                step = step || 1;
                var result = [];
                for (var i = start; i < end; i += step) {
                    result.push(i);
                }
                return result;
            }
            
            function sum(arr) {
                return arr.reduce(function(a, b) { return a + b; }, 0);
            }
            
            function mean(arr) {
                return sum(arr) / arr.length;
            }
            
            function max(arr) {
                return Math.max.apply(null, arr);
            }
            
            function min(arr) {
                return Math.min.apply(null, arr);
            }
            
            function sorted(arr, reverse) {
                var copy = arr.slice();
                copy.sort(function(a, b) { return a - b; });
                return reverse ? copy.reverse() : copy;
            }
            
            function reversed(arr) {
                return arr.slice().reverse();
            }
            
            function len(obj) {
                if (Array.isArray(obj) || typeof obj === 'string') {
                    return obj.length;
                }
                return Object.keys(obj).length;
            }
            
            function print() {
                console.log.apply(console, arguments);
            }
        """)
        
        // Error handler
        ctx.exceptionHandler = { context, exception in
            print("[JS Error]: \(exception?.toString() ?? "Unknown error")")
        }
    }
    
    // MARK: - Execute
    
    public func execute(
        code: String,
        language: Language,
        timeout: TimeInterval = 5.0
    ) async -> ExecutionResult {
        let startTime = Date()
        
        // Periodically reset context to prevent memory buildup
        executionCount += 1
        if executionCount > maxExecutions {
            setupContext()
            executionCount = 0
        }
        
        switch language {
        case .javascript:
            return executeJavaScript(code, startTime: startTime, timeout: timeout)
            
        case .python:
            // Transpile Python-like syntax to JavaScript
            let transpiled = transpilePythonToJS(code)
            return executeJavaScript(transpiled, startTime: startTime, timeout: timeout)
            
        case .json:
            return validateJSON(code, startTime: startTime)
            
        case .regex:
            return testRegex(code, startTime: startTime)
        }
    }
    
    // MARK: - JavaScript Execution
    
    private func executeJavaScript(
        _ code: String,
        startTime: Date,
        timeout: TimeInterval
    ) -> ExecutionResult {
        guard let ctx = jsContext else {
            return ExecutionResult(
                success: false,
                output: "",
                error: "JavaScript context not available",
                executionTime: 0,
                memoryUsed: nil
            )
        }
        
        // Capture console output
        var consoleOutput: [String] = []
        let captureLog: @convention(block) (String) -> Void = { message in
            consoleOutput.append(message)
        }
        ctx.setObject(captureLog, forKeyedSubscript: "log" as NSString)
        
        // Wrap code to capture result
        let wrappedCode = """
        (function() {
            try {
                var __result__ = (function() {
                    \(code)
                })();
                if (__result__ !== undefined) {
                    return typeof __result__ === 'object' ? JSON.stringify(__result__, null, 2) : String(__result__);
                }
                return '';
            } catch (e) {
                return 'Error: ' + e.message;
            }
        })()
        """
        
        // Execute
        var error: String?
        ctx.exceptionHandler = { _, exception in
            error = exception?.toString()
        }
        
        let result = ctx.evaluateScript(wrappedCode)
        let executionTime = Date().timeIntervalSince(startTime)
        
        if let err = error {
            return ExecutionResult(
                success: false,
                output: consoleOutput.joined(separator: "\n"),
                error: err,
                executionTime: executionTime,
                memoryUsed: nil
            )
        }
        
        var output = consoleOutput.joined(separator: "\n")
        if let resultStr = result?.toString(), !resultStr.isEmpty, resultStr != "undefined" {
            if !output.isEmpty {
                output += "\n"
            }
            output += resultStr
        }
        
        return ExecutionResult(
            success: true,
            output: output.isEmpty ? "(no output)" : output,
            error: nil,
            executionTime: executionTime,
            memoryUsed: nil
        )
    }
    
    // MARK: - Python Transpilation
    
    /// Simple Python to JavaScript transpilation for common constructs
    private func transpilePythonToJS(_ python: String) -> String {
        var js = python
        
        // print() → console.log()
        js = js.replacingOccurrences(of: "print(", with: "console.log(")
        
        // True/False/None → true/false/null
        js = js.replacingOccurrences(of: "True", with: "true")
        js = js.replacingOccurrences(of: "False", with: "false")
        js = js.replacingOccurrences(of: "None", with: "null")
        
        // def → function
        let defPattern = #"def\s+(\w+)\s*\(([^)]*)\)\s*:"#
        if let regex = try? NSRegularExpression(pattern: defPattern) {
            js = regex.stringByReplacingMatches(
                in: js,
                range: NSRange(js.startIndex..., in: js),
                withTemplate: "function $1($2) {"
            )
        }
        
        // for x in range(n): → for (var x = 0; x < n; x++) {
        let forRangePattern = #"for\s+(\w+)\s+in\s+range\((\d+)\)\s*:"#
        if let regex = try? NSRegularExpression(pattern: forRangePattern) {
            js = regex.stringByReplacingMatches(
                in: js,
                range: NSRange(js.startIndex..., in: js),
                withTemplate: "for (var $1 = 0; $1 < $2; $1++) {"
            )
        }
        
        // for x in array: → for (var x of array) {
        let forInPattern = #"for\s+(\w+)\s+in\s+(\w+)\s*:"#
        if let regex = try? NSRegularExpression(pattern: forInPattern) {
            js = regex.stringByReplacingMatches(
                in: js,
                range: NSRange(js.startIndex..., in: js),
                withTemplate: "for (var $1 of $2) {"
            )
        }
        
        // if condition: → if (condition) {
        let ifPattern = #"if\s+(.+?)\s*:"#
        if let regex = try? NSRegularExpression(pattern: ifPattern) {
            js = regex.stringByReplacingMatches(
                in: js,
                range: NSRange(js.startIndex..., in: js),
                withTemplate: "if ($1) {"
            )
        }
        
        // elif → else if
        js = js.replacingOccurrences(of: "elif", with: "else if")
        
        // else: → else {
        js = js.replacingOccurrences(of: "else:", with: "else {")
        
        // while condition: → while (condition) {
        let whilePattern = #"while\s+(.+?)\s*:"#
        if let regex = try? NSRegularExpression(pattern: whilePattern) {
            js = regex.stringByReplacingMatches(
                in: js,
                range: NSRange(js.startIndex..., in: js),
                withTemplate: "while ($1) {"
            )
        }
        
        // and/or/not → &&/||/!
        js = js.replacingOccurrences(of: " and ", with: " && ")
        js = js.replacingOccurrences(of: " or ", with: " || ")
        js = js.replacingOccurrences(of: "not ", with: "!")
        
        // ** → Math.pow
        let powPattern = #"(\w+)\s*\*\*\s*(\w+)"#
        if let regex = try? NSRegularExpression(pattern: powPattern) {
            js = regex.stringByReplacingMatches(
                in: js,
                range: NSRange(js.startIndex..., in: js),
                withTemplate: "Math.pow($1, $2)"
            )
        }
        
        // // → Math.floor(/)
        js = js.replacingOccurrences(of: "//", with: "/ /* floor */ ")
        
        // len() already defined in context
        // range() already defined in context
        
        // Add closing braces based on indentation
        js = addClosingBraces(js)
        
        // return without braces at end
        let lines = js.components(separatedBy: "\n")
        if let lastLine = lines.last?.trimmingCharacters(in: .whitespaces),
           !lastLine.isEmpty,
           !lastLine.hasPrefix("return"),
           !lastLine.hasPrefix("console"),
           !lastLine.hasPrefix("//"),
           !lastLine.contains("{"),
           !lastLine.contains("}") {
            js += "\nreturn \(lastLine);"
        }
        
        return js
    }
    
    private func addClosingBraces(_ code: String) -> String {
        var lines = code.components(separatedBy: "\n")
        var result: [String] = []
        var indentStack: [Int] = [0]
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            let currentIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            
            // Close braces for decreased indentation
            while currentIndent < indentStack.last! && indentStack.count > 1 {
                indentStack.removeLast()
                result.append(String(repeating: " ", count: indentStack.last!) + "}")
            }
            
            result.append(line)
            
            // Track increased indentation (block start)
            if trimmed.hasSuffix("{") {
                indentStack.append(currentIndent + 4)
            }
        }
        
        // Close remaining braces
        while indentStack.count > 1 {
            indentStack.removeLast()
            result.append(String(repeating: " ", count: indentStack.last!) + "}")
        }
        
        return result.joined(separator: "\n")
    }
    
    // MARK: - JSON Validation
    
    private func validateJSON(_ json: String, startTime: Date) -> ExecutionResult {
        guard let data = json.data(using: .utf8) else {
            return ExecutionResult(
                success: false,
                output: "",
                error: "Invalid UTF-8 encoding",
                executionTime: Date().timeIntervalSince(startTime),
                memoryUsed: nil
            )
        }
        
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            let formatted = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            let output = String(data: formatted, encoding: .utf8) ?? ""
            
            return ExecutionResult(
                success: true,
                output: "✓ Valid JSON\n\n\(output)",
                error: nil,
                executionTime: Date().timeIntervalSince(startTime),
                memoryUsed: nil
            )
        } catch {
            return ExecutionResult(
                success: false,
                output: "",
                error: "Invalid JSON: \(error.localizedDescription)",
                executionTime: Date().timeIntervalSince(startTime),
                memoryUsed: nil
            )
        }
    }
    
    // MARK: - Regex Testing
    
    private func testRegex(_ input: String, startTime: Date) -> ExecutionResult {
        // Parse input: first line is pattern, rest is test strings
        let lines = input.components(separatedBy: "\n")
        guard let pattern = lines.first, !pattern.isEmpty else {
            return ExecutionResult(
                success: false,
                output: "",
                error: "No regex pattern provided",
                executionTime: Date().timeIntervalSince(startTime),
                memoryUsed: nil
            )
        }
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            var output = "Pattern: /\(pattern)/\n\n"
            
            let testStrings = lines.dropFirst()
            if testStrings.isEmpty {
                output += "✓ Regex compiles successfully"
            } else {
                for test in testStrings where !test.isEmpty {
                    let range = NSRange(test.startIndex..., in: test)
                    let matches = regex.matches(in: test, range: range)
                    
                    if matches.isEmpty {
                        output += "✗ \"\(test)\" — No match\n"
                    } else {
                        let matchStrings = matches.compactMap { match -> String? in
                            guard let range = Range(match.range, in: test) else { return nil }
                            return String(test[range])
                        }
                        output += "✓ \"\(test)\" — Matches: \(matchStrings.joined(separator: ", "))\n"
                    }
                }
            }
            
            return ExecutionResult(
                success: true,
                output: output,
                error: nil,
                executionTime: Date().timeIntervalSince(startTime),
                memoryUsed: nil
            )
        } catch {
            return ExecutionResult(
                success: false,
                output: "",
                error: "Invalid regex: \(error.localizedDescription)",
                executionTime: Date().timeIntervalSince(startTime),
                memoryUsed: nil
            )
        }
    }
    
    // MARK: - Utilities
    
    public func reset() {
        setupContext()
        executionCount = 0
    }
}

// MARK: - Code Block Parser

public struct CodeBlockParser {
    
    public struct CodeBlock {
        public let language: CodeSandbox.Language
        public let code: String
    }
    
    /// Extract code blocks from markdown-style fenced code
    public static func parse(_ text: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        for match in matches {
            let langRange = Range(match.range(at: 1), in: text)
            let codeRange = Range(match.range(at: 2), in: text)
            
            guard let codeRange = codeRange else { continue }
            
            let langStr = langRange.flatMap { String(text[$0]).lowercased() } ?? ""
            let code = String(text[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            let language: CodeSandbox.Language
            switch langStr {
            case "javascript", "js":
                language = .javascript
            case "python", "py":
                language = .python
            case "json":
                language = .json
            case "regex", "regexp":
                language = .regex
            default:
                language = .javascript // Default to JS
            }
            
            blocks.append(CodeBlock(language: language, code: code))
        }
        
        return blocks
    }
}
