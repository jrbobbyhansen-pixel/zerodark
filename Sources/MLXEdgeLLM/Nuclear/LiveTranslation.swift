import Foundation
import Translation
import NaturalLanguage

// MARK: - Live Translation

/// On-device translation using Apple Translation API
@MainActor
public final class LiveTranslation: ObservableObject {
    
    public static let shared = LiveTranslation()
    
    // MARK: - State
    
    @Published public var isAvailable: Bool = false
    @Published public var downloadedLanguages: [String] = []
    @Published public var isTranslating: Bool = false
    
    // MARK: - Supported Languages
    
    public struct Language: Identifiable, Hashable {
        public let id: String
        public let code: String
        public let name: String
        public let nativeName: String
        
        public static let english = Language(id: "en", code: "en", name: "English", nativeName: "English")
        public static let spanish = Language(id: "es", code: "es", name: "Spanish", nativeName: "Español")
        public static let french = Language(id: "fr", code: "fr", name: "French", nativeName: "Français")
        public static let german = Language(id: "de", code: "de", name: "German", nativeName: "Deutsch")
        public static let italian = Language(id: "it", code: "it", name: "Italian", nativeName: "Italiano")
        public static let portuguese = Language(id: "pt", code: "pt", name: "Portuguese", nativeName: "Português")
        public static let chinese = Language(id: "zh", code: "zh-Hans", name: "Chinese (Simplified)", nativeName: "简体中文")
        public static let japanese = Language(id: "ja", code: "ja", name: "Japanese", nativeName: "日本語")
        public static let korean = Language(id: "ko", code: "ko", name: "Korean", nativeName: "한국어")
        public static let arabic = Language(id: "ar", code: "ar", name: "Arabic", nativeName: "العربية")
        public static let russian = Language(id: "ru", code: "ru", name: "Russian", nativeName: "Русский")
        public static let hindi = Language(id: "hi", code: "hi", name: "Hindi", nativeName: "हिन्दी")
        
        public static let all: [Language] = [
            .english, .spanish, .french, .german, .italian, .portuguese,
            .chinese, .japanese, .korean, .arabic, .russian, .hindi
        ]
    }
    
    // MARK: - Init
    
    private init() {
        checkAvailability()
    }
    
    private func checkAvailability() {
        // Translation API available in iOS 17.4+, macOS 14.4+
        if #available(iOS 17.4, macOS 14.4, *) {
            isAvailable = true
        } else {
            isAvailable = false
        }
    }
    
    // MARK: - Translate
    
    @available(iOS 17.4, macOS 14.4, *)
    public func translate(
        _ text: String,
        from source: Language? = nil,
        to target: Language
    ) async throws -> String {
        isTranslating = true
        defer { isTranslating = false }
        
        // Detect source language if not specified
        let sourceLocale: Locale.Language
        if let source = source {
            sourceLocale = Locale.Language(identifier: source.code)
        } else {
            let detected = detectLanguage(text)
            sourceLocale = Locale.Language(identifier: detected ?? "en")
        }
        
        let targetLocale = Locale.Language(identifier: target.code)
        
        let session = try TranslationSession(
            sourceLanguage: sourceLocale,
            targetLanguage: targetLocale
        )
        
        let response = try await session.translate(text)
        return response.targetText
    }
    
    // MARK: - Batch Translate
    
    @available(iOS 17.4, macOS 14.4, *)
    public func translateBatch(
        _ texts: [String],
        from source: Language? = nil,
        to target: Language
    ) async throws -> [String] {
        var results: [String] = []
        
        for text in texts {
            let translated = try await translate(text, from: source, to: target)
            results.append(translated)
        }
        
        return results
    }
    
    // MARK: - Language Detection
    
    public func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        guard let language = recognizer.dominantLanguage else {
            return nil
        }
        
        return language.rawValue
    }
    
    public func detectLanguageWithConfidence(_ text: String) -> [(language: String, confidence: Double)] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        
        return hypotheses.map { (language, confidence) in
            (language.rawValue, confidence)
        }.sorted { $0.confidence > $1.confidence }
    }
    
    // MARK: - Conversation Mode
    
    public struct ConversationMessage {
        public let original: String
        public let translated: String
        public let sourceLanguage: String
        public let targetLanguage: String
        public let timestamp: Date
    }
    
    @available(iOS 17.4, macOS 14.4, *)
    public func conversationTranslate(
        _ text: String,
        userLanguage: Language,
        partnerLanguage: Language
    ) async throws -> ConversationMessage {
        // Detect which language the input is in
        let detected = detectLanguage(text)
        
        let isUserSpeaking = detected == userLanguage.code || detected == nil
        
        let (source, target) = isUserSpeaking 
            ? (userLanguage, partnerLanguage) 
            : (partnerLanguage, userLanguage)
        
        let translated = try await translate(text, from: source, to: target)
        
        return ConversationMessage(
            original: text,
            translated: translated,
            sourceLanguage: source.name,
            targetLanguage: target.name,
            timestamp: Date()
        )
    }
}

// MARK: - Text Processing

public extension LiveTranslation {
    
    /// Clean text for better translation
    func preprocessText(_ text: String) -> String {
        // Remove excessive whitespace
        let cleaned = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return cleaned
    }
    
    /// Split long text into translatable chunks
    func chunkText(_ text: String, maxLength: Int = 5000) -> [String] {
        guard text.count > maxLength else {
            return [text]
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if currentChunk.count + trimmed.count + 2 > maxLength {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                }
                currentChunk = trimmed + ". "
            } else {
                currentChunk += trimmed + ". "
            }
        }
        
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        return chunks
    }
}

// MARK: - Phrasebook

public extension LiveTranslation {
    
    struct Phrase: Identifiable {
        public let id = UUID()
        public let category: String
        public let english: String
        public var translations: [String: String] = [:]
    }
    
    static let commonPhrases: [Phrase] = [
        // Greetings
        Phrase(category: "Greetings", english: "Hello"),
        Phrase(category: "Greetings", english: "Good morning"),
        Phrase(category: "Greetings", english: "Good evening"),
        Phrase(category: "Greetings", english: "How are you?"),
        Phrase(category: "Greetings", english: "Nice to meet you"),
        Phrase(category: "Greetings", english: "Goodbye"),
        
        // Essentials
        Phrase(category: "Essentials", english: "Yes"),
        Phrase(category: "Essentials", english: "No"),
        Phrase(category: "Essentials", english: "Please"),
        Phrase(category: "Essentials", english: "Thank you"),
        Phrase(category: "Essentials", english: "You're welcome"),
        Phrase(category: "Essentials", english: "Excuse me"),
        Phrase(category: "Essentials", english: "I'm sorry"),
        
        // Questions
        Phrase(category: "Questions", english: "Where is...?"),
        Phrase(category: "Questions", english: "How much does this cost?"),
        Phrase(category: "Questions", english: "Do you speak English?"),
        Phrase(category: "Questions", english: "Can you help me?"),
        Phrase(category: "Questions", english: "What time is it?"),
        
        // Emergency
        Phrase(category: "Emergency", english: "Help!"),
        Phrase(category: "Emergency", english: "I need a doctor"),
        Phrase(category: "Emergency", english: "Call the police"),
        Phrase(category: "Emergency", english: "Where is the hospital?"),
        
        // Travel
        Phrase(category: "Travel", english: "Where is the bathroom?"),
        Phrase(category: "Travel", english: "I would like to order..."),
        Phrase(category: "Travel", english: "The check, please"),
        Phrase(category: "Travel", english: "How do I get to...?"),
    ]
}
