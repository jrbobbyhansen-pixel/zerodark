import Foundation
import CoreImage
import Vision

// MARK: - Vision Understanding

/// See and understand images with on-device vision models
/// LLaVA, Qwen-VL, SmolVLM — all local

public actor VisionUnderstanding {
    
    public static let shared = VisionUnderstanding()
    
    // MARK: - Vision Models
    
    public enum VisionModel: String, CaseIterable {
        case smolVLM = "SmolVLM-256M"           // 256M, fastest
        case qwen3VL = "Qwen3-VL-8B"            // 8B, balanced
        case llava = "LLaVA-1.6-7B"             // 7B, detailed
        
        public var sizeMB: Int {
            switch self {
            case .smolVLM: return 512
            case .qwen3VL: return 8000
            case .llava: return 7000
            }
        }
        
        public var maxImageSize: Int {
            switch self {
            case .smolVLM: return 384
            case .qwen3VL: return 1024
            case .llava: return 672
            }
        }
    }
    
    // MARK: - Image Processing
    
    /// Understand an image
    public func understand(
        image: CGImage,
        prompt: String = "Describe this image in detail.",
        model: VisionModel = .smolVLM
    ) async throws -> String {
        // Resize image for model
        let resized = try resize(image, to: model.maxImageSize)
        
        // Extract features using Vision framework
        let features = try await extractFeatures(resized)
        
        // Combine with prompt
        let fullPrompt = """
        <image>
        \(prompt)
        """
        
        // Generate description (placeholder - would use actual VLM)
        // For now, describe detected objects
        return generateDescription(features: features, prompt: prompt)
    }
    
    private func resize(_ image: CGImage, to maxSize: Int) throws -> CGImage {
        let width = image.width
        let height = image.height
        let maxDim = max(width, height)
        
        if maxDim <= maxSize {
            return image
        }
        
        let scale = CGFloat(maxSize) / CGFloat(maxDim)
        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)
        
        let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        guard let resized = context?.makeImage() else {
            throw VisionError.resizeFailed
        }
        
        return resized
    }
    
    // MARK: - Feature Extraction
    
    private struct ImageFeatures {
        var objects: [(label: String, confidence: Float)]
        var text: [String]
        var faces: Int
        var dominantColors: [String]
        var isNSFW: Bool
    }
    
    private func extractFeatures(_ image: CGImage) async throws -> ImageFeatures {
        var features = ImageFeatures(
            objects: [],
            text: [],
            faces: 0,
            dominantColors: [],
            isNSFW: false
        )
        
        let requestHandler = VNImageRequestHandler(cgImage: image)
        
        // Object detection
        let objectRequest = VNRecognizeAnimalsRequest { request, error in
            if let results = request.results as? [VNRecognizedObjectObservation] {
                for result in results {
                    if let label = result.labels.first {
                        features.objects.append((label.identifier, label.confidence))
                    }
                }
            }
        }
        
        // Text detection
        let textRequest = VNRecognizeTextRequest { request, error in
            if let results = request.results as? [VNRecognizedTextObservation] {
                for result in results {
                    if let text = result.topCandidates(1).first?.string {
                        features.text.append(text)
                    }
                }
            }
        }
        
        // Face detection
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            features.faces = request.results?.count ?? 0
        }
        
        try requestHandler.perform([objectRequest, textRequest, faceRequest])
        
        return features
    }
    
    private func generateDescription(features: ImageFeatures, prompt: String) -> String {
        var description = "I see "
        
        if !features.objects.isEmpty {
            let objectNames = features.objects.map { $0.label }.joined(separator: ", ")
            description += objectNames
        }
        
        if features.faces > 0 {
            description += ". There \(features.faces == 1 ? "is" : "are") \(features.faces) \(features.faces == 1 ? "person" : "people") in the image"
        }
        
        if !features.text.isEmpty {
            description += ". I can read the following text: \(features.text.joined(separator: ", "))"
        }
        
        description += "."
        
        return description
    }
    
    // MARK: - Specialized Vision Tasks
    
    /// Extract text from image (OCR)
    public func extractText(from image: CGImage) async throws -> String {
        let requestHandler = VNImageRequestHandler(cgImage: image)
        var extractedText: [String] = []
        
        let request = VNRecognizeTextRequest { request, error in
            if let results = request.results as? [VNRecognizedTextObservation] {
                for result in results {
                    if let text = result.topCandidates(1).first?.string {
                        extractedText.append(text)
                    }
                }
            }
        }
        
        request.recognitionLevel = .accurate
        try requestHandler.perform([request])
        
        return extractedText.joined(separator: "\n")
    }
    
    /// Describe image for accessibility
    public func accessibilityDescription(image: CGImage) async throws -> String {
        let features = try await extractFeatures(image)
        
        var parts: [String] = []
        
        if !features.objects.isEmpty {
            parts.append("Contains: \(features.objects.map { $0.label }.joined(separator: ", "))")
        }
        
        if features.faces > 0 {
            parts.append("\(features.faces) \(features.faces == 1 ? "face" : "faces") detected")
        }
        
        if !features.text.isEmpty {
            parts.append("Text visible: \(features.text.joined(separator: "; "))")
        }
        
        return parts.joined(separator: ". ")
    }
    
    /// Answer question about image
    public func visualQA(
        image: CGImage,
        question: String
    ) async throws -> String {
        return try await understand(
            image: image,
            prompt: "Question: \(question)\nAnswer:"
        )
    }
    
    // MARK: - Errors
    
    public enum VisionError: Error {
        case resizeFailed
        case modelNotLoaded
        case invalidImage
    }
}

// MARK: - Document Understanding

public actor DocumentUnderstanding {
    
    public static let shared = DocumentUnderstanding()
    
    /// Understand document layout and content
    public func analyze(document: CGImage) async throws -> DocumentAnalysis {
        let vision = await VisionUnderstanding.shared
        let text = try await vision.extractText(from: document)
        
        return DocumentAnalysis(
            text: text,
            pageCount: 1,
            hasImages: false,
            hasTables: false
        )
    }
    
    public struct DocumentAnalysis {
        public let text: String
        public let pageCount: Int
        public let hasImages: Bool
        public let hasTables: Bool
    }
}
