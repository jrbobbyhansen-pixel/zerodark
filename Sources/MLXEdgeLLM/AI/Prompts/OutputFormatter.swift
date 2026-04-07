import Foundation
import SwiftUI

enum OutputFormat: String, Codable {
    case json
    case markdown
    case plainText
    case structuredData
}

struct OutputFormatter {
    private let format: OutputFormat
    
    init(format: OutputFormat) {
        self.format = format
    }
    
    func formatOutput(_ data: Any) throws -> String {
        switch format {
        case .json:
            return try JSONSerialization.string(from: data)
        case .markdown:
            return formatAsMarkdown(data)
        case .plainText:
            return formatAsPlainText(data)
        case .structuredData:
            return formatAsStructuredData(data)
        }
    }
    
    private func formatAsMarkdown(_ data: Any) -> String {
        // Implement markdown formatting logic
        return "Markdown formatted data"
    }
    
    private func formatAsPlainText(_ data: Any) -> String {
        // Implement plain text formatting logic
        return "Plain text formatted data"
    }
    
    private func formatAsStructuredData(_ data: Any) -> String {
        // Implement structured data formatting logic
        return "Structured data formatted data"
    }
}

extension JSONSerialization {
    static func string(from data: Any) throws -> String {
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
        return String(data: jsonData, encoding: .utf8) ?? ""
    }
}

class OutputFormatController: ObservableObject {
    @Published var format: OutputFormat = .json
    @Published var output: String = ""
    
    private let formatter = OutputFormatter(format: .json)
    
    func updateOutput(_ data: Any) {
        do {
            output = try formatter.formatOutput(data)
        } catch {
            // Handle format error
            output = "Error formatting output: \(error.localizedDescription)"
        }
    }
    
    func changeFormat(to newFormat: OutputFormat) {
        formatter.format = newFormat
        format = newFormat
    }
}