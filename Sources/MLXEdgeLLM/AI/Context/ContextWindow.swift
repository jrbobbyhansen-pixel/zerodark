import Foundation

// MARK: - ContextWindow

final class ContextWindow: ObservableObject {
    @Published private(set) var tokens: [Token] = []
    private let maxTokens: Int
    private let summaryService: SummaryService

    init(maxTokens: Int, summaryService: SummaryService) {
        self.maxTokens = maxTokens
        self.summaryService = summaryService
    }

    func addToken(_ token: Token) {
        tokens.append(token)
        if tokens.count > maxTokens {
            summarizeAndTrim()
        }
    }

    private func summarizeAndTrim() {
        let summary = summaryService.summarize(tokens)
        tokens = [summary]
    }
}

// MARK: - Token

struct Token: Identifiable {
    let id = UUID()
    let content: String
    let priority: Int
}

// MARK: - SummaryService

protocol SummaryService {
    func summarize(_ tokens: [Token]) -> Token
}

// MARK: - DefaultSummaryService

final class DefaultSummaryService: SummaryService {
    func summarize(_ tokens: [Token]) -> Token {
        let summaryContent = tokens.map { $0.content }.joined(separator: " ")
        return Token(content: summaryContent, priority: 0)
    }
}