import Foundation
import Speech
import Observation

// MARK: - Protocol (swap LocalLLMStub for real MLXEdgeLLM implementation)

protocol LLMProvider {
    func generate(prompt: String) async -> String
}

// MARK: - Stub (replace with MLXEdgeLLM)

struct LocalLLMStub: LLMProvider {
    func generate(prompt: String) async -> String {
        // Simulate thinking time
        try? await Task.sleep(nanoseconds: 800_000_000)
        return """
        [Model not loaded]
        
        To enable on-device inference, integrate MLXEdgeLLM:
        
        1. Add MLXEdgeLLM via Swift Package Manager:
           https://github.com/ml-explore/mlx-swift-examples
        
        2. Download a model (e.g. Qwen3-0.6B-4bit):
           from HuggingFace on first launch over WiFi
        
        3. Replace LocalLLMStub with:
           LLMModelContainer(modelName: "mlx-community/Qwen3-0.6B-4bit")
        
        Once loaded, all inference runs on the A18 Pro Neural Engine
        with zero network calls. ~200–500MB storage required.
        
        Your prompt was: "\(prompt.prefix(100))"
        """
    }
}

// MARK: - Message Model

enum MessageRole: String, Codable {
    case user, assistant
}

struct ConversationMessage: Codable, Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
    }
}

// MARK: - View Model

@Observable
final class LLMAssistantViewModel {
    var messages: [ConversationMessage] = []
    var isGenerating = false
    var isListeningForVoice = false
    var voiceTranscript = ""
    var modelStatus = "Model not loaded — integrate MLXEdgeLLM"
    var sessionFilename: String?

    private var provider: LLMProvider = LocalLLMStub()
    private let vault = VaultManager.shared
    private var sessionStart: Date?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        if sessionStart == nil { sessionStart = .now }
        let userMsg = ConversationMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        isGenerating = true

        // Build context (last 6 messages)
        let context = messages.suffix(6).map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        let response = await provider.generate(prompt: context)

        let assistantMsg = ConversationMessage(role: .assistant, content: response)
        messages.append(assistantMsg)
        isGenerating = false
        saveSession()
    }

    // MARK: - Voice Input

    func startVoiceInput() {
        guard !isListeningForVoice else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self else { return }
            do {
                try self.startRecognizing()
            } catch {
                print("Voice input error: \(error)")
            }
        }
    }

    func stopVoiceInput() -> String {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isListeningForVoice = false
        return voiceTranscript
    }

    private func startRecognizing() throws {
        recognizer = SFSpeechRecognizer(locale: .current)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        isListeningForVoice = true
        voiceTranscript = ""

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                DispatchQueue.main.async {
                    self?.voiceTranscript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                DispatchQueue.main.async { self?.isListeningForVoice = false }
            }
        }
    }

    // MARK: - Persistence

    private func saveSession() {
        guard let start = sessionStart else { return }
        let formatter = ISO8601DateFormatter()
        let filename = "llm_session_\(formatter.string(from: start)).json"
        try? vault.saveJSON(messages, filename: filename)
        sessionFilename = filename
    }
}

// Needed for AVAudioEngine in LLMAssistant
import AVFoundation
