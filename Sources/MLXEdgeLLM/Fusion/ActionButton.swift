// ActionButton.swift — iPhone 15/16 Pro Action Button Integration

import SwiftUI
import AVFoundation
import AppIntents
import Speech

// MARK: - Action Button Handler

@MainActor
final class ActionButtonHandler: ObservableObject {
    static let shared = ActionButtonHandler()
    
    @Published var isListening = false
    @Published var lastTranscription: String?
    @Published var processingState: ProcessingState = .idle
    
    enum ProcessingState {
        case idle
        case listening
        case transcribing
        case thinking
        case responding
    }
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
    private init() {}
    
    // MARK: - Quick Voice Query
    
    /// Called when Action Button is pressed (via App Intent)
    func handleActionButtonPress() async {
        switch processingState {
        case .idle:
            await startVoiceCapture()
        case .listening:
            await stopAndProcess()
        default:
            // Already processing, ignore
            break
        }
    }
    
    private func startVoiceCapture() async {
        processingState = .listening
        isListening = true
        
        // Request microphone permission
        let permission = await AVAudioApplication.requestRecordPermission()
        guard permission else {
            processingState = .idle
            isListening = false
            return
        }
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            print("[ActionButton] Audio session error: \(error)")
            processingState = .idle
            isListening = false
            return
        }
        
        // Start recording
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("action_button_\(Date().timeIntervalSince1970).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()
            
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("[ActionButton] Recording error: \(error)")
            processingState = .idle
            isListening = false
        }
    }
    
    private func stopAndProcess() async {
        audioRecorder?.stop()
        isListening = false
        processingState = .transcribing
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        guard let url = recordingURL else {
            processingState = .idle
            return
        }
        
        // Transcribe with Whisper (placeholder - wire to actual implementation)
        let transcription = await transcribeAudio(url: url)
        lastTranscription = transcription
        
        // Process with tactical system (LLM removed)
        processingState = .thinking
        let response = "Tactical system: '\(transcription)'"

        // Speak response (optional)
        processingState = .responding
        await speakResponse(response)
        
        // Cleanup
        try? FileManager.default.removeItem(at: url)
        processingState = .idle
    }
    
    private func transcribeAudio(url: URL) async -> String {
        // Attempt to transcribe audio using Speech Recognition framework first
        let recognizer = SFSpeechRecognizer()
        guard recognizer?.isAvailable == true else {
            return await transcribeViaMLX(url: url)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            recognizer?.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let result = result, result.isFinal {
                    hasResumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error = error {
                    hasResumed = true
                    // Fallback to MLX-based transcription
                    Task {
                        let mlxTranscript = await self.transcribeViaMLX(url: url)
                        continuation.resume(returning: mlxTranscript)
                    }
                }
            }
        }
    }

    private func transcribeViaMLX(url: URL) async -> String {
        // Fallback: Use MLX with a speech recognition model if available
        // Load audio and pass to Whisper-style model (if present in model catalog)
        do {
            let data = try Data(contentsOf: url)
            // This would require a Whisper-compatible model in MLX
            // For now, return transcription placeholder
            // In production, this would use mlx-swift with a Whisper model
            return "Transcription via MLX (audio processing)"
        } catch {
            return "Unable to transcribe audio"
        }
    }
    
    private func speakResponse(_ text: String) async {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        synthesizer.speak(utterance)
        
        // Wait for speech to complete
        while synthesizer.isSpeaking {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    
    // MARK: - Quick Scan Mode
    
    func handleQuickScan() async {
        // Start LiDAR scan when Action Button is used in scan mode
        guard LiDARCaptureEngine.shared.isLiDARAvailable else {
            print("[ActionButton] LiDAR not available on this device")
            return
        }

        processingState = .thinking

        do {
            try await LiDARCaptureEngine.shared.startScan()
            processingState = .idle
        } catch {
            print("[ActionButton] LiDAR scan error: \(error)")
            processingState = .idle
        }
    }
    
    // MARK: - Emergency Mode
    
    func handleEmergencyPress() async {
        // Triple-press or long-press triggers emergency
        await MeshService.shared.broadcastSOS()

        // Strong haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}

// MARK: - Action Button App Intent

@available(iOS 17.0, *)
struct ActionButtonVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "ZeroDark Voice"
    static var description = IntentDescription("Quick voice query via Action Button")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        await ActionButtonHandler.shared.handleActionButtonPress()
        return .result()
    }
}

@available(iOS 17.0, *)
struct ActionButtonScanIntent: AppIntent {
    static var title: LocalizedStringResource = "ZeroDark Scan"
    static var description = IntentDescription("Quick scan via Action Button")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        await ActionButtonHandler.shared.handleQuickScan()
        return .result()
    }
}

// MARK: - Action Button Status View

struct ActionButtonStatusView: View {
    @StateObject var handler = ActionButtonHandler.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(statusColor)
                    .frame(width: 80, height: 80)
                    .scaleEffect(handler.isListening ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: handler.isListening)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            
            Text(statusText)
                .font(.headline)
                .foregroundColor(.primary)
            
            if let transcription = handler.lastTranscription {
                Text(transcription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
    
    private var statusColor: Color {
        switch handler.processingState {
        case .idle: return .gray
        case .listening: return .red
        case .transcribing: return .orange
        case .thinking: return ZDDesign.forestGreen
        case .responding: return .blue
        }
    }
    
    private var statusIcon: String {
        switch handler.processingState {
        case .idle: return "mic"
        case .listening: return "waveform"
        case .transcribing: return "text.bubble"
        case .thinking: return "brain"
        case .responding: return "speaker.wave.2"
        }
    }
    
    private var statusText: String {
        switch handler.processingState {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .thinking: return "Thinking..."
        case .responding: return "Speaking..."
        }
    }
}
