import Foundation
import EventKit
import Contacts
import CryptoKit
#if os(iOS)
import UIKit
#endif

// MARK: - Agentic Tool System

/// Function calling / tool use for on-device AI
public actor AgentToolkit {
    
    public static let shared = AgentToolkit()
    
    // MARK: - Tool Definition
    
    public struct Tool: Codable, Sendable {
        public let name: String
        public let description: String
        public let parameters: [Parameter]
        public let handler: String // Internal handler ID
        
        public struct Parameter: Codable, Sendable {
            public let name: String
            public let type: String
            public let description: String
            public let required: Bool
            public let enumValues: [String]?
        }
    }
    
    public struct ToolCall: Codable, Sendable {
        public let tool: String
        public let arguments: [String: String]
        
        public init(tool: String, arguments: [String: String]) {
            self.tool = tool
            self.arguments = arguments
        }
    }
    
    public struct ToolResult: Sendable {
        public let success: Bool
        public let output: String
        public let data: [String: Any]?
        
        public var asPromptContext: String {
            if success {
                return "Tool '\(output)' returned: \(output)"
            } else {
                return "Tool failed: \(output)"
            }
        }
    }
    
    // MARK: - Available Tools
    
    public var tools: [Tool] {
        [
            calculatorTool,
            dateTimeTool,
            reminderTool,
            timerTool,
            unitConverterTool,
            randomNumberTool,
            hashTool,
            base64Tool,
            jsonTool,
            regexTool,
            weatherTool,
            searchContactsTool,
            fileSearchTool,
            clipboardTool,
            systemInfoTool
        ]
    }
    
    // MARK: - Tool Definitions
    
    private var calculatorTool: Tool {
        Tool(
            name: "calculator",
            description: "Perform mathematical calculations. Supports basic arithmetic, exponents, roots, trig functions.",
            parameters: [
                .init(name: "expression", type: "string", description: "Math expression to evaluate (e.g., '2 + 2', 'sqrt(16)', 'sin(45)')", required: true, enumValues: nil)
            ],
            handler: "calculator"
        )
    }
    
    private var dateTimeTool: Tool {
        Tool(
            name: "datetime",
            description: "Get current date, time, or perform date calculations.",
            parameters: [
                .init(name: "action", type: "string", description: "Action to perform", required: true, enumValues: ["now", "format", "add", "diff", "timezone"]),
                .init(name: "date", type: "string", description: "Date string (ISO 8601)", required: false, enumValues: nil),
                .init(name: "format", type: "string", description: "Output format", required: false, enumValues: nil),
                .init(name: "amount", type: "string", description: "Amount to add (e.g., '7 days', '2 hours')", required: false, enumValues: nil)
            ],
            handler: "datetime"
        )
    }
    
    private var reminderTool: Tool {
        Tool(
            name: "reminder",
            description: "Create reminders in Apple Reminders app.",
            parameters: [
                .init(name: "title", type: "string", description: "Reminder title", required: true, enumValues: nil),
                .init(name: "due", type: "string", description: "Due date/time (natural language: 'tomorrow 3pm', 'next Monday')", required: false, enumValues: nil),
                .init(name: "notes", type: "string", description: "Additional notes", required: false, enumValues: nil),
                .init(name: "list", type: "string", description: "Reminder list name", required: false, enumValues: nil)
            ],
            handler: "reminder"
        )
    }
    
    private var timerTool: Tool {
        Tool(
            name: "timer",
            description: "Set a timer or stopwatch.",
            parameters: [
                .init(name: "action", type: "string", description: "Action", required: true, enumValues: ["start", "stop", "check"]),
                .init(name: "duration", type: "string", description: "Duration (e.g., '5 minutes', '1 hour 30 minutes')", required: false, enumValues: nil),
                .init(name: "label", type: "string", description: "Timer label", required: false, enumValues: nil)
            ],
            handler: "timer"
        )
    }
    
    private var unitConverterTool: Tool {
        Tool(
            name: "convert",
            description: "Convert between units (length, weight, temperature, currency, etc.).",
            parameters: [
                .init(name: "value", type: "number", description: "Value to convert", required: true, enumValues: nil),
                .init(name: "from", type: "string", description: "Source unit (e.g., 'km', 'fahrenheit', 'USD')", required: true, enumValues: nil),
                .init(name: "to", type: "string", description: "Target unit (e.g., 'miles', 'celsius', 'EUR')", required: true, enumValues: nil)
            ],
            handler: "convert"
        )
    }
    
    private var randomNumberTool: Tool {
        Tool(
            name: "random",
            description: "Generate random numbers, UUIDs, or pick random items.",
            parameters: [
                .init(name: "type", type: "string", description: "Type of random", required: true, enumValues: ["integer", "float", "uuid", "pick"]),
                .init(name: "min", type: "number", description: "Minimum value (for integer/float)", required: false, enumValues: nil),
                .init(name: "max", type: "number", description: "Maximum value (for integer/float)", required: false, enumValues: nil),
                .init(name: "items", type: "string", description: "Comma-separated items to pick from", required: false, enumValues: nil)
            ],
            handler: "random"
        )
    }
    
    private var hashTool: Tool {
        Tool(
            name: "hash",
            description: "Generate cryptographic hashes.",
            parameters: [
                .init(name: "text", type: "string", description: "Text to hash", required: true, enumValues: nil),
                .init(name: "algorithm", type: "string", description: "Hash algorithm", required: false, enumValues: ["md5", "sha1", "sha256", "sha512"])
            ],
            handler: "hash"
        )
    }
    
    private var base64Tool: Tool {
        Tool(
            name: "base64",
            description: "Encode or decode Base64.",
            parameters: [
                .init(name: "action", type: "string", description: "Action", required: true, enumValues: ["encode", "decode"]),
                .init(name: "text", type: "string", description: "Text to encode/decode", required: true, enumValues: nil)
            ],
            handler: "base64"
        )
    }
    
    private var jsonTool: Tool {
        Tool(
            name: "json",
            description: "Parse, format, or query JSON data.",
            parameters: [
                .init(name: "action", type: "string", description: "Action", required: true, enumValues: ["parse", "format", "query"]),
                .init(name: "data", type: "string", description: "JSON data", required: true, enumValues: nil),
                .init(name: "path", type: "string", description: "JSONPath query (for query action)", required: false, enumValues: nil)
            ],
            handler: "json"
        )
    }
    
    private var regexTool: Tool {
        Tool(
            name: "regex",
            description: "Match, extract, or replace using regular expressions.",
            parameters: [
                .init(name: "action", type: "string", description: "Action", required: true, enumValues: ["match", "extract", "replace"]),
                .init(name: "pattern", type: "string", description: "Regex pattern", required: true, enumValues: nil),
                .init(name: "text", type: "string", description: "Text to process", required: true, enumValues: nil),
                .init(name: "replacement", type: "string", description: "Replacement (for replace action)", required: false, enumValues: nil)
            ],
            handler: "regex"
        )
    }
    
    private var weatherTool: Tool {
        Tool(
            name: "weather",
            description: "Get weather using Apple WeatherKit (requires network).",
            parameters: [
                .init(name: "location", type: "string", description: "City or address", required: true, enumValues: nil),
                .init(name: "type", type: "string", description: "Forecast type", required: false, enumValues: ["current", "hourly", "daily"])
            ],
            handler: "weather"
        )
    }
    
    private var searchContactsTool: Tool {
        Tool(
            name: "contacts",
            description: "Search contacts by name, phone, or email.",
            parameters: [
                .init(name: "query", type: "string", description: "Search query (name, phone, or email)", required: true, enumValues: nil)
            ],
            handler: "contacts"
        )
    }
    
    private var fileSearchTool: Tool {
        Tool(
            name: "files",
            description: "Search files in Documents folder.",
            parameters: [
                .init(name: "query", type: "string", description: "Filename search query", required: true, enumValues: nil),
                .init(name: "extension", type: "string", description: "File extension filter (e.g., 'pdf', 'txt')", required: false, enumValues: nil)
            ],
            handler: "files"
        )
    }
    
    private var clipboardTool: Tool {
        Tool(
            name: "clipboard",
            description: "Read from or write to system clipboard.",
            parameters: [
                .init(name: "action", type: "string", description: "Action", required: true, enumValues: ["read", "write"]),
                .init(name: "text", type: "string", description: "Text to copy (for write action)", required: false, enumValues: nil)
            ],
            handler: "clipboard"
        )
    }
    
    private var systemInfoTool: Tool {
        Tool(
            name: "system",
            description: "Get device/system information.",
            parameters: [
                .init(name: "info", type: "string", description: "Information type", required: true, enumValues: ["device", "battery", "storage", "memory", "network"])
            ],
            handler: "system"
        )
    }
    
    // MARK: - Tool Execution
    
    public func execute(_ call: ToolCall) async -> ToolResult {
        switch call.tool {
        case "calculator":
            return executeCalculator(call.arguments)
        case "datetime":
            return executeDateTime(call.arguments)
        case "reminder":
            return await executeReminder(call.arguments)
        case "timer":
            return executeTimer(call.arguments)
        case "convert":
            return executeConvert(call.arguments)
        case "random":
            return executeRandom(call.arguments)
        case "hash":
            return executeHash(call.arguments)
        case "base64":
            return executeBase64(call.arguments)
        case "json":
            return executeJSON(call.arguments)
        case "regex":
            return executeRegex(call.arguments)
        case "clipboard":
            return await executeClipboard(call.arguments)
        case "system":
            return executeSystem(call.arguments)
        default:
            return ToolResult(success: false, output: "Unknown tool: \(call.tool)", data: nil)
        }
    }
    
    // MARK: - Tool Implementations
    
    private func executeCalculator(_ args: [String: String]) -> ToolResult {
        guard let expression = args["expression"] else {
            return ToolResult(success: false, output: "Missing expression", data: nil)
        }
        
        // Use NSExpression for basic math
        let sanitized = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^", with: "**")
        
        // Handle common functions
        var processedExpr = sanitized
        let functions = [
            ("sqrt", { (x: Double) in sqrt(x) }),
            ("sin", { (x: Double) in sin(x * .pi / 180) }),
            ("cos", { (x: Double) in cos(x * .pi / 180) }),
            ("tan", { (x: Double) in tan(x * .pi / 180) }),
            ("log", { (x: Double) in log10(x) }),
            ("ln", { (x: Double) in log(x) }),
            ("abs", { (x: Double) in abs(x) })
        ]
        
        // Try NSExpression first
        do {
            let expr = NSExpression(format: processedExpr)
            if let result = expr.expressionValue(with: nil, context: nil) as? NSNumber {
                let value = result.doubleValue
                let formatted = value.truncatingRemainder(dividingBy: 1) == 0 
                    ? String(format: "%.0f", value) 
                    : String(format: "%.6g", value)
                return ToolResult(success: true, output: formatted, data: ["result": value])
            }
        } catch {
            // Fall through to error
        }
        
        return ToolResult(success: false, output: "Could not evaluate: \(expression)", data: nil)
    }
    
    private func executeDateTime(_ args: [String: String]) -> ToolResult {
        let action = args["action"] ?? "now"
        let formatter = ISO8601DateFormatter()
        
        switch action {
        case "now":
            let now = Date()
            let display = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .medium)
            return ToolResult(success: true, output: display, data: ["iso": formatter.string(from: now)])
            
        case "format":
            guard let dateStr = args["date"] else {
                return ToolResult(success: false, output: "Missing date", data: nil)
            }
            guard let date = formatter.date(from: dateStr) else {
                return ToolResult(success: false, output: "Invalid date format", data: nil)
            }
            let display = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .medium)
            return ToolResult(success: true, output: display, data: nil)
            
        case "add":
            let baseDate = args["date"].flatMap { formatter.date(from: $0) } ?? Date()
            guard let amount = args["amount"] else {
                return ToolResult(success: false, output: "Missing amount", data: nil)
            }
            
            // Parse amount like "7 days" or "2 hours"
            let components = amount.lowercased().split(separator: " ")
            guard components.count == 2,
                  let value = Int(components[0]) else {
                return ToolResult(success: false, output: "Invalid amount format", data: nil)
            }
            
            let unit = String(components[1])
            var dateComponents = DateComponents()
            
            switch unit {
            case "second", "seconds": dateComponents.second = value
            case "minute", "minutes": dateComponents.minute = value
            case "hour", "hours": dateComponents.hour = value
            case "day", "days": dateComponents.day = value
            case "week", "weeks": dateComponents.day = value * 7
            case "month", "months": dateComponents.month = value
            case "year", "years": dateComponents.year = value
            default:
                return ToolResult(success: false, output: "Unknown unit: \(unit)", data: nil)
            }
            
            guard let newDate = Calendar.current.date(byAdding: dateComponents, to: baseDate) else {
                return ToolResult(success: false, output: "Could not calculate date", data: nil)
            }
            
            let display = DateFormatter.localizedString(from: newDate, dateStyle: .full, timeStyle: .medium)
            return ToolResult(success: true, output: display, data: ["iso": formatter.string(from: newDate)])
            
        default:
            return ToolResult(success: false, output: "Unknown action: \(action)", data: nil)
        }
    }
    
    private func executeReminder(_ args: [String: String]) async -> ToolResult {
        guard let title = args["title"] else {
            return ToolResult(success: false, output: "Missing title", data: nil)
        }
        
        let store = EKEventStore()
        
        // Request access
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else {
                return ToolResult(success: false, output: "Reminders access denied", data: nil)
            }
        } catch {
            return ToolResult(success: false, output: "Failed to request access: \(error.localizedDescription)", data: nil)
        }
        
        // Create reminder
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = args["notes"]
        
        // Set calendar (list)
        if let listName = args["list"] {
            let calendars = store.calendars(for: .reminder)
            if let calendar = calendars.first(where: { $0.title.lowercased() == listName.lowercased() }) {
                reminder.calendar = calendar
            }
        }
        
        if reminder.calendar == nil {
            reminder.calendar = store.defaultCalendarForNewReminders()
        }
        
        // Parse due date
        if let dueString = args["due"] {
            // Simple natural language parsing
            let now = Date()
            var dueDate: Date?
            
            let lower = dueString.lowercased()
            if lower.contains("tomorrow") {
                dueDate = Calendar.current.date(byAdding: .day, value: 1, to: now)
            } else if lower.contains("next week") {
                dueDate = Calendar.current.date(byAdding: .day, value: 7, to: now)
            } else if lower.contains("hour") {
                if let hours = Int(lower.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    dueDate = Calendar.current.date(byAdding: .hour, value: hours, to: now)
                }
            }
            
            if let date = dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            }
        }
        
        do {
            try store.save(reminder, commit: true)
            return ToolResult(success: true, output: "Created reminder: \(title)", data: ["id": reminder.calendarItemIdentifier])
        } catch {
            return ToolResult(success: false, output: "Failed to save: \(error.localizedDescription)", data: nil)
        }
    }
    
    private var activeTimers: [String: Date] = [:]
    
    private func executeTimer(_ args: [String: String]) -> ToolResult {
        let action = args["action"] ?? "check"
        let label = args["label"] ?? "default"
        
        switch action {
        case "start":
            activeTimers[label] = Date()
            return ToolResult(success: true, output: "Timer '\(label)' started", data: nil)
            
        case "stop":
            guard let start = activeTimers[label] else {
                return ToolResult(success: false, output: "No active timer '\(label)'", data: nil)
            }
            let elapsed = Date().timeIntervalSince(start)
            activeTimers.removeValue(forKey: label)
            
            let formatted = formatDuration(elapsed)
            return ToolResult(success: true, output: "Timer '\(label)' stopped: \(formatted)", data: ["seconds": elapsed])
            
        case "check":
            guard let start = activeTimers[label] else {
                return ToolResult(success: false, output: "No active timer '\(label)'", data: nil)
            }
            let elapsed = Date().timeIntervalSince(start)
            let formatted = formatDuration(elapsed)
            return ToolResult(success: true, output: "Timer '\(label)': \(formatted)", data: ["seconds": elapsed])
            
        default:
            return ToolResult(success: false, output: "Unknown action: \(action)", data: nil)
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func executeConvert(_ args: [String: String]) -> ToolResult {
        guard let valueStr = args["value"],
              let value = Double(valueStr),
              let from = args["from"]?.lowercased(),
              let to = args["to"]?.lowercased() else {
            return ToolResult(success: false, output: "Missing or invalid arguments", data: nil)
        }
        
        // Length conversions
        let lengthToMeters: [String: Double] = [
            "m": 1, "meter": 1, "meters": 1,
            "km": 1000, "kilometer": 1000, "kilometers": 1000,
            "cm": 0.01, "centimeter": 0.01, "centimeters": 0.01,
            "mm": 0.001, "millimeter": 0.001, "millimeters": 0.001,
            "mi": 1609.344, "mile": 1609.344, "miles": 1609.344,
            "ft": 0.3048, "foot": 0.3048, "feet": 0.3048,
            "in": 0.0254, "inch": 0.0254, "inches": 0.0254,
            "yd": 0.9144, "yard": 0.9144, "yards": 0.9144
        ]
        
        // Weight conversions
        let weightToKg: [String: Double] = [
            "kg": 1, "kilogram": 1, "kilograms": 1,
            "g": 0.001, "gram": 0.001, "grams": 0.001,
            "mg": 0.000001, "milligram": 0.000001,
            "lb": 0.453592, "pound": 0.453592, "pounds": 0.453592,
            "oz": 0.0283495, "ounce": 0.0283495, "ounces": 0.0283495
        ]
        
        // Check length
        if let fromFactor = lengthToMeters[from], let toFactor = lengthToMeters[to] {
            let result = value * fromFactor / toFactor
            return ToolResult(success: true, output: String(format: "%.4g %@ = %.4g %@", value, from, result, to), data: ["result": result])
        }
        
        // Check weight
        if let fromFactor = weightToKg[from], let toFactor = weightToKg[to] {
            let result = value * fromFactor / toFactor
            return ToolResult(success: true, output: String(format: "%.4g %@ = %.4g %@", value, from, result, to), data: ["result": result])
        }
        
        // Temperature
        if (from == "celsius" || from == "c") && (to == "fahrenheit" || to == "f") {
            let result = value * 9/5 + 32
            return ToolResult(success: true, output: String(format: "%.1f°C = %.1f°F", value, result), data: ["result": result])
        }
        if (from == "fahrenheit" || from == "f") && (to == "celsius" || to == "c") {
            let result = (value - 32) * 5/9
            return ToolResult(success: true, output: String(format: "%.1f°F = %.1f°C", value, result), data: ["result": result])
        }
        
        return ToolResult(success: false, output: "Cannot convert from \(from) to \(to)", data: nil)
    }
    
    private func executeRandom(_ args: [String: String]) -> ToolResult {
        let type = args["type"] ?? "integer"
        
        switch type {
        case "integer":
            let min = Int(args["min"] ?? "1") ?? 1
            let max = Int(args["max"] ?? "100") ?? 100
            let result = Int.random(in: min...max)
            return ToolResult(success: true, output: "\(result)", data: ["result": result])
            
        case "float":
            let min = Double(args["min"] ?? "0") ?? 0
            let max = Double(args["max"] ?? "1") ?? 1
            let result = Double.random(in: min...max)
            return ToolResult(success: true, output: String(format: "%.6f", result), data: ["result": result])
            
        case "uuid":
            let uuid = UUID().uuidString
            return ToolResult(success: true, output: uuid, data: ["uuid": uuid])
            
        case "pick":
            guard let items = args["items"]?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }),
                  !items.isEmpty else {
                return ToolResult(success: false, output: "No items to pick from", data: nil)
            }
            let picked = items.randomElement()!
            return ToolResult(success: true, output: picked, data: ["picked": picked])
            
        default:
            return ToolResult(success: false, output: "Unknown type: \(type)", data: nil)
        }
    }
    
    private func executeHash(_ args: [String: String]) -> ToolResult {
        guard let text = args["text"] else {
            return ToolResult(success: false, output: "Missing text", data: nil)
        }
        
        let algorithm = args["algorithm"] ?? "sha256"
        let data = Data(text.utf8)
        
        // Use CryptoKit for hashing
        let hash: String
        switch algorithm {
        case "sha256":
            hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha512":
            hash = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha1":
            hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "md5":
            hash = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        default:
            return ToolResult(success: false, output: "Unknown algorithm: \(algorithm)", data: nil)
        }
        
        return ToolResult(success: true, output: hash, data: ["hash": hash, "algorithm": algorithm])
    }
    
    private func executeBase64(_ args: [String: String]) -> ToolResult {
        guard let action = args["action"],
              let text = args["text"] else {
            return ToolResult(success: false, output: "Missing arguments", data: nil)
        }
        
        switch action {
        case "encode":
            let encoded = Data(text.utf8).base64EncodedString()
            return ToolResult(success: true, output: encoded, data: nil)
            
        case "decode":
            guard let data = Data(base64Encoded: text),
                  let decoded = String(data: data, encoding: .utf8) else {
                return ToolResult(success: false, output: "Invalid Base64", data: nil)
            }
            return ToolResult(success: true, output: decoded, data: nil)
            
        default:
            return ToolResult(success: false, output: "Unknown action: \(action)", data: nil)
        }
    }
    
    private func executeJSON(_ args: [String: String]) -> ToolResult {
        guard let data = args["data"] else {
            return ToolResult(success: false, output: "Missing data", data: nil)
        }
        
        let action = args["action"] ?? "parse"
        
        switch action {
        case "parse", "format":
            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData),
                  let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                  let output = String(data: formatted, encoding: .utf8) else {
                return ToolResult(success: false, output: "Invalid JSON", data: nil)
            }
            return ToolResult(success: true, output: output, data: nil)
            
        default:
            return ToolResult(success: false, output: "Unknown action: \(action)", data: nil)
        }
    }
    
    private func executeRegex(_ args: [String: String]) -> ToolResult {
        guard let pattern = args["pattern"],
              let text = args["text"],
              let action = args["action"] else {
            return ToolResult(success: false, output: "Missing arguments", data: nil)
        }
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ToolResult(success: false, output: "Invalid regex pattern", data: nil)
        }
        
        let range = NSRange(text.startIndex..., in: text)
        
        switch action {
        case "match":
            let matches = regex.matches(in: text, range: range)
            let found = !matches.isEmpty
            return ToolResult(success: true, output: found ? "Match found (\(matches.count) occurrences)" : "No match", data: ["count": matches.count])
            
        case "extract":
            let matches = regex.matches(in: text, range: range)
            let extracted = matches.compactMap { match -> String? in
                guard let range = Range(match.range, in: text) else { return nil }
                return String(text[range])
            }
            return ToolResult(success: true, output: extracted.joined(separator: ", "), data: ["matches": extracted])
            
        case "replace":
            guard let replacement = args["replacement"] else {
                return ToolResult(success: false, output: "Missing replacement", data: nil)
            }
            let result = regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
            return ToolResult(success: true, output: result, data: nil)
            
        default:
            return ToolResult(success: false, output: "Unknown action: \(action)", data: nil)
        }
    }
    
    @MainActor
    private func executeClipboard(_ args: [String: String]) async -> ToolResult {
        #if os(iOS)
        let action = args["action"] ?? "read"
        
        switch action {
        case "read":
            let content = UIPasteboard.general.string ?? ""
            return ToolResult(success: true, output: content.isEmpty ? "(clipboard empty)" : content, data: nil)
            
        case "write":
            guard let text = args["text"] else {
                return ToolResult(success: false, output: "Missing text", data: nil)
            }
            UIPasteboard.general.string = text
            return ToolResult(success: true, output: "Copied to clipboard", data: nil)
            
        default:
            return ToolResult(success: false, output: "Unknown action: \(action)", data: nil)
        }
        #else
        return ToolResult(success: false, output: "Clipboard not available on this platform", data: nil)
        #endif
    }
    
    private func executeSystem(_ args: [String: String]) -> ToolResult {
        let info = args["info"] ?? "device"
        
        switch info {
        case "device":
            #if os(iOS)
            let device = UIDevice.current
            let output = """
            Model: \(device.model)
            Name: \(device.name)
            System: \(device.systemName) \(device.systemVersion)
            """
            return ToolResult(success: true, output: output, data: nil)
            #else
            return ToolResult(success: true, output: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", data: nil)
            #endif
            
        case "battery":
            #if os(iOS)
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = Int(UIDevice.current.batteryLevel * 100)
            let state: String
            switch UIDevice.current.batteryState {
            case .charging: state = "Charging"
            case .full: state = "Full"
            case .unplugged: state = "Unplugged"
            default: state = "Unknown"
            }
            return ToolResult(success: true, output: "\(level)% (\(state))", data: ["level": level, "state": state])
            #else
            return ToolResult(success: false, output: "Battery info not available on macOS", data: nil)
            #endif
            
        case "memory":
            let info = ProcessInfo.processInfo
            let physical = info.physicalMemory / (1024 * 1024 * 1024)
            return ToolResult(success: true, output: "\(physical) GB RAM", data: ["gb": physical])
            
        case "storage":
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            if let path = paths.first,
               let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path.path),
               let free = attrs[.systemFreeSize] as? Int64 {
                let freeGB = Double(free) / (1024 * 1024 * 1024)
                return ToolResult(success: true, output: String(format: "%.1f GB free", freeGB), data: ["freeGB": freeGB])
            }
            return ToolResult(success: false, output: "Could not get storage info", data: nil)
            
        default:
            return ToolResult(success: false, output: "Unknown info type: \(info)", data: nil)
        }
    }
    
    // MARK: - Prompt Generation
    
    /// Generate tool descriptions for the model prompt
    public func generateToolsPrompt() -> String {
        var prompt = "You have access to the following tools:\n\n"
        
        for tool in tools {
            prompt += "### \(tool.name)\n"
            prompt += "\(tool.description)\n"
            prompt += "Parameters:\n"
            for param in tool.parameters {
                let required = param.required ? "(required)" : "(optional)"
                prompt += "- \(param.name) \(required): \(param.description)"
                if let enums = param.enumValues {
                    prompt += " [options: \(enums.joined(separator: ", "))]"
                }
                prompt += "\n"
            }
            prompt += "\n"
        }
        
        prompt += """
        
        To use a tool, respond with:
        <tool_call>
        {"tool": "tool_name", "arguments": {"param1": "value1", "param2": "value2"}}
        </tool_call>
        
        After I execute the tool, I'll provide the result and you can continue your response.
        """
        
        return prompt
    }
    
    /// Parse tool calls from model output
    public func parseToolCalls(from response: String) -> [ToolCall] {
        var calls: [ToolCall] = []
        
        let pattern = "<tool_call>\\s*([\\s\\S]*?)\\s*</tool_call>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let range = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, range: range)
        
        for match in matches {
            guard let jsonRange = Range(match.range(at: 1), in: response) else { continue }
            let jsonStr = String(response[jsonRange])
            
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONDecoder().decode(ToolCall.self, from: data) else {
                continue
            }
            
            calls.append(json)
        }
        
        return calls
    }
}
