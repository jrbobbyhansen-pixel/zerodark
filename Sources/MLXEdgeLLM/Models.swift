import Foundation

// MARK: - Model

public enum Model: String, CaseIterable, Sendable {
    
    // MARK: Text
    case qwen3_0_6b   = "mlx-community/Qwen3-0.6B-4bit"
    case qwen3_1_7b   = "mlx-community/Qwen3-1.7B-4bit"
    case qwen3_4b     = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
    case gemma3_1b    = "mlx-community/gemma-3-1b-it-4bit"
    case phi3_5_mini  = "mlx-community/Phi-3.5-mini-instruct-4bit"
    case llama3_2_1b  = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    case llama3_2_3b  = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    
    // MARK: Text · BEAST MODE (8B - max for iPhone 16 Pro Max)
    case qwen3_8b            = "mlx-community/Qwen3-8B-4bit"
    case llama3_1_8b         = "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"
    case qwen3_8b_abliterated = "mlx-community/Josiefied-Qwen3-8B-abliterated-v1-4bit"
    case deepseek_r1_8b      = "mlx-community/DeepSeek-R1-Distill-Llama-8B-4bit"
    case ministral_8b        = "mlx-community/Ministral-8B-Instruct-2410-4bit"
    case hermes3_8b          = "mlx-community/Hermes-3-Llama-3.1-8B-4bit"
    case llama3_groq_8b      = "mlx-community/Llama-3-Groq-8B-Tool-Use-4bit"
    
    // MARK: Text · CODE SPECIALISTS
    case qwen25_coder_7b     = "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"
    case deepcoder_8b        = "mlx-community/DeepCoder-14B-Preview-4bit"
    
    // MARK: Text · 14B PERFORMANCE TIER (iPad Pro M4 / Mac)
    case qwen25_14b          = "mlx-community/Qwen2.5-14B-Instruct-4bit"
    case qwen25_coder_14b    = "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit"
    case deepseek_r1_14b     = "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
    case qwen3_14b           = "mlx-community/Qwen3-14B-4bit"
    case hermes4_14b         = "mlx-community/Hermes-4-14B-4bit"
    
    // MARK: Vision
    case qwen35_0_8b  = "mlx-community/Qwen3.5-0.8B-MLX-4bit"
    case qwen35_2b    = "mlx-community/Qwen3.5-2B-4bit"
    case smolvlm_500m = "mlx-community/SmolVLM-500M-Instruct-bf16"
    case smolvlm_2b   = "mlx-community/SmolVLM-Instruct-4bit"
    
    // MARK: Vision · BEAST MODE (8B Vision-Language)
    case qwen3_vl_8b  = "mlx-community/Qwen3-VL-8B-Instruct-4bit"
    
    // MARK: Vision · Specialized
    case fastVLM_0_5b_fp16   = "mlx-community/FastVLM-0.5B-bf16"
    case fastVLM_1_5b_int8   = "InsightKeeper/FastVLM-1.5B-MLX-8bit"
    case graniteDocling_258m  = "ibm-granite/granite-docling-258M-mlx"
    case graniteVision_3_3   = "mlx-community/granite-vision-3.2-2b-MLX"
    
    // MARK: - Purpose
    
    public enum Purpose {
        case text
        case vision
        case visionSpecialized(docTags: Bool)
    }
    
    public var purpose: Purpose {
        switch self {
            case .qwen3_0_6b, .qwen3_1_7b, .qwen3_4b,
                    .gemma3_1b, .phi3_5_mini,
                    .llama3_2_1b, .llama3_2_3b,
                    .qwen3_8b, .llama3_1_8b, .qwen3_8b_abliterated, .deepseek_r1_8b,
                    .ministral_8b, .hermes3_8b, .llama3_groq_8b,
                    .qwen25_coder_7b, .deepcoder_8b,
                    .qwen25_14b, .qwen25_coder_14b, .deepseek_r1_14b, .qwen3_14b, .hermes4_14b:
                return .text
                
            case .qwen35_0_8b, .qwen35_2b,
                    .smolvlm_500m, .smolvlm_2b,
                    .qwen3_vl_8b:
                return .vision
                
            case .fastVLM_0_5b_fp16, .fastVLM_1_5b_int8, .graniteVision_3_3:
                return .visionSpecialized(docTags: false)
                
            case .graniteDocling_258m:
                return .visionSpecialized(docTags: true)
        }
    }
    
    // MARK: - Metadata
    
    public var displayName: String {
        switch self {
            case .qwen3_0_6b:          return "Qwen3 0.6B"
            case .qwen3_1_7b:          return "Qwen3 1.7B"
            case .qwen3_4b:            return "Qwen3 4B"
            case .gemma3_1b:           return "Gemma 3 1B"
            case .phi3_5_mini:         return "Phi-3.5 Mini"
            case .llama3_2_1b:         return "Llama 3.2 1B"
            case .llama3_2_3b:         return "Llama 3.2 3B"
            // BEAST MODE
            case .qwen3_8b:            return "⚡ Qwen3 8B (BEAST)"
            case .llama3_1_8b:         return "⚡ Llama 3.1 8B (BEAST)"
            case .qwen3_8b_abliterated: return "🔓 Qwen3 8B Abliterated (BEAST)"
            case .deepseek_r1_8b:      return "🧠 DeepSeek R1 8B (Reasoning)"
            case .ministral_8b:        return "⚡ Ministral 8B (BEAST)"
            case .hermes3_8b:          return "⚡ Hermes 3 8B (BEAST)"
            case .llama3_groq_8b:      return "🔧 Llama 3 Groq 8B (Tools)"
            // CODE SPECIALISTS
            case .qwen25_coder_7b:     return "💻 Qwen2.5 Coder 7B"
            case .deepcoder_8b:        return "💻 DeepCoder 14B"
            // 14B PERFORMANCE TIER
            case .qwen25_14b:          return "🚀 Qwen2.5 14B (PRO)"
            case .qwen25_coder_14b:    return "🚀💻 Qwen2.5 Coder 14B (PRO)"
            case .deepseek_r1_14b:     return "🚀🧠 DeepSeek R1 14B (PRO)"
            case .qwen3_14b:           return "🚀 Qwen3 14B (PRO)"
            case .hermes4_14b:         return "🚀 Hermes 4 14B (PRO)"
            // Vision
            case .qwen35_0_8b:         return "Qwen3.5 0.8B (default)"
            case .qwen35_2b:           return "Qwen3.5 2B"
            case .smolvlm_500m:        return "SmolVLM 500M"
            case .smolvlm_2b:          return "SmolVLM2 2B"
            case .qwen3_vl_8b:         return "⚡👁️ Qwen3 VL 8B Vision (BEAST)"
            // Specialized
            case .fastVLM_0_5b_fp16:   return "FastVLM 0.5B FP16"
            case .fastVLM_1_5b_int8:   return "FastVLM 1.5B Int8"
            case .graniteDocling_258m: return "Granite Docling 258M (IBM)"
            case .graniteVision_3_3:   return "Granite Vision 3.2 2B"
        }
    }
    
    public var approximateSizeMB: Int {
        switch self {
            case .qwen3_0_6b:          return 400
            case .qwen3_1_7b:          return 1_000
            case .qwen3_4b:            return 2_500
            case .gemma3_1b:           return 700
            case .phi3_5_mini:         return 2_200
            case .llama3_2_1b:         return 700
            case .llama3_2_3b:         return 1_800
            // BEAST MODE (8B = ~4.5GB)
            case .qwen3_8b:            return 4_500
            case .llama3_1_8b:         return 4_500
            case .qwen3_8b_abliterated: return 4_500
            case .deepseek_r1_8b:      return 4_500
            case .ministral_8b:        return 4_500
            case .hermes3_8b:          return 4_500
            case .llama3_groq_8b:      return 4_500
            // CODE SPECIALISTS
            case .qwen25_coder_7b:     return 4_000
            case .deepcoder_8b:        return 7_500
            // 14B PERFORMANCE TIER (requires 16GB+ RAM)
            case .qwen25_14b:          return 8_000
            case .qwen25_coder_14b:    return 8_000
            case .deepseek_r1_14b:     return 8_000
            case .qwen3_14b:           return 8_000
            case .hermes4_14b:         return 8_000
            // Vision
            case .qwen35_0_8b:         return 625
            case .qwen35_2b:           return 1_720
            case .smolvlm_500m:        return 1_020
            case .smolvlm_2b:          return 1_460
            case .qwen3_vl_8b:         return 4_500
            // Specialized
            case .fastVLM_0_5b_fp16:   return 1_250
            case .fastVLM_1_5b_int8:   return 800
            case .graniteDocling_258m: return 631
            case .graniteVision_3_3:   return 1_200
        }
    }
    
    /// Default prompt for document/OCR extraction.
    /// Returns `nil` for non-specialized models.
    public var defaultDocumentPrompt: String? {
        switch self {
            case .fastVLM_0_5b_fp16, .fastVLM_1_5b_int8:
                return """
            You are a receipt OCR assistant. Extract all information from this receipt image \
            and return a JSON object with keys: store, date (YYYY-MM-DD), \
            items (array of {name, quantity, price}), subtotal, tax, total, currency. \
            Respond ONLY with valid JSON, no markdown.
            """
            case .graniteDocling_258m:
                return "Convert this page to docling."
            case .graniteVision_3_3:
                return "Describe the image in detail."
            default:
                return nil
        }
    }
    
    // MARK: - Storage
    
    /// Local cache directory where MLX downloads the model.
    /// Mirrors the `<org>/<repo>` folder structure used by mlx-swift.
    public var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models")
            .appendingPathComponent(rawValue)
    }
    
    /// Returns `true` if the model directory exists on disk.
    public var isDownloaded: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: cacheDirectory.path,
            isDirectory: &isDir
        )
        return exists && isDir.boolValue
    }
}

// MARK: - Convenience collections

public extension Model {
    /// All text-generation models, downloaded first.
    static var textModels: [Model] {
        allCases
            .filter { if case .text = $0.purpose { true } else { false } }
            .sorted { $0.isDownloaded && !$1.isDownloaded }
    }
    /// All general-purpose vision models, downloaded first.
    static var visionModels: [Model] {
        allCases
            .filter { if case .vision = $0.purpose { true } else { false } }
            .sorted { $0.isDownloaded && !$1.isDownloaded }
    }
    /// All OCR / document-specialized vision models, downloaded first.
    static var specializedModels: [Model] {
        allCases
            .filter { if case .visionSpecialized = $0.purpose { true } else { false } }
            .sorted { $0.isDownloaded && !$1.isDownloaded }
    }
}
