import Foundation

// MARK: - Text Models

/// Modelos de texto disponibles vía MLXLLM (mlx-community en HuggingFace).
public enum TextModel: String, CaseIterable, Sendable {
    
    /// Qwen3 0.6B — ~0.4 GB, ultra-ligero
    case qwen3_0_6b = "mlx-community/Qwen3-0.6B-4bit"
    
    /// Qwen3 1.7B — ~1.0 GB
    case qwen3_1_7b = "mlx-community/Qwen3-1.7B-4bit"
    
    /// Qwen3 4B — ~2.5 GB
    case qwen3_4b = "mlx-community/Qwen3-4B-4bit"
    
    /// Gemma 3 1B — ~0.7 GB
    case gemma3_1b = "mlx-community/gemma-3-1b-it-4bit"
    
    /// Phi-3.5 Mini — ~2.2 GB
    case phi3_5_mini = "mlx-community/Phi-3.5-mini-instruct-4bit"
    
    /// Llama 3.2 1B — ~0.7 GB
    case llama3_2_1b = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    
    /// Llama 3.2 3B — ~1.8 GB
    case llama3_2_3b = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    
    public var displayName: String {
        switch self {
            case .qwen3_0_6b:    return "Qwen3 0.6B"
            case .qwen3_1_7b:    return "Qwen3 1.7B"
            case .qwen3_4b:      return "Qwen3 4B"
            case .gemma3_1b:     return "Gemma 3 1B"
            case .phi3_5_mini:   return "Phi-3.5 Mini"
            case .llama3_2_1b:   return "Llama 3.2 1B"
            case .llama3_2_3b:   return "Llama 3.2 3B"
        }
    }
    
    public var approximateSizeMB: Int {
        switch self {
            case .qwen3_0_6b:    return 400
            case .qwen3_1_7b:    return 1_000
            case .qwen3_4b:      return 2_500
            case .gemma3_1b:     return 700
            case .phi3_5_mini:   return 2_200
            case .llama3_2_1b:   return 700
            case .llama3_2_3b:   return 1_800
        }
    }
    
    /// Modelo de texto por defecto
    public static var `default`: TextModel { .qwen3_1_7b }
}

// MARK: - Vision Language Models

/// Modelos Vision-Language disponibles vía MLXVLM (mlx-community en HuggingFace).
/// Soportan análisis de imágenes, OCR, document parsing y chat multimodal.
public enum VisionModel: String, CaseIterable, Sendable {
    
    /// ⭐ Recomendado: Qwen3.5 0.8B — ~1.0 GB, ideal para iPhone
    /// Multimodal nativo, OCR, document parsing, 201 idiomas
    case qwen35_0_8b = "mlx-community/Qwen3.5-0.8B-MLX-4bit"
    
    /// Qwen3.5 2B — ~1.8 GB, mayor precisión
    case qwen35_2b = "mlx-community/Qwen3.5-2B-4bit"
    
    /// Qwen3.5 4B — ~3.2 GB, para iPad Pro / Mac
    case qwen35_4b = "mlx-community/Qwen3.5-4B-4bit"
    
    /// Qwen2.5-VL 2B — ~1.4 GB, versión estable anterior
    case qwen25vl_2b = "mlx-community/Qwen2.5-VL-2B-Instruct-4bit"
    
    /// Gemma 3 4B — ~2.5 GB, visión de Google
    case gemma3_4b = "mlx-community/gemma-3-4b-it-4bit"
    
    /// SmolVLM 500M — ~0.5 GB, mínima memoria
    case smolvlm_500m = "mlx-community/SmolVLM-500M-Instruct-bf16"
    
    /// SmolVLM 2B — ~1.2 GB
    case smolvlm_2b = "mlx-community/SmolVLM-2B-Instruct-4bit"
    
    public var displayName: String {
        switch self {
            case .qwen35_0_8b:   return "Qwen3.5 0.8B ⭐"
            case .qwen35_2b:     return "Qwen3.5 2B"
            case .qwen35_4b:     return "Qwen3.5 4B"
            case .qwen25vl_2b:   return "Qwen2.5-VL 2B"
            case .gemma3_4b:     return "Gemma 3 4B"
            case .smolvlm_500m:  return "SmolVLM 500M"
            case .smolvlm_2b:    return "SmolVLM 2B"
        }
    }
    
    public var approximateSizeMB: Int {
        switch self {
            case .qwen35_0_8b:   return 1_000
            case .qwen35_2b:     return 1_800
            case .qwen35_4b:     return 3_200
            case .qwen25vl_2b:   return 1_400
            case .gemma3_4b:     return 2_500
            case .smolvlm_500m:  return 500
            case .smolvlm_2b:    return 1_200
        }
    }
    
    /// Modelo VLM por defecto para iOS
    public static var `default`: VisionModel { .qwen35_0_8b }
}
