import Foundation
import ScreenCaptureKit
import Vision
import CoreGraphics

// MARK: - Screen Understanding

/// Read and understand what's on screen (macOS only)
#if os(macOS)
@MainActor
public final class ScreenUnderstanding: ObservableObject {
    
    public static let shared = ScreenUnderstanding()
    
    // MARK: - State
    
    @Published public var isAvailable: Bool = false
    @Published public var lastCapture: ScreenCapture?
    @Published public var lastAnalysis: ScreenAnalysis?
    
    // MARK: - Types
    
    public struct ScreenCapture {
        public let image: CGImage
        public let timestamp: Date
        public let displayID: CGDirectDisplayID
    }
    
    public struct ScreenAnalysis {
        public let text: [TextBlock]
        public let uiElements: [UIElement]
        public let description: String
        
        public struct TextBlock {
            public let text: String
            public let boundingBox: CGRect
            public let confidence: Float
        }
        
        public struct UIElement {
            public let type: String  // button, textfield, link, etc.
            public let label: String?
            public let boundingBox: CGRect
        }
    }
    
    // MARK: - Init
    
    private init() {
        checkAvailability()
    }
    
    private func checkAvailability() {
        if #available(macOS 12.3, *) {
            isAvailable = true
        } else {
            isAvailable = false
        }
    }
    
    // MARK: - Capture Screen
    
    @available(macOS 12.3, *)
    public func captureScreen() async throws -> ScreenCapture {
        // Get available content
        let content = try await SCShareableContent.current
        
        guard let display = content.displays.first else {
            throw ScreenError.noDisplayAvailable
        }
        
        // Create stream configuration
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        
        // Create filter for display
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // Capture screenshot
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        let capture = ScreenCapture(
            image: image,
            timestamp: Date(),
            displayID: display.displayID
        )
        
        lastCapture = capture
        return capture
    }
    
    // MARK: - Analyze Screen
    
    public func analyzeScreen(_ capture: ScreenCapture) async throws -> ScreenAnalysis {
        var textBlocks: [ScreenAnalysis.TextBlock] = []
        var uiElements: [ScreenAnalysis.UIElement] = []
        
        // Text recognition using Vision
        let textRequest = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                
                let block = ScreenAnalysis.TextBlock(
                    text: topCandidate.string,
                    boundingBox: observation.boundingBox,
                    confidence: topCandidate.confidence
                )
                textBlocks.append(block)
            }
        }
        
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        
        // Rectangle detection for UI elements
        let rectRequest = VNDetectRectanglesRequest { request, error in
            guard let observations = request.results as? [VNRectangleObservation] else { return }
            
            for observation in observations {
                let element = ScreenAnalysis.UIElement(
                    type: "rectangle",
                    label: nil,
                    boundingBox: observation.boundingBox
                )
                uiElements.append(element)
            }
        }
        
        // Run Vision requests
        let handler = VNImageRequestHandler(cgImage: capture.image, options: [:])
        try handler.perform([textRequest, rectRequest])
        
        // Generate description
        let description = generateDescription(textBlocks: textBlocks, uiElements: uiElements)
        
        let analysis = ScreenAnalysis(
            text: textBlocks,
            uiElements: uiElements,
            description: description
        )
        
        lastAnalysis = analysis
        return analysis
    }
    
    private func generateDescription(
        textBlocks: [ScreenAnalysis.TextBlock],
        uiElements: [ScreenAnalysis.UIElement]
    ) -> String {
        var lines: [String] = []
        
        lines.append("Screen Content:")
        lines.append("")
        
        // Group text by vertical position (rough layout understanding)
        let sortedText = textBlocks.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        
        var currentY: CGFloat = -1
        for block in sortedText {
            // New line group if Y position changed significantly
            if currentY < 0 || abs(block.boundingBox.origin.y - currentY) > 0.02 {
                if currentY >= 0 { lines.append("") }
                currentY = block.boundingBox.origin.y
            }
            lines.append("  \(block.text)")
        }
        
        lines.append("")
        lines.append("UI Elements: \(uiElements.count) detected")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Capture Window
    
    @available(macOS 12.3, *)
    public func captureWindow(titled: String) async throws -> ScreenCapture {
        let content = try await SCShareableContent.current
        
        guard let window = content.windows.first(where: { 
            $0.title?.lowercased().contains(titled.lowercased()) == true 
        }) else {
            throw ScreenError.windowNotFound(titled)
        }
        
        guard let display = content.displays.first else {
            throw ScreenError.noDisplayAvailable
        }
        
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        
        let filter = SCContentFilter(display: display, including: [window])
        
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        return ScreenCapture(
            image: image,
            timestamp: Date(),
            displayID: display.displayID
        )
    }
    
    // MARK: - Errors
    
    public enum ScreenError: Error, LocalizedError {
        case noDisplayAvailable
        case windowNotFound(String)
        case captureFailure
        
        public var errorDescription: String? {
            switch self {
            case .noDisplayAvailable: return "No display available"
            case .windowNotFound(let title): return "Window not found: \(title)"
            case .captureFailure: return "Screen capture failed"
            }
        }
    }
}
#endif

// MARK: - iOS Screen Understanding

#if os(iOS)
import UIKit

@MainActor
public final class ScreenUnderstanding: ObservableObject {
    
    public static let shared = ScreenUnderstanding()
    
    @Published public var isAvailable: Bool = false
    
    public struct ScreenAnalysis {
        public let text: [TextBlock]
        public let description: String
        
        public struct TextBlock {
            public let text: String
            public let boundingBox: CGRect
            public let confidence: Float
        }
    }
    
    private init() {
        // Screen capture not available on iOS without app-specific implementation
        isAvailable = false
    }
    
    /// Analyze a provided image (e.g., from Photos or camera)
    public func analyzeImage(_ image: UIImage) async throws -> ScreenAnalysis {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "ScreenUnderstanding", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Could not get CGImage from UIImage"
            ])
        }
        
        var textBlocks: [ScreenAnalysis.TextBlock] = []
        
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                
                textBlocks.append(ScreenAnalysis.TextBlock(
                    text: topCandidate.string,
                    boundingBox: observation.boundingBox,
                    confidence: topCandidate.confidence
                ))
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        let description = textBlocks.map { $0.text }.joined(separator: "\n")
        
        return ScreenAnalysis(
            text: textBlocks,
            description: description.isEmpty ? "No text detected" : description
        )
    }
}
#endif
