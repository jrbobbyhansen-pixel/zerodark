import Foundation

/// Errores de MLXEdgeLLM
public enum MLXEdgeLLMError: LocalizedError {
    case modelNotLoaded
    case imageProcessingFailed
    case invalidResponse(String)
    
    public var errorDescription: String? {
        switch self {
            case .modelNotLoaded:
                return "Model is not loaded. Initialize MLXEdgeLLM or MLXEdgeLLMVision first."
            case .imageProcessingFailed:
                return "Failed to process the provided image."
            case .invalidResponse(let detail):
                return "Invalid model response: \(detail)"
        }
    }
}
