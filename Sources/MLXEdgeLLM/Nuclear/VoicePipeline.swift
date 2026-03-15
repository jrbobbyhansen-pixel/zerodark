import Foundation
import AVFoundation
import Speech

// MARK: - Voice Pipeline

/// Full on-device voice pipeline: STT → LLM → TTS

#if os(iOS)

@MainActor
public final class VoicePipeline: NSObject, ObservableObject {
    
    public static let shared = VoicePipeline()
    
    public enum PipelineState: String {
        case idle, listening, processing, speaking, error
    }
    
    @Published public var state: PipelineState = .idle
    @Published public var transcription: String = ""
    @Published public var response: String = ""
    @Published public var isAvailable: Bool = false
    @Published public var errorMessage: String?
    
    public var onTranscriptionComplete: ((String) -> Void)?
    
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var synthesizer = AVSpeechSynthesizer()
    
    private override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        checkAvailability()
    }
    
    private func checkAvailability() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                self.isAvailable = status == .authorized
            }
        }
    }
    
    public func startListening() throws {
        guard isAvailable else { throw VoiceError.notAuthorized }
        
        state = .listening
        audioEngine = AVAudioEngine()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let audioEngine = audioEngine,
              let recognitionRequest = recognitionRequest else {
            throw VoiceError.setupFailed
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                Task { @MainActor in
                    self.transcription = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.onTranscriptionComplete?(self.transcription)
                    }
                }
            }
        }
    }
    
    public func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        state = .idle
    }
    
    public func speak(_ text: String) {
        state = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
        
        // Reset state after speaking
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(text.count) * 0.05) {
            self.state = .idle
        }
    }
    
    public enum VoiceError: Error {
        case notAuthorized
        case setupFailed
    }
}

#else

// macOS stub
@MainActor
public final class VoicePipeline: ObservableObject {
    public static let shared = VoicePipeline()
    
    public enum PipelineState: String {
        case idle, listening, processing, speaking, error
    }
    
    @Published public var state: PipelineState = .idle
    @Published public var transcription: String = ""
    @Published public var response: String = ""
    @Published public var isAvailable: Bool = false
    @Published public var errorMessage: String?
    
    public var onTranscriptionComplete: ((String) -> Void)?
    
    public func startListening() throws {
        throw VoiceError.notAvailable
    }
    
    public func stopListening() {}
    
    public func speak(_ text: String) {
        // Could use NSSpeechSynthesizer on macOS
    }
    
    public enum VoiceError: Error {
        case notAvailable
    }
}

#endif
