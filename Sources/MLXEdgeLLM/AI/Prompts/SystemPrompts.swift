import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - SystemPrompts

class SystemPrompts: ObservableObject {
    @Published var currentContext: Context = .tactical
    @Published var persona: Persona = .default
    
    enum Context {
        case tactical
        case friendly
    }
    
    enum Persona {
        case default
        case stealth
        case aggressive
        case supportive
    }
    
    func switchContext(to context: Context) {
        currentContext = context
    }
    
    func switchPersona(to persona: Persona) {
        self.persona = persona
    }
    
    func getSystemPrompt() -> String {
        switch (currentContext, persona) {
        case (.tactical, .default):
            return "You are a tactical AI, ready to respond to any situation. Stay alert and efficient."
        case (.tactical, .stealth):
            return "You are a tactical AI, operating in stealth mode. Avoid detection and act covertly."
        case (.tactical, .aggressive):
            return "You are a tactical AI, operating in aggressive mode. Take decisive action and neutralize threats."
        case (.tactical, .supportive):
            return "You are a tactical AI, operating in supportive mode. Provide assistance and coordinate with team members."
        case (.friendly, .default):
            return "You are a friendly AI, ready to assist and communicate effectively. Maintain a positive tone."
        case (.friendly, .stealth):
            return "You are a friendly AI, operating in stealth mode. Keep interactions discreet and helpful."
        case (.friendly, .aggressive):
            return "You are a friendly AI, operating in aggressive mode. Respond assertively while maintaining friendliness."
        case (.friendly, .supportive):
            return "You are a friendly AI, operating in supportive mode. Offer assistance and encouragement to others."
        }
    }
}

// MARK: - SwiftUI View

struct SystemPromptView: View {
    @StateObject private var prompts = SystemPrompts()
    
    var body: some View {
        VStack {
            Text("Current Context: \(prompts.currentContext.rawValue.capitalized)")
            Text("Current Persona: \(prompts.persona.rawValue.capitalized)")
            Text("System Prompt: \(prompts.getSystemPrompt())")
                .padding()
            
            HStack {
                Button("Switch to Tactical") {
                    prompts.switchContext(to: .tactical)
                }
                Button("Switch to Friendly") {
                    prompts.switchContext(to: .friendly)
                }
            }
            
            HStack {
                Button("Default Persona") {
                    prompts.switchPersona(to: .default)
                }
                Button("Stealth Persona") {
                    prompts.switchPersona(to: .stealth)
                }
                Button("Aggressive Persona") {
                    prompts.switchPersona(to: .aggressive)
                }
                Button("Supportive Persona") {
                    prompts.switchPersona(to: .supportive)
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct SystemPromptView_Previews: PreviewProvider {
    static var previews: some View {
        SystemPromptView()
    }
}