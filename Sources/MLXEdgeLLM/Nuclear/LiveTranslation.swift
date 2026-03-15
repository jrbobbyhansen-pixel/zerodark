import Foundation

// MARK: - Live Translation

/// On-device translation
/// Note: Uses Apple's Translation framework on iOS 17.4+/macOS 14.4+

@MainActor
public final class LiveTranslation: ObservableObject {
    
    public static let shared = LiveTranslation()
    
    @Published public var isAvailable: Bool = false
    @Published public var supportedLanguages: [Language] = []
    
    public struct Language: Identifiable, Hashable, Sendable {
        public let id: String
        public let code: String
        public let name: String
        
        public static let english = Language(id: "en", code: "en", name: "English")
        public static let spanish = Language(id: "es", code: "es", name: "Spanish")
        public static let french = Language(id: "fr", code: "fr", name: "French")
        public static let german = Language(id: "de", code: "de", name: "German")
        public static let chinese = Language(id: "zh", code: "zh-Hans", name: "Chinese")
        public static let japanese = Language(id: "ja", code: "ja", name: "Japanese")
        
        public static let all: [Language] = [.english, .spanish, .french, .german, .chinese, .japanese]
    }
    
    private init() {
        // Translation availability depends on OS version
        #if os(iOS)
        if #available(iOS 17.4, *) {
            isAvailable = true
            supportedLanguages = Language.all
        }
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            isAvailable = true
            supportedLanguages = Language.all
        }
        #endif
    }
    
    /// Translate text using LLM (fallback when Translation framework unavailable)
    public func translate(_ text: String, from source: Language? = nil, to target: Language) async throws -> String {
        // For now, use LLM-based translation as the primary method
        // This works on all platforms
        let sourceHint = source.map { " from \($0.name)" } ?? ""
        let prompt = "Translate\(sourceHint) to \(target.name): \(text)\n\nProvide only the translation, nothing else."
        
        var response = ""
        response = try await ZeroDarkAI.shared.process(prompt: prompt, onToken: { token in
            response = token
        })
        
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public enum TranslationError: Error {
        case notAvailable
        case languageNotSupported
        case translationFailed
    }
}
