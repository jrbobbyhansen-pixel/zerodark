import Foundation

// MARK: - Action Button Integration

/// Use iPhone 15/16 Pro Action Button for instant Zero Dark access
/// One press = Voice AI conversation

/*
 Action Button configuration:
 
 1. Settings → Action Button → Shortcut
 2. Create a Shortcut that calls "Voice Conversation" intent
 3. Press Action Button → Zero Dark listens
 
 The experience:
 - User presses Action Button
 - Zero Dark immediately starts listening
 - User speaks
 - AI responds with audio
 - Haptic feedback confirms completion
*/

#if os(iOS)
import UIKit

// MARK: - Action Button Handler

public final class ActionButtonHandler {
    
    public static let shared = ActionButtonHandler()
    
    /// Called when Action Button triggers Zero Dark
    public func handleActionButtonPress() async {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Start voice pipeline
        let voice = await MainActor.run { VoicePipeline.shared }
        
        do {
            // Start listening
            try await MainActor.run {
                try voice.startListening()
            }
            
            // Wait for transcription
            let transcription = await waitForTranscription(voice)
            
            // Process with AI
            let ai = await ZeroDarkAI.shared
            let response = try await ai.generate(transcription, stream: false)
            
            // Speak response
            await MainActor.run {
                voice.speak(response)
            }
            
            // Success haptic
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)
            
        } catch {
            // Error haptic
            let errorGenerator = UINotificationFeedbackGenerator()
            errorGenerator.notificationOccurred(.error)
        }
    }
    
    private func waitForTranscription(_ voice: VoicePipeline) async -> String {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                voice.onTranscriptionComplete = { text in
                    continuation.resume(returning: text)
                }
            }
        }
    }
}

// MARK: - Quick Launch Modes

public enum QuickLaunchMode: String, CaseIterable {
    case voice = "Voice Conversation"
    case camera = "Analyze Camera"
    case clipboard = "Process Clipboard"
    case translate = "Quick Translate"
    case calculate = "Quick Calculate"
    
    public var systemImage: String {
        switch self {
        case .voice: return "mic.fill"
        case .camera: return "camera.fill"
        case .clipboard: return "doc.on.clipboard"
        case .translate: return "globe"
        case .calculate: return "function"
        }
    }
    
    public func execute() async {
        switch self {
        case .voice:
            await ActionButtonHandler.shared.handleActionButtonPress()
            
        case .camera:
            // Open camera for vision analysis
            break
            
        case .clipboard:
            await processClipboard()
            
        case .translate:
            await translateClipboard()
            
        case .calculate:
            await calculateClipboard()
        }
    }
    
    private func processClipboard() async {
        guard let text = await MainActor.run(body: { UIPasteboard.general.string }) else { return }
        
        let ai = await ZeroDarkAI.shared
        let response = try? await ai.generate("Analyze this: \(text)", stream: false)
        
        if let response = response {
            await MainActor.run {
                UIPasteboard.general.string = response
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
    
    private func translateClipboard() async {
        guard let text = await MainActor.run(body: { UIPasteboard.general.string }) else { return }
        
        if #available(iOS 17.4, *) {
            let translation = LiveTranslation.shared
            let translated = try? await translation.translate(text, to: .spanish)
            
            if let translated = translated {
                await MainActor.run {
                    UIPasteboard.general.string = translated
                }
            }
        }
    }
    
    private func calculateClipboard() async {
        guard let text = await MainActor.run(body: { UIPasteboard.general.string }) else { return }
        
        let toolkit = await AgentToolkit.shared
        let result = await toolkit.execute(AgentToolkit.ToolCall(
            tool: "calculator",
            arguments: ["expression": text]
        ))
        
        if result.success {
            await MainActor.run {
                UIPasteboard.general.string = result.output
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
}
#endif
