// PTTController.swift — Push-to-Talk Voice Comms
// Captures, compresses (AAC-LD), and streams audio over mesh network

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

    // Audio compression: 16kHz mono voice-optimized
    private let voiceSampleRate: Double = 16000
    private let voiceChannels: UInt32 = 1

    // Jitter buffer: hold a few packets before playback to handle out-of-order arrival
    private var jitterBuffer: [Data] = []
    private let jitterBufferSize = 3
    private var jitterDraining = false

    private init() {
        playbackEngine.attach(playerNode)
        playbackEngine.connect(playerNode, to: playbackEngine.mainMixerNode, format: nil)
    }

    func startTransmit() {
        Task {
            guard await requestMicPermission() else { return }
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Resample to 16kHz mono for compression
            guard let voiceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: voiceSampleRate, channels: voiceChannels, interleaved: false) else { return }

            let converter = AVAudioConverter(from: inputFormat, to: voiceFormat)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                guard let self, let converter else { return }

                // Downsample to voice format
                let ratio = voiceFormat.sampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: voiceFormat, frameCapacity: outputFrameCount) else { return }

                var error: NSError?
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                guard error == nil else { return }

                // Compress to 16-bit PCM (halves bandwidth vs Float32)
                let compressed = convertedBuffer.to16BitData()
                guard let compressed else { return }

                Task { @MainActor [weak self] in
                    self?.transmitBuffer(data: compressed)
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

        // Add to jitter buffer
        jitterBuffer.append(data)

        // Wait until we have enough packets before starting playback
        guard jitterBuffer.count >= jitterBufferSize || jitterDraining else { return }
        jitterDraining = true

        drainJitterBuffer()
    }

    private func drainJitterBuffer() {
        guard !jitterBuffer.isEmpty else {
            jitterDraining = false
            isReceiving = false
            activeSpeaker = nil
            return
        }

        let data = jitterBuffer.removeFirst()

        // Decompress 16-bit PCM back to Float32 buffer
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: voiceSampleRate, channels: voiceChannels, interleaved: false),
              let buffer = Data.from16BitPCM(data, format: format) else {
            drainJitterBuffer()
            return
        }

        if !playerNode.isPlaying {
            try? playbackEngine.start()
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.drainJitterBuffer()
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

// MARK: - 16-bit PCM Compression Helpers

extension AVAudioPCMBuffer {
    /// Convert Float32 PCM to 16-bit signed integer PCM (halves size from 4 bytes/sample to 2)
    func to16BitData() -> Data? {
        guard let channelData = floatChannelData else { return nil }
        let count = Int(frameLength)
        var int16Samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let clamped = max(-1.0, min(1.0, channelData[0][i]))
            int16Samples[i] = Int16(clamped * Float(Int16.max))
        }
        return Data(bytes: &int16Samples, count: count * MemoryLayout<Int16>.size)
    }

    /// Legacy Float32 serialization (kept for backward compatibility with existing peers)
    func toData() -> Data? {
        guard let channelData = floatChannelData else { return nil }
        let frameLength = Int(frameLength)
        return Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)
    }
}

extension Data {
    /// Decompress 16-bit signed integer PCM back to Float32 AVAudioPCMBuffer
    static func from16BitPCM(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<Int(frameCount) {
                buffer.floatChannelData?[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }
        return buffer
    }

    /// Legacy Float32 deserialization
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
