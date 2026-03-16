//
//  MLXInference.swift
//  ZeroDark
//
//  Real MLX inference using mlx-swift-lm
//

import SwiftUI
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXRandom

// MARK: - MLX Model Manager

@MainActor
public class MLXModelManager: ObservableObject {
    public static let shared = MLXModelManager()
    
    @Published public var isLoading = false
    @Published public var loadProgress: Double = 0
    @Published public var currentModelId: String?
    @Published public var isReady = false
    @Published public var error: String?
    @Published public var tokensPerSecond: Double = 0
    
    // Available models
    public let availableModels: [ModelInfo] = [
        ModelInfo(id: "mlx-community/Qwen2.5-3B-Instruct-4bit", name: "Qwen 3B", size: "1.8 GB", recommended: true),
        ModelInfo(id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3B", size: "1.8 GB", recommended: false),
        ModelInfo(id: "mlx-community/gemma-2-2b-it-4bit", name: "Gemma 2B", size: "1.4 GB", recommended: false),
        ModelInfo(id: "mlx-community/SmolLM-135M-Instruct-4bit", name: "SmolLM 135M", size: "100 MB", recommended: false),
    ]
    
    // Loaded model container
    private var modelContainer: ModelContainer?
    
    public struct ModelInfo: Identifiable {
        public let id: String
        public let name: String
        public let size: String
        public let recommended: Bool
    }
    
    // MARK: - Load Model
    
    public func loadModel(_ modelId: String) async throws {
        isLoading = true
        loadProgress = 0
        error = nil
        
        defer { isLoading = false }
        
        do {
            // Get configuration from registry or create default
            let config = ModelConfiguration(id: modelId)
            
            // Load the model
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.loadProgress = progress.fractionCompleted
                }
            }
            
            currentModelId = modelId
            isReady = true
            
        } catch {
            self.error = error.localizedDescription
            isReady = false
            throw error
        }
    }
    
    // MARK: - Generate
    
    public func generate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7
    ) async throws -> String {
        guard let container = modelContainer else {
            throw MLXError.modelNotLoaded
        }
        
        let startTime = Date()
        var tokenCount = 0
        var output = ""
        
        // Create generation parameters
        let parameters = GenerateParameters(
            temperature: temperature,
            topP: 0.9,
            repetitionPenalty: 1.1
        )
        
        // Generate
        let result = try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: .text(prompt)))
            
            return try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            ) { tokens in
                tokenCount = tokens.count
                if tokenCount >= maxTokens {
                    return .stop
                }
                return .more
            }
        }
        
        output = result.output
        
        let elapsed = Date().timeIntervalSince(startTime)
        tokensPerSecond = Double(tokenCount) / max(0.001, elapsed)
        
        return output
    }
    
    // MARK: - Stream Generate
    
    public func streamGenerate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let container = modelContainer else {
            throw MLXError.modelNotLoaded
        }
        
        let parameters = GenerateParameters(
            temperature: temperature,
            topP: 0.9
        )
        
        var tokenCount = 0
        
        try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: .text(prompt)))
            
            return try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            ) { tokens in
                tokenCount = tokens.count
                
                // Decode latest token
                if let lastToken = tokens.last {
                    let decoded = context.tokenizer.decode(tokens: [lastToken])
                    onToken(decoded)
                }
                
                if tokenCount >= maxTokens {
                    return .stop
                }
                return .more
            }
        }
    }
    
    enum MLXError: Error, LocalizedError {
        case modelNotLoaded
        case generationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "No model loaded"
            case .generationFailed(let msg):
                return "Generation failed: \(msg)"
            }
        }
    }
}

// MARK: - Unified Inference Engine

@MainActor
public class UnifiedInferenceEngine: ObservableObject {
    public static let shared = UnifiedInferenceEngine()
    
    private let modelManager = MLXModelManager.shared
    
    @Published public var isGenerating = false
    
    /// Main generate function - used by all systems
    public func generate(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 512,
        temperature: Float = 0.7
    ) async -> String {
        // Auto-load model if not ready
        if !modelManager.isReady && !modelManager.isLoading {
            if let recommended = modelManager.availableModels.first(where: { $0.recommended }) {
                try? await modelManager.loadModel(recommended.id)
            }
        }
        
        guard modelManager.isReady else {
            if modelManager.isLoading {
                return "[Loading model... \(Int(modelManager.loadProgress * 100))%]"
            }
            return "[No model loaded. Go to More → Models to download one.]"
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        var fullPrompt = prompt
        if let system = systemPrompt {
            fullPrompt = "System: \(system)\n\nUser: \(prompt)\n\nAssistant:"
        }
        
        do {
            return try await modelManager.generate(
                prompt: fullPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        } catch {
            return "[Error: \(error.localizedDescription)]"
        }
    }
    
    /// Stream generate with callback
    public func streamGenerate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        onToken: @escaping (String) -> Void
    ) async {
        guard modelManager.isReady else {
            onToken("[No model loaded]")
            return
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            try await modelManager.streamGenerate(
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                onToken: onToken
            )
        } catch {
            onToken("[Error: \(error.localizedDescription)]")
        }
    }
}

// MARK: - Model Manager View

struct ModelManagerView: View {
    @StateObject private var manager = MLXModelManager.shared
    
    var body: some View {
        List {
            if manager.isLoading {
                Section {
                    VStack(spacing: 12) {
                        ProgressView(value: manager.loadProgress)
                            .tint(.cyan)
                        Text("\(Int(manager.loadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            if let error = manager.error {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Section("Current Model") {
                if let current = manager.currentModelId {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(current.components(separatedBy: "/").last ?? current)
                        Spacer()
                        if manager.isReady {
                            Text("Ready")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    Text("No model loaded")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Available Models") {
                ForEach(manager.availableModels) { model in
                    ModelRowView(model: model)
                }
            }
            
            if manager.isReady {
                Section("Stats") {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text("\(manager.tokensPerSecond, specifier: "%.1f") tok/s")
                            .foregroundColor(.cyan)
                    }
                }
            }
        }
        .navigationTitle("Models")
    }
}

struct ModelRowView: View {
    let model: MLXModelManager.ModelInfo
    @StateObject private var manager = MLXModelManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.headline)
                    if model.recommended {
                        Text("Recommended")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.2))
                            .foregroundColor(.cyan)
                            .cornerRadius(4)
                    }
                }
                Text(model.size)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Load") {
                Task {
                    try? await manager.loadModel(model.id)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(manager.isLoading || manager.currentModelId == model.id)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ModelManagerView()
    }
    .preferredColorScheme(.dark)
}
