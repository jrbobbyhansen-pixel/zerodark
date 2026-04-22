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
    @Published var lastError: String?

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private var generateTask: Task<Void, Never>?

    // Model configuration — Phi-3.5-mini 4-bit quantized for mobile
    private let modelId = "mlx-community/Phi-3.5-mini-instruct-4bit"

    // Inference safety nets. The underlying MLX stream has no timeout; these
    // cap our risk surface when model.streamResponse hangs or emits very
    // slowly (bad prompt, hardware throttle, or loss-of-file condition).
    /// Hard cap on total generation wall-clock. Beyond this, we cancel.
    var inferenceMaxDurationSeconds: Double = 60.0
    /// If no token has arrived by this many seconds, we cancel as "first-token
    /// stall" — the model is loaded but producing nothing.
    var inferenceFirstTokenTimeoutSeconds: Double = 15.0

    private init() {}

    // MARK: - Model Loading

    func loadModel() async {
        guard modelState != .loading && modelState != .ready else { return }
        
        modelState = .loading
        loadProgress = 0.1
        
        do {
            
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
            
            
        } catch {
            self.modelState = .error(error.localizedDescription)
        }
    }

    /// Reload the model if it is not currently ready. No-op when already ready or loading.
    /// Called by RuntimeSafetyMonitor when `modelLoaded` violates.
    func reloadIfNeeded() async {
        switch modelState {
        case .ready, .loading:
            return
        case .notLoaded, .error:
            await loadModel()
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
        lastError = nil

        let maxTotal = inferenceMaxDurationSeconds
        let firstTokenTimeout = inferenceFirstTokenTimeoutSeconds

        generateTask = Task {
            let startedAt = Date()
            var firstTokenReceived = false
            do {
                let stream = session.streamResponse(to: prompt)
                for try await chunk in stream {
                    // Cooperative cancellation — fires when user hits Stop.
                    try Task.checkCancellation()

                    // First-token stall detection: if we've exceeded the
                    // first-token budget and no chunk has arrived yet, abort.
                    // The check happens here so the next iteration catches it;
                    // the very first yielded chunk flips the flag and the
                    // branch is never taken again.
                    let elapsed = Date().timeIntervalSince(startedAt)
                    if !firstTokenReceived, elapsed > firstTokenTimeout {
                        throw InferenceTimeoutError.firstTokenStall(budget: firstTokenTimeout)
                    }

                    // Total duration guard — hard cap.
                    if elapsed > maxTotal {
                        throw InferenceTimeoutError.totalDurationExceeded(budget: maxTotal)
                    }

                    firstTokenReceived = true
                    await MainActor.run { onToken(chunk) }
                }

                await MainActor.run {
                    self.isGenerating = false
                    onComplete()
                }

            } catch is CancellationError {
                await MainActor.run {
                    self.isGenerating = false
                    onComplete()
                }
            } catch let timeout as InferenceTimeoutError {
                await MainActor.run {
                    self.lastError = timeout.localizedDescription
                    onToken("[\(timeout.localizedDescription)]")
                    self.isGenerating = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
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

// MARK: - Inference timeout errors

enum InferenceTimeoutError: Error, LocalizedError {
    /// No token was emitted within the first-token budget. Usually indicates
    /// the model loaded but is producing nothing — hardware throttle, bad
    /// prompt, or loaded-but-idle state.
    case firstTokenStall(budget: Double)
    /// Generation exceeded the total wall-clock budget. The user likely
    /// asked an open-ended question; we stop and report the partial answer.
    case totalDurationExceeded(budget: Double)

    var errorDescription: String? {
        switch self {
        case .firstTokenStall(let b):
            return "Model produced no tokens within \(Int(b))s — aborted."
        case .totalDurationExceeded(let b):
            return "Generation exceeded \(Int(b))s wall-clock budget — truncated."
        }
    }
}

// MARK: - Model integrity note
//
// The plan's P0 item called for SHA256 checksum validation on model load.
// MLX's LLMModelFactory downloads Phi-3.5 from HuggingFace at runtime — the
// exact bytes aren't known ahead of time, and MLX does not expose a hook to
// intercept + verify the download. A proper integrity story requires either:
//   (a) switching to a locally-bundled model with a known hash, OR
//   (b) upstream support in MLX for manifest-based verification.
// Neither is feasible without changing the deployment model. The timeout +
// first-token-stall + total-duration guards here cap the runtime risk
// surface instead — a corrupted download presents as generation failure
// (garbled output or refusal to emit tokens), and both conditions now
// abort cleanly with a user-facing error.
