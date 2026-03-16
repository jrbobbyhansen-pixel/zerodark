// VikingMemoryDemo.swift
// Zero Dark - Usage Examples
// Created: 2026-03-15

import Foundation

// MARK: - Demo: How Tiered Memory Works

/*
 
 ## The Problem This Solves
 
 Traditional approach: Dump entire conversation history into context
 - 20 messages = ~10,000 tokens
 - Expensive, slow, hits limits
 
 Viking approach: Tiered memory loading
 - L0 summaries always loaded = ~500 tokens
 - L1 loaded for relevant topics = ~1,000 tokens
 - L2 only on explicit drill-down
 - Result: 80%+ token savings
 
 ## Example Flow
 
 1. User says: "I prefer dark mode and concise responses"
    
    Memory Created:
    ├── Category: preferences
    ├── L0: "Prefers dark mode and concise responses"
    ├── L1: "User explicitly stated preference for dark mode UI and concise, direct responses without unnecessary elaboration."
    └── L2: [Full conversation turn stored]
 
 2. Later, user asks: "Change the theme"
    
    Context Built:
    ├── [All L0 summaries - always included]
    │   └── "Prefers dark mode and concise responses"
    ├── [L1 for "preferences" - relevant to "theme"]
    │   └── "User explicitly stated preference for dark mode..."
    └── [L2 NOT loaded - not explicitly requested]
 
 3. AI responds knowing user prefers dark mode, without seeing full history
 
 ## Token Comparison
 
 Scenario: 50-message conversation about a project
 
 Traditional RAG:
 - All messages in context: ~25,000 tokens
 - Hit context limits, expensive
 
 Viking Tiered:
 - 10 L0 summaries: ~1,000 tokens
 - 3 relevant L1 sections: ~1,500 tokens
 - Total: ~2,500 tokens (90% savings!)
 
 */

// MARK: - Demo Usage

@MainActor
func demoVikingMemory() async {
    let memoryStore = TieredMemoryStore()
    let promptBuilder = VikingPromptBuilder(memoryStore: memoryStore)
    let autoHook = AutoMemoryHook(memoryStore: memoryStore)
    
    // Simulate conversation turns
    
    // Turn 1: User states preference
    autoHook.onConversationTurn(
        userMessage: "I prefer concise responses, no fluff. Also I'm working on a project called Zero Dark.",
        assistantResponse: "Got it! I'll keep responses direct and to the point. Zero Dark sounds interesting - what's it about?"
    )
    
    // Turn 2: User describes project
    autoHook.onConversationTurn(
        userMessage: "Zero Dark is an on-device AI framework for Apple platforms. We just added MLX support.",
        assistantResponse: "Nice! On-device AI with MLX - that's powerful for privacy and performance. What models are you running?"
    )
    
    // Turn 3: A decision
    autoHook.onConversationTurn(
        userMessage: "We decided to go with Qwen 3.5 9B. It works with strict=False to skip vision weights.",
        assistantResponse: "Smart choice! Qwen 3.5 9B at 48.5 tok/s with the strict=False trick is a solid setup."
    )
    
    // Now build context for a new query
    let context = promptBuilder.buildSystemPrompt(
        basePrompt: "You are Zero Dark AI, an on-device assistant.",
        currentQuery: "What model should I use for code generation?",
        maxMemoryTokens: 2000
    )
    
    print("=== Built Context ===")
    print(context)
    print("")
    
    // Check stats
    let stats = MemoryStats(from: memoryStore)
    print(stats.description)
}

// MARK: - Integration with ZeroDarkAI

/*
 
 To integrate with existing ZeroDarkAI:
 
 1. Add TieredMemoryStore as a property:
    
    @MainActor
    public class ZeroDarkAI: ObservableObject {
        private let memoryStore = TieredMemoryStore()
        private lazy var autoHook = AutoMemoryHook(memoryStore: memoryStore)
        private lazy var promptBuilder = VikingPromptBuilder(memoryStore: memoryStore)
        // ...
    }
 
 2. In the chat method, wrap the system prompt:
    
    func chat(messages: [Message]) async -> String {
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        
        let enhancedSystemPrompt = promptBuilder.buildSystemPrompt(
            basePrompt: systemPrompt,
            currentQuery: lastUserMessage
        )
        
        // Use enhancedSystemPrompt instead of systemPrompt
        // ...
    }
 
 3. After each response, call the hook:
    
    func onResponse(userMessage: String, response: String) {
        autoHook.onConversationTurn(
            userMessage: userMessage,
            assistantResponse: response
        )
    }
 
 4. That's it! Memory extraction and tiered loading happen automatically.
 
 */

// MARK: - File Structure

/*
 
 Sources/ZeroDark/Memory/
 ├── TieredMemory.swift           <- Core L0/L1/L2 system
 ├── VikingMemoryIntegration.swift <- ZeroDarkAI hooks
 └── VikingMemoryDemo.swift        <- This file (examples)
 
 Storage:
 ~/Documents/zerodark_memory.json  <- Persisted memories
 
 */
