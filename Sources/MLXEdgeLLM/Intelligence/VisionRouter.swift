import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Vision Router

/// Routes vision tasks to the appropriate model:
/// - GLM-OCR for documents, tables, formulas, text extraction
/// - General VLM for scene understanding, object detection, etc.
@MainActor
public final class VisionRouter {
    
    public static let shared = VisionRouter()
    
    // Vision task types
    public enum VisionTask {
        case ocr           // Document parsing, text extraction
        case tableExtract  // Table → structured data
        case formulaExtract // Math formulas → LaTeX
        case sceneAnalysis // General "what's in this image"
        case objectDetect  // Find specific objects
        case imageChat     // Conversational about image
    }
    
    // MARK: - Classification
    
    /// Classify what type of vision task this is
    public func classifyVisionTask(prompt: String, imageType: ImageType) -> VisionTask {
        let lowercased = prompt.lowercased()
        
        // Document indicators → OCR
        let ocrPhrases = [
            "extract", "read", "ocr", "text", "transcribe",
            "what does it say", "parse", "scan"
        ]
        if ocrPhrases.contains(where: { lowercased.contains($0) }) {
            return .ocr
        }
        
        // Table indicators
        if lowercased.contains("table") || lowercased.contains("spreadsheet") ||
           lowercased.contains("columns") || lowercased.contains("rows") {
            return .tableExtract
        }
        
        // Formula indicators
        if lowercased.contains("formula") || lowercased.contains("equation") ||
           lowercased.contains("math") || lowercased.contains("latex") {
            return .formulaExtract
        }
        
        // Image type hints
        switch imageType {
        case .document, .pdf, .screenshot:
            return .ocr
        case .photo, .artwork:
            return .sceneAnalysis
        case .diagram:
            return lowercased.contains("formula") ? .formulaExtract : .ocr
        case .unknown:
            break
        }
        
        // Default to scene analysis for general images
        return .sceneAnalysis
    }
    
    // MARK: - Routing Decision
    
    public struct VisionRoutingDecision {
        public let task: VisionTask
        public let useGLMOCR: Bool      // True = use GLM-OCR engine
        public let useGeneralVLM: Bool  // True = use Qwen-VL or similar
        public let outputFormat: OCROutputFormat
        public let confidence: Float
    }
    
    /// Route a vision request to the appropriate model
    public func route(
        prompt: String,
        imageType: ImageType = .unknown
    ) -> VisionRoutingDecision {
        let task = classifyVisionTask(prompt: prompt, imageType: imageType)
        
        switch task {
        case .ocr, .tableExtract, .formulaExtract:
            // Use GLM-OCR for document tasks
            let format: OCROutputFormat
            switch task {
            case .tableExtract: format = .markdown
            case .formulaExtract: format = .latex
            default: format = .markdown
            }
            
            return VisionRoutingDecision(
                task: task,
                useGLMOCR: true,
                useGeneralVLM: false,
                outputFormat: format,
                confidence: 0.95
            )
            
        case .sceneAnalysis, .objectDetect, .imageChat:
            // Use general VLM for understanding tasks
            return VisionRoutingDecision(
                task: task,
                useGLMOCR: false,
                useGeneralVLM: true,
                outputFormat: .plainText,
                confidence: 0.9
            )
        }
    }
}

// MARK: - Image Type Detection

public enum ImageType {
    case document    // Scanned doc, printed text
    case pdf         // PDF page
    case screenshot  // Screen capture
    case photo       // Natural photo
    case artwork     // Illustration, painting
    case diagram     // Charts, flowcharts
    case unknown
    
    /// Detect image type from file extension or content hints
    public static func detect(from url: URL) -> ImageType {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        
        let filename = url.lastPathComponent.lowercased()
        if filename.contains("screenshot") { return .screenshot }
        if filename.contains("scan") { return .document }
        if filename.contains("receipt") || filename.contains("invoice") { return .document }
        
        return .unknown
    }
}

// MARK: - Unified Vision Interface

@MainActor
public class UnifiedVisionEngine {
    
    private let glmOCR: GLMOCREngine
    private let modelRouter: ModelRouter
    private let visionRouter: VisionRouter
    
    public init() {
        self.glmOCR = GLMOCREngine()
        self.modelRouter = ModelRouter.shared
        self.visionRouter = VisionRouter.shared
    }
    
    /// Process any image with automatic model selection
    public func process(
        image: UIImage,
        prompt: String,
        imageType: ImageType = .unknown
    ) async throws -> String {
        let decision = visionRouter.route(prompt: prompt, imageType: imageType)
        
        if decision.useGLMOCR {
            // Route to GLM-OCR
            let result = try await glmOCR.processImage(image, format: decision.outputFormat)
            return result.text
        } else {
            // Route to general VLM via ModelRouter
            // This would call the selected VLM model
            let model = modelRouter.selectModel(for: .vision)
            // ... inference code here
            return "// VLM inference result"
        }
    }
}
