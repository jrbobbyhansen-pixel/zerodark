import Foundation
import SwiftUI
import AVFoundation
import CryptoKit

// MARK: - SecureVoiceManager

class SecureVoiceManager: ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var autoDeleteEnabled = false
    @Published var autoDeleteTime: TimeInterval = 3600 // 1 hour

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var encryptedData: Data?

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        audioRecorder = try? AVAudioRecorder(url: audioFilename, settings: settings)
        audioRecorder?.record()
        isRecording = true
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        encryptAudio()
    }

    // MARK: - Playback

    func startPlayback() {
        guard !isPlaying else { return }

        guard let encryptedData = encryptedData else { return }

        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        do {
            try encryptedData.write(to: audioFilename)
            audioPlayer = try AVAudioPlayer(contentsOf: audioFilename)
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Failed to start playback: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
    }

    // MARK: - Encryption

    private func encryptAudio() {
        guard let audioData = audioRecorder?.url else { return }

        do {
            let data = try Data(contentsOf: audioData)
            let key = SymmetricKey(size: .aes256)
            let sealedBox = try AES.GCM.seal(data, using: key)
            encryptedData = sealedBox.encryptedData
        } catch {
            print("Failed to encrypt audio: \(error)")
        }
    }

    // MARK: - Auto-Delete

    func scheduleAutoDelete() {
        guard autoDeleteEnabled else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + autoDeleteTime) {
            self.deleteAudio()
        }
    }

    private func deleteAudio() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        try? FileManager.default.removeItem(at: audioFilename)
        encryptedData = nil
    }

    // MARK: - Utilities

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

// MARK: - SecureVoiceView

struct SecureVoiceView: View {
    @StateObject private var manager = SecureVoiceManager()

    var body: some View {
        VStack {
            Button(action: {
                if manager.isRecording {
                    manager.stopRecording()
                } else {
                    manager.startRecording()
                }
            }) {
                Text(manager.isRecording ? "Stop Recording" : "Start Recording")
            }
            .padding()

            Button(action: {
                if manager.isPlaying {
                    manager.stopPlayback()
                } else {
                    manager.startPlayback()
                }
            }) {
                Text(manager.isPlaying ? "Stop Playback" : "Start Playback")
            }
            .padding()

            Toggle("Auto Delete", isOn: $manager.autoDeleteEnabled)
                .onChange(of: manager.autoDeleteEnabled) { enabled in
                    if enabled {
                        manager.scheduleAutoDelete()
                    }
                }

            Slider(value: $manager.autoDeleteTime, in: 60...3600, step: 60)
                .padding()
                .disabled(!manager.autoDeleteEnabled)
        }
        .onAppear {
            manager.scheduleAutoDelete()
        }
    }
}

// MARK: - Preview

struct SecureVoiceView_Previews: PreviewProvider {
    static var previews: some View {
        SecureVoiceView()
    }
}