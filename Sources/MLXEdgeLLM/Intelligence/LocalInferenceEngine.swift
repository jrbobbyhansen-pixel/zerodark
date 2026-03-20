// LocalInferenceEngine.swift
// ZeroDark — MLX Swift Implementation

import Foundation
import MLX
import MLXLLM
import MLXLMCommon

@MainActor
final class LocalInferenceEngine: ObservableObject {
    static let shared = LocalInferenceEngine()

    enum ModelState: Equatable {
        case notLoaded, loading, ready, error(String)
        static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.notLoaded, .notLoaded), (.loading, .loading), (.ready, .ready): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    @Published var modelState: ModelState = .notLoaded
    @Published var loadProgress: Double = 0.0
    @Published var isGenerating: Bool = false

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private var generateTask: Task<Void, Never>?

    // Model configuration — Phi-3.5-mini 4-bit quantized for mobile
    private let modelId = "mlx-community/Phi-3.5-mini-instruct-4bit"

    private init() {}

    // MARK: - Model Loading

    func loadModel() async {
        guard modelState != .loading && modelState != .ready else { return }
        
        modelState = .loading
        loadProgress = 0.1
        
        do {
            print("[ZeroDark] LocalInferenceEngine: Loading MLX model \(modelId)...")
            
            let configuration = ModelConfiguration(id: modelId)
            
            // Load with progress tracking
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.loadProgress = progress.fractionCompleted
                }
            }
            
            self.modelContainer = container
            
            // Create chat session with tactical advisor system prompt
            self.chatSession = ChatSession(
                container,
                instructions: """
                You are a tactical field advisor embedded in a survival/field operations app. \
                Your role is to provide direct, actionable guidance based on field manual content. \
                Prioritize critical safety steps first. Be concise but complete. \
                If asked about something outside your context, say so clearly.
                """
            )
            
            self.loadProgress = 1.0
            self.modelState = .ready
            
            print("[ZeroDark] LocalInferenceEngine: Model loaded successfully")
            
        } catch {
            print("[ZeroDark] LocalInferenceEngine: Failed to load model: \(error)")
            self.modelState = .error(error.localizedDescription)
        }
    }

    // MARK: - Text Generation

    func generate(
        prompt: String,
        maxTokens: Int = 512,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard let session = chatSession, modelState == .ready else {
            onToken("[Model not loaded — tap to load]")
            onComplete()
            return
        }
        
        isGenerating = true
        
        generateTask = Task {
            do {
                // Use streaming response
                let stream = session.streamResponse(to: prompt)
                
                for try await chunk in stream {
                    await MainActor.run {
                        onToken(chunk)
                    }
                }
                
                await MainActor.run {
                    self.isGenerating = false
                    onComplete()
                }
                
            } catch {
                await MainActor.run {
                    onToken("[Generation error: \(error.localizedDescription)]")
                    self.isGenerating = false
                    onComplete()
                }
            }
        }
    }

    // MARK: - RAG-Augmented Generation

    func generateWithContext(
        query: String,
        context: String,
        maxTokens: Int = 512,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        let augmentedPrompt = """
        FIELD MANUAL CONTEXT:
        \(context)

        OPERATOR QUESTION:
        \(query)

        Provide a direct, actionable answer based on the field manual context above. \
        Prioritize critical steps first. If the context doesn't contain relevant information, say so.
        """
        
        generate(prompt: augmentedPrompt, maxTokens: maxTokens, onToken: onToken, onComplete: onComplete)
    }

    // MARK: - Control

    func cancel() {
        generateTask?.cancel()
        generateTask = nil
        isGenerating = false
    }

    func cancelGeneration() {
        cancel()
    }

    func unloadModel() {
        chatSession = nil
        modelContainer = nil
        modelState = .notLoaded
        loadProgress = 0.0
    }

    // MARK: - Model Info

    var modelFileExists: Bool {
        // MLX downloads models on-demand from HuggingFace
        return true
    }

    static var modelPath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Models")
    }
}
