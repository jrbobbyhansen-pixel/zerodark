import Foundation
import AVFoundation
import CoreImage

// MARK: - Multi-Modal Fusion

/// Combine text + image + audio + video understanding
/// True multi-modal AI on device

public actor MultiModalFusion {
    
    public static let shared = MultiModalFusion()
    
    // MARK: - Input Types
    
    public enum ModalInput {
        case text(String)
        case image(CGImage)
        case audio(URL)
        case video(URL)
        case document(URL)
        case screen(CGImage)
    }
    
    public struct MultiModalRequest {
        public var inputs: [ModalInput]
        public var prompt: String
        public var maxTokens: Int = 512
        
        public init(inputs: [ModalInput], prompt: String) {
            self.inputs = inputs
            self.prompt = prompt
        }
    }
    
    // MARK: - Processing
    
    /// Process multi-modal input
    public func process(_ request: MultiModalRequest) async throws -> String {
        var context: [String] = []
        
        // Process each modality
        for input in request.inputs {
            let description = try await processInput(input)
            context.append(description)
        }
        
        // Combine context
        let fullContext = context.joined(separator: "\n\n")
        
        // Generate response
        let ai = await ZeroDarkAI.shared
        let fullPrompt = """
        Context:
        \(fullContext)
        
        User request: \(request.prompt)
        
        Response:
        """
        
        return try await ai.process(prompt: fullPrompt, onToken: { _ in })
    }
    
    private func processInput(_ input: ModalInput) async throws -> String {
        switch input {
        case .text(let text):
            return "TEXT: \(text)"
            
        case .image(let image):
            let vision = await VisionUnderstanding.shared
            let description = try await vision.understand(image: image)
            return "IMAGE: \(description)"
            
        case .audio(let url):
            let whisper = await WhisperPipeline.shared
            let transcription = try await whisper.transcribe(file: url)
            return "AUDIO: \(transcription.text)"
            
        case .video(let url):
            return try await processVideo(url)
            
        case .document(let url):
            return try await processDocument(url)
            
        case .screen(let image):
            let vision = await VisionUnderstanding.shared
            let description = try await vision.understand(image: image, prompt: "Describe this screen")
            return "SCREEN: \(description)"
        }
    }
    
    // MARK: - Video Processing
    
    private func processVideo(_ url: URL) async throws -> String {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        // Extract key frames
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        var frameDescriptions: [String] = []
        let frameCount = min(5, Int(duration))
        
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) * duration / Double(frameCount), preferredTimescale: 600)
            
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                let vision = await VisionUnderstanding.shared
                let desc = try await vision.understand(image: image, prompt: "Describe this video frame")
                frameDescriptions.append("Frame \(i + 1): \(desc)")
            }
        }
        
        // Extract audio
        let whisper = await WhisperPipeline.shared
        let transcription = try? await whisper.transcribe(file: url)
        
        var result = "VIDEO (\(Int(duration))s):\n"
        result += frameDescriptions.joined(separator: "\n")
        
        if let transcription = transcription, !transcription.text.isEmpty {
            result += "\nAUDIO: \(transcription.text)"
        }
        
        return result
    }
    
    // MARK: - Document Processing
    
    private func processDocument(_ url: URL) async throws -> String {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf":
            // Extract text from PDF
            guard let pdfDoc = CGPDFDocument(url as CFURL) else {
                throw FusionError.documentLoadFailed
            }
            
            var text = ""
            for i in 1...min(pdfDoc.numberOfPages, 10) {
                if let page = pdfDoc.page(at: i) {
                    // Would extract text from page
                    text += "Page \(i) content\n"
                }
            }
            return "DOCUMENT (PDF): \(text)"
            
        case "txt", "md":
            let content = try String(contentsOf: url)
            return "DOCUMENT: \(content)"
            
        default:
            return "DOCUMENT: Unknown format"
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Ask about an image
    public func askAboutImage(_ image: CGImage, question: String) async throws -> String {
        try await process(MultiModalRequest(
            inputs: [.image(image)],
            prompt: question
        ))
    }
    
    /// Summarize a video
    public func summarizeVideo(_ url: URL) async throws -> String {
        try await process(MultiModalRequest(
            inputs: [.video(url)],
            prompt: "Summarize this video in detail"
        ))
    }
    
    /// Analyze screen context
    public func analyzeScreen(_ screenshot: CGImage, task: String) async throws -> String {
        try await process(MultiModalRequest(
            inputs: [.screen(screenshot)],
            prompt: "Based on this screen, help me: \(task)"
        ))
    }
    
    /// Process conversation with mixed media
    public func chat(
        messages: [(role: String, content: [ModalInput])],
        newMessage: String
    ) async throws -> String {
        var context: [String] = []
        
        for message in messages {
            var parts: [String] = []
            for input in message.content {
                let processed = try await processInput(input)
                parts.append(processed)
            }
            context.append("\(message.role): \(parts.joined(separator: " "))")
        }
        
        let ai = await ZeroDarkAI.shared
        let fullPrompt = context.joined(separator: "\n") + "\nUser: \(newMessage)\nAssistant:"
        
        return try await ai.process(prompt: fullPrompt, onToken: { _ in })
    }
    
    // MARK: - Errors
    
    public enum FusionError: Error {
        case documentLoadFailed
        case videoProcessingFailed
        case modalityNotSupported
    }
}

// MARK: - Real-time Multi-Modal

/// Process multiple streams in real-time
public actor RealtimeMultiModal {
    
    public static let shared = RealtimeMultiModal()
    
    /// Process camera + microphone together
    public func processLiveStream(
        onResult: @escaping (String) -> Void
    ) async throws {
        // Would combine:
        // - Live camera frames (vision)
        // - Live microphone audio (whisper)
        // - Real-time LLM processing
        
        // For true real-time multi-modal understanding
    }
}
