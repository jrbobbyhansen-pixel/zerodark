// PTTController.swift — Push-to-Talk Voice Comms
// Captures and streams audio over mesh network

import AVFoundation
import Foundation

@MainActor
final class PTTController: ObservableObject {
    static let shared = PTTController()

    @Published var isTransmitting = false
    @Published var isReceiving = false
    @Published var activeSpeaker: String? = nil

    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }

    // Shared playback engine (not per-call) to avoid audio session conflicts
    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private init() {
        // Setup playback engine once
        playbackEngine.attach(playerNode)
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: nil)
    }

    func startTransmit() {
        Task {
            guard await requestMicPermission() else { return }
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let data = buffer.toData() else { return }
                Task { @MainActor [weak self] in
                    self?.transmitBuffer(data: data)
                }
            }
            try? audioEngine.start()
            isTransmitting = true
        }
    }

    func stopTransmit() {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isTransmitting = false
    }

    func receiveAudio(data: Data, fromPeer peerName: String) {
        activeSpeaker = peerName
        isReceiving = true

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false),
              let buffer = data.toPCMBuffer(format: format) else {
            isReceiving = false
            return
        }

        // Use shared playback engine
        if !playerNode.isPlaying {
            try? playbackEngine.start()
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.isReceiving = false
                self?.activeSpeaker = nil
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func transmitBuffer(data: Data) {
        MeshService.shared.broadcastAudio(data: data, callsign: AppConfig.deviceCallsign)
    }

    private func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

// MARK: - AVAudioPCMBuffer Helpers

extension AVAudioPCMBuffer {
    func toData() -> Data? {
        guard let channelData = floatChannelData else { return nil }
        let frameLength = Int(frameLength)
        return Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)
    }
}

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(count / MemoryLayout<Float>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        self.withUnsafeBytes { ptr in
            buffer.floatChannelData?[0].update(
                from: ptr.bindMemory(to: Float.self).baseAddress!,
                count: Int(frameCount)
            )
        }
        return buffer
    }
}
