import Foundation
import AVFoundation
import Speech
import Observation

// MARK: - Protocol (swap LocalLLMStub for real MLXEdgeLLM implementation)

protocol LLMProvider {
    func generate(prompt: String) async -> String
}

// MARK: - Stub (replace with MLXEdgeLLM)

struct LocalLLMStub: LLMProvider {
    func generate(prompt: String) async -> String {
        try? await Task.sleep(nanoseconds: 800_000_000)
        return """
        [Model not loaded]

        To enable on-device inference, integrate MLXEdgeLLM:

        1. Add package: https://github.com/ml-explore/mlx-swift-examples
        2. Download model (e.g. Qwen3-0.6B-4bit) on first launch over WiFi
        3. Replace LocalLLMStub with MLXProvider (see README)

        All inference runs on the A18 Pro Neural Engine — zero network calls.
        ~200–500MB storage required.
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

    // Voice input — property so stopVoiceInput() can actually stop it
    private let voiceAudioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    // MARK: - Chat

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        if sessionStart == nil { sessionStart = .now }
        messages.append(ConversationMessage(role: .user, content: trimmed))
        isGenerating = true

        // Build context window (last 6 messages)
        let context = messages.suffix(6)
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n")
        let response = await provider.generate(prompt: context)

        messages.append(ConversationMessage(role: .assistant, content: response))
        isGenerating = false
        saveSession()
    }

    // MARK: - Voice Input

    func startVoiceInput() {
        guard !isListeningForVoice else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self else { return }
            do { try self.startRecognizing() } catch {
                print("Voice input error: \(error)")
            }
        }
    }

    func stopVoiceInput() -> String {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        if voiceAudioEngine.isRunning {
            voiceAudioEngine.stop()
            voiceAudioEngine.inputNode.removeTap(onBus: 0)
        }
        isListeningForVoice = false
        return voiceTranscript
    }

    private func startRecognizing() throws {
        recognizer = SFSpeechRecognizer(locale: .current)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, options: [.allowBluetooth])
        try session.setActive(true)

        let inputNode = voiceAudioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        voiceAudioEngine.prepare()
        try voiceAudioEngine.start()

        isListeningForVoice = true
        voiceTranscript = ""

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async { self.voiceTranscript = result.bestTranscription.formattedString }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async { _ = self.stopVoiceInput() }
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
