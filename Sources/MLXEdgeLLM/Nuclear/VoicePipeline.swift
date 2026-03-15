import Foundation
import AVFoundation
import Speech

// MARK: - Voice Pipeline

/// Full on-device voice pipeline: STT → LLM → TTS
@MainActor
public final class VoicePipeline: NSObject, ObservableObject {
    
    public static let shared = VoicePipeline()
    
    // MARK: - State
    
    public enum PipelineState: String {
        case idle = "Idle"
        case listening = "Listening"
        case processing = "Processing"
        case speaking = "Speaking"
        case error = "Error"
    }
    
    @Published public var state: PipelineState = .idle
    @Published public var transcription: String = ""
    @Published public var response: String = ""
    @Published public var isAvailable: Bool = false
    @Published public var errorMessage: String?
    @Published public var audioLevel: Float = 0
    
    // MARK: - Audio
    
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var synthesizer: AVSpeechSynthesizer?
    
    // MARK: - Configuration
    
    public struct VoiceConfig {
        public var language: String = "en-US"
        public var voiceIdentifier: String? = nil  // nil = system default
        public var speakingRate: Float = 0.5  // 0.0 - 1.0
        public var pitchMultiplier: Float = 1.0
        public var volume: Float = 1.0
        public var silenceTimeout: TimeInterval = 2.0  // Auto-stop after silence
        
        public static let `default` = VoiceConfig()
    }
    
    public var config = VoiceConfig()
    
    // MARK: - Callbacks
    
    public var onTranscriptionComplete: ((String) -> Void)?
    public var onResponseReady: ((String) -> Void)?
    public var onSpeechComplete: (() -> Void)?
    
    // MARK: - Init
    
    private override init() {
        super.init()
        setupComponents()
    }
    
    private func setupComponents() {
        // Speech recognizer
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: config.language))
        
        // Synthesizer
        synthesizer = AVSpeechSynthesizer()
        synthesizer?.delegate = self
        
        // Check availability
        Task {
            await checkAvailability()
        }
    }
    
    // MARK: - Availability
    
    public func checkAvailability() async {
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        // Request microphone permission
        let audioStatus = await AVAudioApplication.shared.requestRecordPermission()
        
        await MainActor.run {
            isAvailable = speechStatus == .authorized && audioStatus
            
            if !isAvailable {
                if speechStatus != .authorized {
                    errorMessage = "Speech recognition not authorized"
                } else if !audioStatus {
                    errorMessage = "Microphone access not authorized"
                }
            }
        }
    }
    
    // MARK: - Listen (STT)
    
    public func startListening() throws {
        guard isAvailable else {
            throw VoiceError.notAvailable
        }
        
        guard state == .idle else {
            throw VoiceError.alreadyRunning
        }
        
        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw VoiceError.audioEngineUnavailable
        }
        
        let inputNode = audioEngine.inputNode
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true  // On-device only!
        
        // Start recognition
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                Task { @MainActor in
                    self.transcription = result.bestTranscription.formattedString
                }
                
                if result.isFinal {
                    Task { @MainActor in
                        self.stopListening()
                        self.onTranscriptionComplete?(self.transcription)
                    }
                }
            }
            
            if let error = error {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                    self.state = .error
                }
            }
        }
        
        // Configure audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            
            // Calculate audio level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += abs(channelData[i])
            }
            let avg = sum / Float(frameLength)
            
            Task { @MainActor in
                self?.audioLevel = avg * 10  // Scale for visibility
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        state = .listening
        transcription = ""
    }
    
    public func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        
        if state == .listening {
            state = .idle
        }
        
        audioLevel = 0
    }
    
    // MARK: - Speak (TTS)
    
    public func speak(_ text: String) {
        guard let synthesizer = synthesizer else { return }
        
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        response = text
        state = .speaking
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Configure voice
        if let voiceId = config.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: config.language)
        }
        
        utterance.rate = config.speakingRate
        utterance.pitchMultiplier = config.pitchMultiplier
        utterance.volume = config.volume
        
        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
        }
        
        synthesizer.speak(utterance)
    }
    
    public func stopSpeaking() {
        synthesizer?.stopSpeaking(at: .immediate)
        state = .idle
    }
    
    // MARK: - Full Pipeline
    
    /// Run the full pipeline: Listen → Process with LLM → Speak response
    public func runPipeline(
        processWithLLM: @escaping (String) async -> String
    ) async throws {
        // Start listening
        try startListening()
        
        // Wait for transcription to complete
        let transcribedText = await withCheckedContinuation { continuation in
            self.onTranscriptionComplete = { text in
                continuation.resume(returning: text)
            }
        }
        
        // Process with LLM
        state = .processing
        let llmResponse = await processWithLLM(transcribedText)
        
        // Speak response
        speak(llmResponse)
        
        // Wait for speech to complete
        await withCheckedContinuation { continuation in
            self.onSpeechComplete = {
                continuation.resume()
            }
        }
        
        state = .idle
    }
    
    // MARK: - Available Voices
    
    public var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix(String(config.language.prefix(2)))
        }
    }
    
    public var enhancedVoices: [AVSpeechSynthesisVoice] {
        availableVoices.filter { $0.quality == .enhanced }
    }
    
    // MARK: - Errors
    
    public enum VoiceError: Error, LocalizedError {
        case notAvailable
        case alreadyRunning
        case audioEngineUnavailable
        case requestCreationFailed
        
        public var errorDescription: String? {
            switch self {
            case .notAvailable: return "Voice features not available"
            case .alreadyRunning: return "Voice pipeline already running"
            case .audioEngineUnavailable: return "Audio engine not available"
            case .requestCreationFailed: return "Failed to create recognition request"
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoicePipeline: AVSpeechSynthesizerDelegate {
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            state = .idle
            onSpeechComplete?()
        }
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            state = .idle
        }
    }
}

// MARK: - Whisper Integration (Future)

/// Placeholder for on-device Whisper integration
/// When Apple ships their Whisper-based on-device transcription, 
/// or we integrate whisper.cpp via MLX
public struct WhisperTranscriber {
    
    public enum WhisperModel: String {
        case tiny = "whisper-tiny"
        case base = "whisper-base"
        case small = "whisper-small"
        case medium = "whisper-medium"
    }
    
    public static func isAvailable() -> Bool {
        // Check if whisper models are downloaded
        // This would integrate with mlx-whisper when available
        return false
    }
    
    public static func transcribe(
        audioURL: URL,
        model: WhisperModel = .base
    ) async throws -> String {
        // Future: Integrate with mlx-whisper
        throw NSError(domain: "WhisperTranscriber", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Whisper transcription not yet implemented. Using Apple Speech."
        ])
    }
}

// MARK: - Wake Word Detection

/// Simple wake word detection using Speech Recognition
public actor WakeWordDetector {
    
    public static let shared = WakeWordDetector()
    
    private var isListening = false
    private var wakeWords: [String] = ["hey zero", "okay zero", "zero dark"]
    
    public var onWakeWordDetected: (() -> Void)?
    
    public func setWakeWords(_ words: [String]) {
        wakeWords = words.map { $0.lowercased() }
    }
    
    public func start() async throws {
        // Continuous low-power listening for wake words
        // Implementation would use a lightweight acoustic model
        // For now, this is a placeholder
        isListening = true
    }
    
    public func stop() {
        isListening = false
    }
    
    public func checkForWakeWord(in text: String) -> Bool {
        let lower = text.lowercased()
        return wakeWords.contains { lower.contains($0) }
    }
}
