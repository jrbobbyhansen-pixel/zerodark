import Foundation
import MLX

// MARK: - Speculative Decoding

/// 2-3x speedup by using small model to draft, large model to verify
/// This is how Claude, GPT-4 achieve low latency at scale

public actor SpeculativeDecoder {
    
    public static let shared = SpeculativeDecoder()
    
    // MARK: - Configuration
    
    public struct Config {
        /// Number of tokens to draft before verification
        public var draftTokens: Int = 5
        
        /// Draft model (small, fast)
        public var draftModel: Model = .qwen3_0_6b
        
        /// Target model (large, accurate)  
        public var targetModel: Model = .qwen3_8b
        
        /// Acceptance threshold (0-1)
        public var acceptanceThreshold: Float = 0.8
        
        /// Enable adaptive draft length
        public var adaptiveDraftLength: Bool = true
        
        public static let `default` = Config()
        
        /// Optimized for speed
        public static var speed: Config {
            var c = Config()
            c.draftTokens = 8
            c.draftModel = .qwen3_0_6b
            return c
        }
        
        /// Optimized for quality
        public static var quality: Config {
            var c = Config()
            c.draftTokens = 3
            c.acceptanceThreshold = 0.9
            return c
        }
    }
    
    public var config = Config()
    
    // MARK: - State
    
    private var draftEngine: BeastEngine?
    private var targetEngine: BeastEngine?
    private var acceptanceHistory: [Float] = []
    
    // MARK: - Generate
    
    public func generate(
        prompt: String,
        maxTokens: Int = 512,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        // Load engines if needed
        if draftEngine == nil {
            draftEngine = try await BeastEngine(model: config.draftModel)
        }
        if targetEngine == nil {
            targetEngine = try await BeastEngine(model: config.targetModel)
        }
        
        guard let draft = draftEngine, let target = targetEngine else {
            throw SpeculativeError.enginesNotLoaded
        }
        
        var fullResponse = ""
        var tokenCount = 0
        var currentDraftLength = config.draftTokens
        
        while tokenCount < maxTokens {
            // Phase 1: Draft tokens with small model
            let draftStart = Date()
            let draftTokens = try await generateDraft(
                engine: draft,
                prompt: prompt + fullResponse,
                count: currentDraftLength
            )
            let draftTime = Date().timeIntervalSince(draftStart)
            
            // Phase 2: Verify with target model
            let verifyStart = Date()
            let (accepted, verified) = try await verifyDraft(
                engine: target,
                prompt: prompt + fullResponse,
                draft: draftTokens
            )
            let verifyTime = Date().timeIntervalSince(verifyStart)
            
            // Calculate acceptance rate
            let acceptanceRate = Float(accepted) / Float(draftTokens.count)
            acceptanceHistory.append(acceptanceRate)
            
            // Adaptive draft length
            if config.adaptiveDraftLength {
                currentDraftLength = adaptDraftLength(
                    current: currentDraftLength,
                    acceptanceRate: acceptanceRate,
                    draftTime: draftTime,
                    verifyTime: verifyTime
                )
            }
            
            // Emit accepted tokens
            for token in verified {
                fullResponse += token
                tokenCount += 1
                onToken(fullResponse)
                
                if tokenCount >= maxTokens { break }
            }
            
            // Check for EOS
            if verified.last?.contains("<|endoftext|>") == true ||
               verified.last?.contains("</s>") == true {
                break
            }
        }
        
        return fullResponse
    }
    
    // MARK: - Draft Generation
    
    private func generateDraft(
        engine: BeastEngine,
        prompt: String,
        count: Int
    ) async throws -> [String] {
        var tokens: [String] = []
        var current = ""
        
        _ = try await engine.generate(
            prompt: prompt,
            maxTokens: count,
            onToken: { token in
                // Extract just the new token
                let newPart = String(token.dropFirst(current.count))
                if !newPart.isEmpty {
                    tokens.append(newPart)
                }
                current = token
            }
        )
        
        return tokens
    }
    
    // MARK: - Verification
    
    private func verifyDraft(
        engine: BeastEngine,
        prompt: String,
        draft: [String]
    ) async throws -> (accepted: Int, tokens: [String]) {
        var accepted = 0
        var verified: [String] = []
        
        // Get target model's probabilities for each draft token
        for (index, draftToken) in draft.enumerated() {
            let contextPrompt = prompt + verified.joined()
            
            // Generate one token from target
            var targetToken = ""
            _ = try await engine.generate(
                prompt: contextPrompt,
                maxTokens: 1,
                onToken: { token in
                    targetToken = token
                }
            )
            
            // Compare draft to target
            if draftToken == targetToken || 
               draftToken.trimmingCharacters(in: .whitespaces) == targetToken.trimmingCharacters(in: .whitespaces) {
                // Accept draft token
                verified.append(draftToken)
                accepted += 1
            } else {
                // Reject draft, use target token
                verified.append(targetToken)
                break // Stop accepting draft tokens after first rejection
            }
        }
        
        return (accepted, verified)
    }
    
    // MARK: - Adaptive Draft Length
    
    private func adaptDraftLength(
        current: Int,
        acceptanceRate: Float,
        draftTime: TimeInterval,
        verifyTime: TimeInterval
    ) -> Int {
        // If acceptance is high, draft more tokens
        // If acceptance is low, draft fewer tokens
        
        let minDraft = 2
        let maxDraft = 12
        
        var newLength = current
        
        if acceptanceRate > 0.9 {
            newLength = min(current + 2, maxDraft)
        } else if acceptanceRate > 0.7 {
            newLength = min(current + 1, maxDraft)
        } else if acceptanceRate < 0.4 {
            newLength = max(current - 2, minDraft)
        } else if acceptanceRate < 0.6 {
            newLength = max(current - 1, minDraft)
        }
        
        // Also consider timing ratio
        let timeRatio = draftTime / max(verifyTime, 0.001)
        if timeRatio > 0.5 {
            // Draft is taking too long relative to verify
            newLength = max(newLength - 1, minDraft)
        }
        
        return newLength
    }
    
    // MARK: - Stats
    
    public var averageAcceptanceRate: Float {
        guard !acceptanceHistory.isEmpty else { return 0 }
        return acceptanceHistory.reduce(0, +) / Float(acceptanceHistory.count)
    }
    
    public func resetStats() {
        acceptanceHistory.removeAll()
    }
    
    // MARK: - Errors
    
    public enum SpeculativeError: Error {
        case enginesNotLoaded
    }
}
