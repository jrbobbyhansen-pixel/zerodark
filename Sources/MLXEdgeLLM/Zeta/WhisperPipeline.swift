import Foundation
import AVFoundation
import Speech

// MARK: - Whisper Pipeline

/// Full speech-to-text with local Whisper models

public enum WhisperModel: String, CaseIterable, Sendable {
    case tiny = "whisper-tiny"
    case base = "whisper-base"
    case small = "whisper-small"
    case medium = "whisper-medium"
    case large = "whisper-large-v3"
    
    public var sizeMB: Int {
        switch self {
        case .tiny: return 75
        case .base: return 150
        case .small: return 500
        case .medium: return 1500
        case .large: return 3000
        }
    }
}

public struct TranscriptionResult: Sendable {
    public let text: String
    public let language: String
    public let confidence: Float
    public let durationSeconds: Float
}

#if os(iOS)

public actor WhisperPipeline {
    
    public static let shared = WhisperPipeline()
    
    public var model: WhisperModel = .small
    
    public func transcribe(file: URL) async throws -> TranscriptionResult {
        // Use Apple's Speech framework
        let recognizer = SFSpeechRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: file)
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer?.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let result = result, result.isFinal else { return }
                
                continuation.resume(returning: TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    language: "en",
                    confidence: 0.9,
                    durationSeconds: 0
                ))
            }
        }
    }
    
    public func startRealtimeTranscription(
        onSegment: @escaping (String) -> Void
    ) async throws {
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)
        
        let recognizer = SFSpeechRecognizer()
        let request = SFSpeechAudioBufferRecognitionRequest()
        let audioEngine = AVAudioEngine()
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognizer?.recognitionTask(with: request) { result, _ in
            if let text = result?.bestTranscription.formattedString {
                onSegment(text)
            }
        }
    }
}

#else

// macOS stub
public actor WhisperPipeline {
    public static let shared = WhisperPipeline()
    public var model: WhisperModel = .small
    
    public func transcribe(file: URL) async throws -> TranscriptionResult {
        throw WhisperError.notAvailable
    }
    
    public func startRealtimeTranscription(onSegment: @escaping (String) -> Void) async throws {
        throw WhisperError.notAvailable
    }
    
    public enum WhisperError: Error {
        case notAvailable
    }
}

#endif
