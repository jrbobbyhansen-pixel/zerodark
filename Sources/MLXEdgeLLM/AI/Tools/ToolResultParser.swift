import Foundation
import SwiftUI

// MARK: - ToolResultParser

class ToolResultParser: ObservableObject {
    @Published var summary: String = ""
    @Published var keyInformation: [String] = []
    @Published var errors: [String] = []

    func parseResult(_ result: String) {
        summary = ""
        keyInformation = []
        errors = []

        let lines = result.split(separator: "\n")
        for line in lines {
            if line.hasPrefix("ERROR:") {
                errors.append(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("SUMMARY:") {
                summary = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("KEY:") {
                keyInformation.append(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
            }
        }
    }

    func summarizeLargeOutput(_ output: String) -> String {
        let words = output.split(separator: " ")
        if words.count > 50 {
            return String(words.prefix(50)) + "..."
        }
        return output
    }
}

// MARK: - ToolResultParserViewModel

class ToolResultParserViewModel: ObservableObject {
    @Published var result: String = ""
    @Published var parsedSummary: String = ""
    @Published var parsedKeyInformation: [String] = []
    @Published var parsedErrors: [String] = []

    private let parser = ToolResultParser()

    func parse() {
        parser.parseResult(result)
        parsedSummary = parser.summary
        parsedKeyInformation = parser.keyInformation
        parsedErrors = parser.errors
    }
}

// MARK: - ToolResultParserView

struct ToolResultParserView: View {
    @StateObject private var viewModel = ToolResultParserViewModel()

    var body: some View {
        VStack {
            Text("Tool Result Parser")
                .font(.largeTitle)
                .padding()

            TextEditor(text: $viewModel.result)
                .frame(height: 200)
                .padding()

            Button("Parse Result") {
                viewModel.parse()
            }
            .padding()

            Text("Summary: \(viewModel.parsedSummary)")
                .font(.headline)
                .padding()

            Text("Key Information:")
                .font(.headline)
                .padding()

            ForEach(viewModel.parsedKeyInformation, id: \.self) { info in
                Text("- \(info)")
            }

            Text("Errors:")
                .font(.headline)
                .padding()

            ForEach(viewModel.parsedErrors, id: \.self) { error in
                Text("- \(error)")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct ToolResultParserView_Previews: PreviewProvider {
    static var previews: some View {
        ToolResultParserView()
    }
}