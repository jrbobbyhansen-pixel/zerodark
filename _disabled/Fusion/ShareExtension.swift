import Foundation

// MARK: - Share Extension Support

/// Process ANY content shared from ANY app with Zero Dark
/// User selects text/image/URL → Share → Zero Dark → AI processes

/*
 To implement:
 1. File → New → Target → Share Extension
 2. Name it "ZeroDarkShare"
 3. Configure Info.plist for supported types
 4. Use ShareProcessor below
*/

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// Actions available in share extension
public enum ShareAction: String, CaseIterable {
    case summarize = "Summarize"
    case explain = "Explain"
    case translate = "Translate"
    case analyze = "Analyze"
    case extractFacts = "Extract Facts"
    case critique = "Critique"
    case saveToMemory = "Save to Memory"
    case askQuestion = "Ask Question"
}

/// Processes shared content
public final class ShareProcessor {
    
    public static let shared = ShareProcessor()
    
    // MARK: - Process Text
    
    public func processText(_ text: String, action: ShareAction) async throws -> String {
        let prompt: String
        
        switch action {
        case .summarize:
            prompt = "Summarize this content:\n\n\(text)"
        case .explain:
            prompt = "Explain this in simple terms:\n\n\(text)"
        case .translate:
            prompt = "Translate this to Spanish:\n\n\(text)"
        case .analyze:
            prompt = "Analyze this content. What are the key points, arguments, and implications?\n\n\(text)"
        case .extractFacts:
            prompt = "Extract the key facts from this content as bullet points:\n\n\(text)"
        case .critique:
            prompt = "Provide a critical analysis of this content:\n\n\(text)"
        case .saveToMemory:
            // Save to conversation memory
            let memory = await ConversationMemory.shared
            await memory.remember(text, type: .fact, importance: 0.7)
            return "Saved to memory"
        case .askQuestion:
            // Will be handled interactively
            return text
        }
        
        let ai = await ZeroDarkAI.shared
        return try await ai.process(prompt: prompt, stream: false)
    }
    
    // MARK: - Process URL
    
    public func processURL(_ url: URL, action: ShareAction) async throws -> String {
        // Fetch URL content
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ShareError.cannotFetchURL
        }
        
        // Extract text from HTML (basic extraction)
        let text = extractText(from: html)
        
        return try await processText(text, action: action)
    }
    
    private func extractText(from html: String) -> String {
        // Remove scripts and styles
        var text = html
        
        // Remove script tags
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        if let regex = try? NSRegularExpression(pattern: scriptPattern, options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        
        // Remove style tags
        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"
        if let regex = try? NSRegularExpression(pattern: stylePattern, options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        
        // Remove all HTML tags
        let tagPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        
        // Clean up whitespace
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        // Limit length
        if text.count > 10000 {
            text = String(text.prefix(10000)) + "..."
        }
        
        return text
    }
    
    // MARK: - Process Image
    
    public func processImage(_ image: UIImage, action: ShareAction) async throws -> String {
        // Use vision model
        let ai = await ZeroDarkAI.shared
        
        let prompt: String
        switch action {
        case .summarize:
            prompt = "Describe what you see in this image."
        case .explain:
            prompt = "Explain what's happening in this image in detail."
        case .analyze:
            prompt = "Analyze this image. What are the key elements, composition, and meaning?"
        case .extractFacts:
            prompt = "Extract any text, numbers, or factual information from this image."
        default:
            prompt = "Describe this image."
        }
        
        // Use vision model
        return try await ai.generateVision(prompt, images: [image])
    }
    
    // MARK: - Errors
    
    public enum ShareError: Error, LocalizedError {
        case cannotFetchURL
        case unsupportedContent
        
        public var errorDescription: String? {
            switch self {
            case .cannotFetchURL: return "Could not fetch URL content"
            case .unsupportedContent: return "Unsupported content type"
            }
        }
    }
}

/*
 Example ShareViewController implementation:
 
 class ShareViewController: UIViewController {
     
     var sharedText: String?
     var sharedURL: URL?
     var sharedImage: UIImage?
     
     override func viewDidLoad() {
         super.viewDidLoad()
         extractSharedContent()
         setupUI()
     }
     
     func extractSharedContent() {
         guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
               let attachments = extensionItem.attachments else { return }
         
         for attachment in attachments {
             if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                 attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                     self.sharedText = item as? String
                 }
             } else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                 attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                     self.sharedURL = item as? URL
                 }
             } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                 attachment.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                     if let url = item as? URL, let data = try? Data(contentsOf: url) {
                         self.sharedImage = UIImage(data: data)
                     }
                 }
             }
         }
     }
     
     func performAction(_ action: ShareAction) {
         Task {
             let processor = ShareProcessor.shared
             var result: String?
             
             if let text = sharedText {
                 result = try? await processor.processText(text, action: action)
             } else if let url = sharedURL {
                 result = try? await processor.processURL(url, action: action)
             } else if let image = sharedImage {
                 result = try? await processor.processImage(image, action: action)
             }
             
             // Show result or copy to clipboard
             if let result = result {
                 UIPasteboard.general.string = result
             }
             
             extensionContext?.completeRequest(returningItems: nil)
         }
     }
 }
*/
#endif
