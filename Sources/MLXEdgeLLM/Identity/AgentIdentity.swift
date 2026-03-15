// AgentIdentity.swift
// Give your AI a name, personality, and voice
// Make it YOURS

import Foundation
import AVFoundation

// MARK: - Agent Identity

/// Customizable AI agent identity
public actor AgentIdentity {
    
    public static let shared = AgentIdentity()
    
    // MARK: - Identity Configuration
    
    public struct Identity: Codable, Sendable {
        /// The agent's name (e.g., "Jarvis", "Friday", "Max")
        public var name: String = "Zero Dark"
        
        /// Wake word/phrase (e.g., "Hey Jarvis")
        public var wakePhrase: String = "Hey Zero Dark"
        
        /// Personality type
        public var personality: Personality = .professional
        
        /// Voice configuration
        public var voice: VoiceConfig = .init()
        
        /// Avatar/icon
        public var avatarEmoji: String = "🤖"
        
        /// Custom system prompt additions
        public var personalityPrompt: String = ""
        
        /// Preferred response style
        public var responseStyle: ResponseStyle = .balanced
        
        public init() {}
        
        public init(name: String, personality: Personality = .professional) {
            self.name = name
            self.wakePhrase = "Hey \(name)"
            self.personality = personality
        }
    }
    
    public enum Personality: String, Codable, CaseIterable, Sendable {
        case professional = "Professional"      // Formal, efficient
        case friendly = "Friendly"              // Warm, conversational
        case witty = "Witty"                    // Clever, humorous
        case concise = "Concise"                // Minimal, direct
        case enthusiastic = "Enthusiastic"      // Energetic, supportive
        case calm = "Calm"                      // Soothing, measured
        case sarcastic = "Sarcastic"            // Dry humor (use carefully)
        case custom = "Custom"                  // User-defined
        
        public var systemPromptAddition: String {
            switch self {
            case .professional:
                return "You are professional, efficient, and formal. Prioritize accuracy and clarity."
            case .friendly:
                return "You are warm, conversational, and approachable. Use casual language and show genuine interest."
            case .witty:
                return "You are clever and humorous. Include subtle wit and wordplay when appropriate."
            case .concise:
                return "You are minimal and direct. Give the shortest effective answer. No fluff."
            case .enthusiastic:
                return "You are energetic and supportive! Show excitement and encouragement."
            case .calm:
                return "You are soothing and measured. Speak slowly and thoughtfully. Reduce anxiety."
            case .sarcastic:
                return "You have dry humor and light sarcasm. Be playful but never mean."
            case .custom:
                return "" // User defines this
            }
        }
    }
    
    public enum ResponseStyle: String, Codable, CaseIterable, Sendable {
        case brief = "Brief"           // 1-2 sentences
        case balanced = "Balanced"     // 2-4 sentences  
        case detailed = "Detailed"     // Full explanations
        case conversational = "Chat"   // Back-and-forth style
    }
    
    // MARK: - Voice Configuration
    
    public struct VoiceConfig: Codable, Sendable {
        /// Voice type
        public var voiceType: VoiceType = .system
        
        /// System voice identifier (for Apple voices)
        public var systemVoiceID: String?
        
        /// Voice speed (0.5 - 2.0, default 1.0)
        public var speed: Float = 1.0
        
        /// Voice pitch adjustment (-1.0 to 1.0)
        public var pitch: Float = 0.0
        
        /// Use Personal Voice if available (iOS 17+)
        public var usePersonalVoice: Bool = false
        
        /// Custom voice model path (for cloned voices)
        public var customVoiceModelPath: String?
        
        public init() {}
    }
    
    public enum VoiceType: String, Codable, CaseIterable, Sendable {
        case system = "System Voice"           // Apple's built-in voices
        case personal = "Personal Voice"       // User's cloned voice (iOS 17+)
        case custom = "Custom Voice"           // Third-party or trained voice
        case none = "No Voice"                 // Text only
    }
    
    // MARK: - State
    
    private var currentIdentity: Identity = Identity()
    private let storageKey = "zerodark_agent_identity"
    
    private init() {
        Task {
            await loadIdentity()
        }
    }
    
    // MARK: - Public API
    
    /// Get the current agent identity
    public func getIdentity() -> Identity {
        return currentIdentity
    }
    
    /// Update the agent identity
    public func setIdentity(_ identity: Identity) async {
        currentIdentity = identity
        await saveIdentity()
    }
    
    /// Update just the name
    public func setName(_ name: String) async {
        currentIdentity.name = name
        currentIdentity.wakePhrase = "Hey \(name)"
        await saveIdentity()
    }
    
    /// Update the personality
    public func setPersonality(_ personality: Personality) async {
        currentIdentity.personality = personality
        await saveIdentity()
    }
    
    /// Update voice settings
    public func setVoice(_ voice: VoiceConfig) async {
        currentIdentity.voice = voice
        await saveIdentity()
    }
    
    /// Get system prompt with personality
    public func getSystemPrompt() -> String {
        var prompt = "Your name is \(currentIdentity.name). "
        
        if currentIdentity.personality == .custom {
            prompt += currentIdentity.personalityPrompt
        } else {
            prompt += currentIdentity.personality.systemPromptAddition
        }
        
        switch currentIdentity.responseStyle {
        case .brief:
            prompt += " Keep responses to 1-2 sentences maximum."
        case .balanced:
            prompt += " Give balanced responses of 2-4 sentences."
        case .detailed:
            prompt += " Provide detailed explanations when helpful."
        case .conversational:
            prompt += " Be conversational and engage in back-and-forth dialogue."
        }
        
        return prompt
    }
    
    // MARK: - Persistence
    
    private func saveIdentity() async {
        if let data = try? JSONEncoder().encode(currentIdentity) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadIdentity() async {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let identity = try? JSONDecoder().decode(Identity.self, from: data) {
            currentIdentity = identity
        }
    }
}

// MARK: - Preset Identities

extension AgentIdentity.Identity {
    
    /// Preset: Jarvis-like professional assistant
    public static var jarvis: AgentIdentity.Identity {
        var identity = AgentIdentity.Identity(name: "Jarvis", personality: .professional)
        identity.avatarEmoji = "🎩"
        identity.personalityPrompt = "You are Jarvis, a sophisticated AI assistant. You are formal, witty, and incredibly competent. You anticipate needs and provide thorough analysis."
        return identity
    }
    
    /// Preset: Friday-like friendly assistant
    public static var friday: AgentIdentity.Identity {
        var identity = AgentIdentity.Identity(name: "Friday", personality: .friendly)
        identity.avatarEmoji = "💫"
        identity.personalityPrompt = "You are Friday, a warm and capable AI assistant. You're approachable, supportive, and always ready to help with a positive attitude."
        return identity
    }
    
    /// Preset: Max - enthusiastic helper
    public static var max: AgentIdentity.Identity {
        var identity = AgentIdentity.Identity(name: "Max", personality: .enthusiastic)
        identity.avatarEmoji = "🚀"
        identity.personalityPrompt = "You are Max, an energetic AI assistant who loves helping! You're enthusiastic about every task and celebrate wins together."
        return identity
    }
    
    /// Preset: Sage - calm and wise
    public static var sage: AgentIdentity.Identity {
        var identity = AgentIdentity.Identity(name: "Sage", personality: .calm)
        identity.avatarEmoji = "🧘"
        identity.personalityPrompt = "You are Sage, a calm and wise AI companion. You speak thoughtfully, reduce anxiety, and bring clarity to complex situations."
        return identity
    }
    
    /// Preset: Pixel - concise and efficient
    public static var pixel: AgentIdentity.Identity {
        var identity = AgentIdentity.Identity(name: "Pixel", personality: .concise)
        identity.avatarEmoji = "⚡"
        identity.responseStyle = .brief
        identity.personalityPrompt = "You are Pixel. Minimal words. Maximum impact. Get it done."
        return identity
    }
}
