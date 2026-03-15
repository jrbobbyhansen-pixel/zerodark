import Foundation

// MARK: - Keyboard Extension Support

/// Enable Zero Dark as an AI-powered keyboard
/// User can invoke AI in ANY text field across iOS

/*
 To implement this, create a new Keyboard Extension target in Xcode:
 
 1. File → New → Target → Custom Keyboard Extension
 2. Name it "ZeroDarkKeyboard"
 3. Use this code as the KeyboardViewController
 
 The keyboard provides:
 - Normal typing
 - AI button to rewrite/improve text
 - Quick actions (translate, summarize, expand)
 - Voice input with transcription
*/

#if os(iOS)
import UIKit

/// Keyboard action types
public enum KeyboardAIAction: String, CaseIterable {
    case improve = "Improve"
    case fix = "Fix Grammar"
    case shorten = "Shorten"
    case expand = "Expand"
    case formal = "Make Formal"
    case casual = "Make Casual"
    case translate = "Translate"
    case reply = "Suggest Reply"
    case summarize = "Summarize"
    case bullets = "To Bullets"
}

/// Protocol for keyboard AI processing
public protocol KeyboardAIProcessor {
    func process(_ text: String, action: KeyboardAIAction) async throws -> String
}

/// Default implementation using Zero Dark
public final class ZeroDarkKeyboardProcessor: KeyboardAIProcessor {
    
    public static let shared = ZeroDarkKeyboardProcessor()
    
    public func process(_ text: String, action: KeyboardAIAction) async throws -> String {
        let prompt: String
        
        switch action {
        case .improve:
            prompt = "Improve this text while keeping the same meaning:\n\n\(text)"
        case .fix:
            prompt = "Fix any grammar or spelling errors in this text:\n\n\(text)"
        case .shorten:
            prompt = "Shorten this text while keeping the key points:\n\n\(text)"
        case .expand:
            prompt = "Expand on this text with more detail:\n\n\(text)"
        case .formal:
            prompt = "Rewrite this in a formal, professional tone:\n\n\(text)"
        case .casual:
            prompt = "Rewrite this in a casual, friendly tone:\n\n\(text)"
        case .translate:
            prompt = "Translate this to Spanish:\n\n\(text)"
        case .reply:
            prompt = "Suggest a helpful reply to this message:\n\n\(text)"
        case .summarize:
            prompt = "Summarize this in one sentence:\n\n\(text)"
        case .bullets:
            prompt = "Convert this to bullet points:\n\n\(text)"
        }
        
        let ai = await ZeroDarkAI.shared
        return try await ai.generate(prompt, stream: false)
    }
}

/*
 Example KeyboardViewController implementation:
 
 class KeyboardViewController: UIInputViewController {
     
     var aiButton: UIButton!
     var actionMenu: UIStackView!
     
     override func viewDidLoad() {
         super.viewDidLoad()
         setupKeyboard()
     }
     
     func setupKeyboard() {
         // Add AI button to keyboard
         aiButton = UIButton(type: .system)
         aiButton.setImage(UIImage(systemName: "brain"), for: .normal)
         aiButton.addTarget(self, action: #selector(showAIActions), for: .touchUpInside)
         view.addSubview(aiButton)
     }
     
     @objc func showAIActions() {
         // Show action menu
     }
     
     func performAIAction(_ action: KeyboardAIAction) {
         // Get text from text field
         guard let proxy = textDocumentProxy as? UITextDocumentProxy else { return }
         
         // Select all text (or get context)
         let text = proxy.documentContextBeforeInput ?? ""
         
         Task {
             let processor = ZeroDarkKeyboardProcessor.shared
             let result = try? await processor.process(text, action: action)
             
             if let result = result {
                 // Replace text
                 await MainActor.run {
                     // Delete old text
                     for _ in 0..<text.count {
                         proxy.deleteBackward()
                     }
                     // Insert new text
                     proxy.insertText(result)
                 }
             }
         }
     }
 }
*/
#endif
