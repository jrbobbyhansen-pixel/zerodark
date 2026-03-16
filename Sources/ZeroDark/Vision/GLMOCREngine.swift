// GLMOCREngine.swift
// Zero Dark - GLM-OCR Integration (0.9B Document Parser)
// Created: 2026-03-15

import Foundation
import CoreImage
import UIKit

// MARK: - OCR Output Types

public enum OCROutputFormat: String, Codable {
    case plainText = "text"
    case markdown = "markdown"
    case json = "json"
    case latex = "latex"
}

public struct OCRResult: Codable {
    public let text: String
    public let format: OCROutputFormat
    public let confidence: Float
    public let regions: [OCRRegion]
    public let processingTimeMs: Int
}

public struct OCRRegion: Codable {
    public let type: RegionType
    public let boundingBox: CGRect
    public let content: String
    
    public enum RegionType: String, Codable {
        case paragraph
        case table
        case formula
        case figure
        case header
        case footer
    }
}

// MARK: - GLM-OCR Engine

/// On-device OCR using GLM-OCR (0.9B params, runs on iPhone)
/// Model: mlx-community/GLM-OCR-4bit
@MainActor
public class GLMOCREngine: ObservableObject {
    
    @Published public private(set) var isLoaded = false
    @Published public private(set) var isProcessing = false
    
    private let modelPath: URL
    private var model: Any? // MLX model reference
    
    // Model specs
    public static let modelName = "GLM-OCR-4bit"
    public static let modelSize = "0.5GB"
    public static let parameters = "0.9B"
    
    public init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.modelPath = documents.appendingPathComponent("models/glm-ocr-4bit")
    }
    
    // MARK: - Model Management
    
    /// Check if model is downloaded
    public var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelPath.appendingPathComponent("config.json").path)
    }
    
    /// Download model from HuggingFace
    public func downloadModel(progress: @escaping (Float) -> Void) async throws {
        // In production, this would download from HuggingFace
        // For now, we'll use the mlx-lm download
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        process.arguments = [
            "-c",
            """
            from huggingface_hub import snapshot_download
            snapshot_download(
                repo_id="mlx-community/GLM-OCR-4bit",
                local_dir="\(modelPath.path)"
            )
            """
        ]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            isLoaded = true
        } else {
            throw OCRError.downloadFailed
        }
    }
    
    /// Load model into memory
    public func loadModel() async throws {
        guard isModelDownloaded else {
            throw OCRError.modelNotFound
        }
        
        // Load using MLX
        // In production, this integrates with mlx-swift or calls Python
        isLoaded = true
    }
    
    // MARK: - OCR Processing
    
    /// Process image and extract text
    public func processImage(
        _ image: UIImage,
        format: OCROutputFormat = .markdown
    ) async throws -> OCRResult {
        guard isLoaded else {
            throw OCRError.modelNotLoaded
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let startTime = Date()
        
        // Convert image to base64 for model input
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw OCRError.invalidImage
        }
        
        // Build prompt based on format
        let prompt = buildPrompt(for: format)
        
        // Call model (in production, this calls MLX inference)
        let result = try await runInference(imageData: imageData, prompt: prompt)
        
        let processingTime = Int(Date().timeIntervalSince(startTime) * 1000)
        
        return OCRResult(
            text: result,
            format: format,
            confidence: 0.95, // Would come from model
            regions: [], // Would be extracted from model output
            processingTimeMs: processingTime
        )
    }
    
    /// Process PDF document
    public func processPDF(at url: URL, format: OCROutputFormat = .markdown) async throws -> [OCRResult] {
        // Extract pages from PDF
        guard let document = CGPDFDocument(url as CFURL) else {
            throw OCRError.invalidDocument
        }
        
        var results: [OCRResult] = []
        
        for pageIndex in 1...document.numberOfPages {
            guard let page = document.page(at: pageIndex) else { continue }
            
            // Render page to image
            let pageRect = page.getBoxRect(.mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(pageRect)
                
                ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                ctx.cgContext.drawPDFPage(page)
            }
            
            let result = try await processImage(image, format: format)
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private func buildPrompt(for format: OCROutputFormat) -> String {
        switch format {
        case .plainText:
            return "Extract all text from this image. Output plain text only."
        case .markdown:
            return "Extract all text from this image. Format as clean Markdown with headers, lists, and tables preserved."
        case .json:
            return "Extract all text from this image. Output as structured JSON with fields for each section."
        case .latex:
            return "Extract all text and formulas from this image. Format mathematical expressions as LaTeX."
        }
    }
    
    private func runInference(imageData: Data, prompt: String) async throws -> String {
        // In production, this calls the MLX model
        // For now, return placeholder
        
        // The actual implementation would:
        // 1. Load image into model's vision encoder (CogViT)
        // 2. Run GLM decoder with prompt
        // 3. Use Multi-Token Prediction for speed
        // 4. Return structured output
        
        return "// OCR output would appear here"
    }
}

// MARK: - Errors

public enum OCRError: Error, LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case downloadFailed
    case invalidImage
    case invalidDocument
    case inferenceError(String)
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "GLM-OCR model not found. Please download first."
        case .modelNotLoaded:
            return "Model not loaded into memory."
        case .downloadFailed:
            return "Failed to download model from HuggingFace."
        case .invalidImage:
            return "Could not process the provided image."
        case .invalidDocument:
            return "Could not read the PDF document."
        case .inferenceError(let msg):
            return "Inference error: \(msg)"
        }
    }
}

// MARK: - Convenience Extensions

extension GLMOCREngine {
    
    /// Quick OCR from camera capture
    public func processFromCamera() async throws -> OCRResult {
        // Would integrate with camera capture
        throw OCRError.inferenceError("Camera capture not implemented")
    }
    
    /// OCR from clipboard image
    public func processFromClipboard() async throws -> OCRResult? {
        guard let image = UIPasteboard.general.image else {
            return nil
        }
        return try await processImage(image)
    }
}

// MARK: - Model Download Helper

public struct GLMOCRModelInfo {
    public static let huggingFaceRepo = "mlx-community/GLM-OCR-4bit"
    public static let downloadSize = "500MB"
    public static let requiredRAM = "1.5GB"
    
    public static let capabilities = [
        "Plain text extraction",
        "Table parsing → Markdown",
        "Formula extraction → LaTeX",
        "Document layout understanding",
        "Structured JSON output",
        "Multi-language support"
    ]
    
    public static let benchmarks = [
        "OmniDocBench": "94.6 (#1)",
        "Parameters": "0.9B",
        "Speed": "~50 tokens/sec on M4"
    ]
}
