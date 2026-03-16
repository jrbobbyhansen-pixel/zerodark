// VoiceSynthesis.swift
// Give your AI an actual voice — including YOUR voice
// Supports Apple Personal Voice, system voices, and custom voice models

import Foundation
import AVFoundation

#if os(iOS)
#if canImport(UIKit)
import UIKit
#endif
#endif

// MARK: - Voice Synthesis Engine

@MainActor
public final class VoiceSynthesisEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    
    public static let shared = VoiceSynthesisEngine()
    
    // MARK: - Published State
    
    @Published public var isSpeaking: Bool = false
    @Published public var availableVoices: [VoiceOption] = []
    @Published public var selectedVoice: VoiceOption?
    @Published public var personalVoiceAvailable: Bool = false
    
    // MARK: - Voice Option
    
    public struct VoiceOption: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let language: String
        public let quality: VoiceQuality
        public let isPersonalVoice: Bool
        public let sampleText: String
        
        public enum VoiceQuality: String {
            case `default` = "Default"
            case enhanced = "Enhanced"
            case premium = "Premium"
            case personal = "Personal"
        }
        
        public init(voice: AVSpeechSynthesisVoice) {
            self.id = voice.identifier
            self.name = voice.name
            self.language = voice.language
            self.quality = voice.quality == .enhanced ? .enhanced : .default
            self.isPersonalVoice = false
            self.sampleText = "Hello, I'm \(voice.name)"
        }
        
        public init(id: String, name: String, language: String, quality: VoiceQuality, isPersonalVoice: Bool) {
            self.id = id
            self.name = name
            self.language = language
            self.quality = quality
            self.isPersonalVoice = isPersonalVoice
            self.sampleText = "Hello, I'm \(name)"
        }
    }
    
    // MARK: - Private Properties
    
    private let synthesizer = AVSpeechSynthesizer()
    private var onComplete: (() -> Void)?
    
    // MARK: - Init
    
    private override init() {
        super.init()
        synthesizer.delegate = self
        loadAvailableVoices()
        checkPersonalVoiceAvailability()
    }
    
    // MARK: - Voice Loading
    
    private func loadAvailableVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Group by language, prefer enhanced voices
        var voiceOptions: [VoiceOption] = []
        
        for voice in voices {
            // Filter to English voices for simplicity (can expand later)
            if voice.language.starts(with: "en") {
                let option = VoiceOption(voice: voice)
                voiceOptions.append(option)
            }
        }
        
        // Sort: enhanced first, then by name
        voiceOptions.sort { v1, v2 in
            if v1.quality == .enhanced && v2.quality != .enhanced { return true }
            if v1.quality != .enhanced && v2.quality == .enhanced { return false }
            return v1.name < v2.name
        }
        
        availableVoices = voiceOptions
        
        // Set default voice
        if selectedVoice == nil, let first = voiceOptions.first {
            selectedVoice = first
        }
    }
    
    private func checkPersonalVoiceAvailability() {
        // Personal Voice available in iOS 17+
        if #available(iOS 17.0, macOS 14.0, *) {
            // Check if user has set up Personal Voice
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                Task { @MainActor in
                    self.personalVoiceAvailable = (status == .authorized)
                    
                    if self.personalVoiceAvailable {
                        // Add Personal Voice as an option
                        let personalOption = VoiceOption(
                            id: "personal_voice",
                            name: "Your Voice",
                            language: "en-US",
                            quality: .personal,
                            isPersonalVoice: true
                        )
                        self.availableVoices.insert(personalOption, at: 0)
                    }
                }
            }
        }
    }
    
    // MARK: - Speech Synthesis
    
    /// Speak text with the configured voice
    public func speak(_ text: String, completion: (() -> Void)? = nil) {
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        onComplete = completion
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Apply voice settings
        if let voiceOption = selectedVoice {
            if voiceOption.isPersonalVoice {
                // Use Personal Voice
                if #available(iOS 17.0, macOS 14.0, *) {
                    // Personal Voice uses a special voice type
                    utterance.voice = AVSpeechSynthesisVoice(identifier: voiceOption.id)
                }
            } else {
                utterance.voice = AVSpeechSynthesisVoice(identifier: voiceOption.id)
            }
        }
        
        // Apply identity settings
        Task {
            let identity = await AgentIdentity.shared.getIdentity()
            utterance.rate = identity.voice.speed * AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0 + identity.voice.pitch
        }
        
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    /// Stop speaking
    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    /// Preview a voice
    public func previewVoice(_ voice: VoiceOption) {
        let utterance = AVSpeechUtterance(string: voice.sampleText)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voice.id)
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        onComplete?()
        onComplete = nil
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

// MARK: - Voice Recording for Cloning

#if os(iOS)

@MainActor
public final class VoiceRecorder: NSObject, ObservableObject {
    
    public static let shared = VoiceRecorder()
    
    @Published public var isRecording: Bool = false
    @Published public var recordedSamples: [URL] = []
    @Published public var recordingProgress: Double = 0
    
    private var audioRecorder: AVAudioRecorder?
    
    // Sample phrases for voice cloning
    public let samplePhrases: [String] = [
        "The quick brown fox jumps over the lazy dog.",
        "Hello, this is my voice for my AI assistant.",
        "I love how technology makes life easier every day.",
        "Pack my box with five dozen liquor jugs.",
        "How vexingly quick daft zebras jump."
    ]
    
    private override init() {
        super.init()
    }
    
    /// Request microphone permission
    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// Start recording a sample
    public func startRecording(sampleIndex: Int) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("voice_sample_\(sampleIndex).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
        audioRecorder?.record()
        isRecording = true
    }
    
    /// Stop recording
    public func stopRecording() -> URL? {
        guard let recorder = audioRecorder else { return nil }
        
        recorder.stop()
        isRecording = false
        
        let url = recorder.url
        recordedSamples.append(url)
        recordingProgress = Double(recordedSamples.count) / Double(samplePhrases.count)
        
        return url
    }
    
    /// Check if all samples are recorded
    public var allSamplesRecorded: Bool {
        recordedSamples.count >= samplePhrases.count
    }
    
    /// Clear all recorded samples
    public func clearSamples() {
        for url in recordedSamples {
            try? FileManager.default.removeItem(at: url)
        }
        recordedSamples = []
        recordingProgress = 0
    }
}

#else

// macOS stub
@MainActor
public final class VoiceRecorder: ObservableObject {
    public static let shared = VoiceRecorder()
    
    @Published public var isRecording: Bool = false
    @Published public var recordedSamples: [URL] = []
    @Published public var recordingProgress: Double = 0
    
    public let samplePhrases: [String] = [
        "The quick brown fox jumps over the lazy dog.",
        "Hello, this is my voice for my AI assistant.",
        "I love how technology makes life easier every day.",
        "Pack my box with five dozen liquor jugs.",
        "How vexingly quick daft zebras jump."
    ]
    
    public func requestPermission() async -> Bool { return false }
    public func startRecording(sampleIndex: Int) throws {}
    public func stopRecording() -> URL? { return nil }
    public var allSamplesRecorded: Bool { false }
    public func clearSamples() {}
}

#endif

// MARK: - Voice Cloning (Future)

/// Voice cloning using recorded samples
/// This would integrate with a voice cloning model (e.g., Coqui TTS, XTTS)
public actor VoiceCloner {
    
    public static let shared = VoiceCloner()
    
    public enum CloneStatus {
        case notStarted
        case recording(progress: Double)
        case processing
        case ready
        case error(String)
    }
    
    public var status: CloneStatus = .notStarted
    
    /// Create a voice clone from recorded samples
    public func createVoiceClone(fromSamples samples: [URL]) async throws -> URL {
        status = .processing
        
        // In production:
        // 1. Load samples
        // 2. Extract voice features
        // 3. Train/fine-tune voice model
        // 4. Save model to disk
        // 5. Return model path
        
        // For now, return a placeholder
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = documentsPath.appendingPathComponent("custom_voice_model.bin")
        
        // Simulate processing time
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        status = .ready
        return modelPath
    }
    
    /// Generate speech using cloned voice
    public func synthesize(text: String, modelPath: URL) async throws -> Data {
        // In production:
        // 1. Load voice model
        // 2. Run TTS inference
        // 3. Return audio data
        
        // Placeholder
        return Data()
    }
}
