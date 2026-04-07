import Foundation
import SwiftUI
import AVFoundation
import Speech

class VoiceCommandService: ObservableObject {
    @Published var isListening = false
    @Published var transcription = ""
    @Published var error: Error?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self.isListening = true
                case .denied, .restricted, .notDetermined:
                    self.isListening = false
                @unknown default:
                    self.isListening = false
                }
            }
        }
    }

    func startListening() {
        if audioEngine.isRunning {
            stopListening()
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                self.transcription = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = error
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = error
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionRequest = nil
            recognitionTask = nil
        }
    }
}

struct VoiceCommandView: View {
    @StateObject private var voiceCommandService = VoiceCommandService()

    var body: some View {
        VStack {
            Text("Voice Command Interface")
                .font(.largeTitle)
                .padding()

            Text(voiceCommandService.transcription)
                .font(.title)
                .padding()

            Button(action: {
                if voiceCommandService.isListening {
                    voiceCommandService.startListening()
                } else {
                    voiceCommandService.stopListening()
                }
            }) {
                Text(voiceCommandService.isListening ? "Stop Listening" : "Start Listening")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()

            if let error = voiceCommandService.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

struct VoiceCommands_Previews: PreviewProvider {
    static var previews: some View {
        VoiceCommandView()
    }
}