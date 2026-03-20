// HAMMERAcousticModem.swift — Acoustic Steganography System
// Swift port of Raytheon HAMMER for covert data transmission over audio

import Foundation
import AVFoundation
import Accelerate
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HAMMER Configuration

struct HAMMERConfig {
    // Frequency domain parameters
    let carrierFrequency: Double = 18000.0  // Hz - above most hearing
    let bandwidth: Double = 2000.0           // Hz
    let symbolRate: Double = 100.0           // symbols/second
    let sampleRate: Double = 44100.0         // Hz
    
    // Modulation parameters
    let bitsPerSymbol: Int = 4               // 16-QAM
    let guardInterval: Double = 0.001        // 1ms guard
    let preambleLength: Int = 64             // sync preamble symbols
    
    // Error correction
    let useConvolutionalCoding: Bool = true
    let codeRate: Double = 0.5               // 1/2 rate
    let interleaverDepth: Int = 8
    
    // Steganography
    let embedInMusic: Bool = true
    let maxEmbedPower: Double = -40.0        // dB below carrier
}

// MARK: - Symbol Modulation

enum HAMMERModulation {
    case bpsk    // 1 bit/symbol - most robust
    case qpsk    // 2 bits/symbol
    case qam16   // 4 bits/symbol
    case qam64   // 6 bits/symbol - highest throughput
    
    var bitsPerSymbol: Int {
        switch self {
        case .bpsk: return 1
        case .qpsk: return 2
        case .qam16: return 4
        case .qam64: return 6
        }
    }
    
    var constellation: [(Double, Double)] {
        switch self {
        case .bpsk:
            return [(-1, 0), (1, 0)]
        case .qpsk:
            let v = 1.0 / sqrt(2.0)
            return [(-v, -v), (-v, v), (v, -v), (v, v)]
        case .qam16:
            var points: [(Double, Double)] = []
            for i in [-3, -1, 1, 3] {
                for q in [-3, -1, 1, 3] {
                    points.append((Double(i) / sqrt(10), Double(q) / sqrt(10)))
                }
            }
            return points
        case .qam64:
            var points: [(Double, Double)] = []
            for i in stride(from: -7, through: 7, by: 2) {
                for q in stride(from: -7, through: 7, by: 2) {
                    points.append((Double(i) / sqrt(42), Double(q) / sqrt(42)))
                }
            }
            return points
        }
    }
}

// MARK: - HAMMER Packet Structure

struct HAMMERPacket {
    let preamble: [UInt8]      // Sync pattern
    let header: HAMMERHeader   // Packet metadata
    let payload: Data          // Encrypted data
    let crc: UInt32            // CRC-32 checksum
    let timestamp: Date
}

struct HAMMERHeader {
    let version: UInt8 = 1
    let packetType: PacketType
    let sequenceNumber: UInt16
    let payloadLength: UInt16
    let sourceId: UInt32
    let destinationId: UInt32
    let flags: UInt8
    
    enum PacketType: UInt8 {
        case data = 0x01
        case ack = 0x02
        case beacon = 0x03
        case keyExchange = 0x04
        case emergency = 0xFF
    }
}

// MARK: - HAMMER Acoustic Modem

@MainActor
final class HAMMERAcousticModem: ObservableObject {
    static let shared = HAMMERAcousticModem()
    
    // Published state
    @Published var isTransmitting = false
    @Published var isReceiving = false
    @Published var signalStrength: Double = 0
    @Published var lastReceivedPacket: HAMMERPacket?
    @Published var transmissionProgress: Double = 0
    @Published var errorRate: Double = 0
    
    // Configuration
    private let config = HAMMERConfig()
    private var modulation: HAMMERModulation = .qam16
    
    // Audio engine
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var inputNode: AVAudioInputNode?
    
    // Signal processing
    private var fftSetup: vDSP_DFT_Setup?
    private let fftLength = 4096
    private var receiveBuffer: [Float] = []
    private var transmitBuffer: [Float] = []
    
    // Cryptography
    private var sessionKey: SymmetricKey?
    private var sequenceNumber: UInt16 = 0
    private let deviceId: UInt32
    
    // Callbacks
    var onPacketReceived: ((HAMMERPacket) -> Void)?
    var onTransmissionComplete: ((Bool) -> Void)?
    
    private init() {
        #if canImport(UIKit)
        deviceId = UInt32(truncatingIfNeeded: UIDevice.current.identifierForVendor?.hashValue ?? 0)
        #else
        deviceId = UInt32.random(in: 0...UInt32.max)
        #endif
        setupFFT()
    }
    
    // MARK: - Setup
    
    private func setupFFT() {
        fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftLength),
            .FORWARD
        )
    }
    
    func initialize() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)

        inputNode = engine.inputNode

        try engine.start()
    }

    /// Set the shared session key for encryption/decryption.
    /// Must be called before transmitting data.
    func setSessionKey(_ key: SymmetricKey) {
        sessionKey = key
    }

    /// Check if a session key has been set
    var isKeySet: Bool { sessionKey != nil }

    /// Convenience transmit: UTF-8 encodes message and calls transmit(data:)
    func transmit(message: String) async throws {
        guard let data = message.data(using: .utf8) else { return }
        try await transmit(data: data)
    }

    /// Start passive listening; decrypts received packets and decodes as UTF-8 strings
    func startListening(onReceive: @escaping (String) -> Void) {
        onPacketReceived = { [weak self] packet in
            guard let key = self?.sessionKey,
                  let sealed = try? AES.GCM.SealedBox(combined: packet.payload),
                  let decrypted = try? AES.GCM.open(sealed, using: key),
                  let text = String(data: decrypted, encoding: .utf8) else { return }
            onReceive(text)
        }
        startReceiving()
    }

    /// Stop passive listening
    func stopListening() {
        stopReceiving()
    }

    // MARK: - Transmission
    
    func transmit(data: Data, to destinationId: UInt32? = nil) async throws {
        isTransmitting = true
        transmissionProgress = 0
        
        defer { 
            isTransmitting = false 
            transmissionProgress = 1.0
        }
        
        // Encrypt payload
        let encryptedPayload = try encryptPayload(data)
        
        // Build packet
        let packet = HAMMERPacket(
            preamble: generatePreamble(),
            header: HAMMERHeader(
                packetType: .data,
                sequenceNumber: nextSequenceNumber(),
                payloadLength: UInt16(encryptedPayload.count),
                sourceId: deviceId,
                destinationId: destinationId ?? 0xFFFFFFFF,  // Broadcast
                flags: 0
            ),
            payload: encryptedPayload,
            crc: calculateCRC(encryptedPayload),
            timestamp: Date()
        )
        
        // Encode to symbols
        let symbols = encodePacket(packet)
        
        // Modulate to audio
        let audioSamples = modulateSymbols(symbols)
        
        // Transmit
        try await playAudio(samples: audioSamples)
        
        onTransmissionComplete?(true)
    }
    
    func transmitWithCover(data: Data, coverAudio: AVAudioFile) async throws {
        // Embed data in cover audio using steganography
        isTransmitting = true
        
        defer { isTransmitting = false }
        
        let encryptedPayload = try encryptPayload(data)
        let symbols = encodePacket(HAMMERPacket(
            preamble: generatePreamble(),
            header: HAMMERHeader(
                packetType: .data,
                sequenceNumber: nextSequenceNumber(),
                payloadLength: UInt16(encryptedPayload.count),
                sourceId: deviceId,
                destinationId: 0xFFFFFFFF,
                flags: 0
            ),
            payload: encryptedPayload,
            crc: calculateCRC(encryptedPayload),
            timestamp: Date()
        ))
        
        // Read cover audio
        let format = coverAudio.processingFormat
        let frameCount = AVAudioFrameCount(coverAudio.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw HAMMERError.bufferCreationFailed
        }
        try coverAudio.read(into: buffer)
        
        // Embed covert signal
        let stegoBuffer = embedSignal(symbols: symbols, in: buffer)
        
        // Play combined audio
        try await playBuffer(stegoBuffer)
    }
    
    // MARK: - Reception
    
    func startReceiving() {
        guard let inputNode = inputNode else { return }
        isReceiving = true
        receiveBuffer = []
        
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.processReceivedAudio(buffer)
        }
    }
    
    func stopReceiving() {
        inputNode?.removeTap(onBus: 0)
        isReceiving = false
    }
    
    private func processReceivedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Append to receive buffer
        receiveBuffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Process when we have enough samples
        while receiveBuffer.count >= fftLength {
            let samples = Array(receiveBuffer.prefix(fftLength))
            receiveBuffer.removeFirst(fftLength)
            
            // Detect and demodulate signal
            if let packet = demodulateAndDecode(samples: samples) {
                Task { @MainActor in
                    self.lastReceivedPacket = packet
                    self.onPacketReceived?(packet)
                }
            }
            
            // Update signal strength
            Task { @MainActor in
                self.signalStrength = self.measureSignalStrength(samples)
            }
        }
    }
    
    // MARK: - Signal Processing
    
    private func modulateSymbols(_ symbols: [Int]) -> [Float] {
        var samples: [Float] = []
        let samplesPerSymbol = Int(config.sampleRate / config.symbolRate)
        let constellation = modulation.constellation
        
        for symbol in symbols {
            let (i, q) = constellation[symbol % constellation.count]
            
            for n in 0..<samplesPerSymbol {
                let t = Double(n) / config.sampleRate
                let phase = 2.0 * .pi * config.carrierFrequency * t
                
                // QAM modulation: s(t) = I*cos(wt) - Q*sin(wt)
                let sample = Float(i * cos(phase) - q * sin(phase))
                samples.append(sample * 0.1)  // Scale for audio output
            }
        }
        
        // Apply raised cosine pulse shaping
        return applyPulseShaping(samples)
    }
    
    private func demodulateAndDecode(samples: [Float]) -> HAMMERPacket? {
        // FFT to frequency domain
        guard let setup = fftSetup else {
            print("[HAMMER] FFT setup unavailable — skipping demodulation")
            return nil
        }

        var realPart = [Float](repeating: 0, count: fftLength)
        var imagPart = [Float](repeating: 0, count: fftLength)

        let success = samples.withUnsafeBufferPointer { samplesPtr -> Bool in
            guard let samplesBase = samplesPtr.baseAddress else {
                print("[HAMMER] Samples buffer has no base address")
                return false
            }
            return realPart.withUnsafeMutableBufferPointer { realPtr -> Bool in
                guard let realBase = realPtr.baseAddress else {
                    print("[HAMMER] Real buffer has no base address")
                    return false
                }
                return imagPart.withUnsafeMutableBufferPointer { imagPtr -> Bool in
                    guard let imagBase = imagPtr.baseAddress else {
                        print("[HAMMER] Imaginary buffer has no base address")
                        return false
                    }
                    vDSP_DFT_Execute(
                        setup,
                        samplesBase,
                        [Float](repeating: 0, count: fftLength),
                        realBase,
                        imagBase
                    )
                    return true
                }
            }
        }

        guard success else { return nil }
        
        // Find carrier frequency bin
        let binWidth = config.sampleRate / Double(fftLength)
        let carrierBin = Int(config.carrierFrequency / binWidth)
        let bandwidthBins = Int(config.bandwidth / binWidth)
        
        // Check for signal presence
        var signalPower: Float = 0
        for i in (carrierBin - bandwidthBins/2)...(carrierBin + bandwidthBins/2) {
            if i >= 0 && i < fftLength/2 {
                signalPower += realPart[i] * realPart[i] + imagPart[i] * imagPart[i]
            }
        }
        
        guard signalPower > 0.001 else { return nil }  // No signal detected
        
        // Demodulate symbols
        let symbols = extractSymbols(real: realPart, imag: imagPart, carrierBin: carrierBin)
        
        // Decode packet
        return decodePacket(symbols: symbols)
    }
    
    private func extractSymbols(real: [Float], imag: [Float], carrierBin: Int) -> [Int] {
        var symbols: [Int] = []
        let constellation = modulation.constellation
        let bandwidthBins = Int(config.bandwidth / (config.sampleRate / Double(fftLength)))

        // Extract symbols from multiple bins in the frequency band
        // Use weighted averaging across the bandwidth for better noise immunity
        var totalI: Double = 0.0
        var totalQ: Double = 0.0
        var weightSum: Double = 0.0

        // Window function weights (Hann window for spectral efficiency)
        for binOffset in (-bandwidthBins/2)...(bandwidthBins/2) {
            let bin = carrierBin + binOffset
            guard bin >= 0 && bin < fftLength/2 else { continue }

            // Hann window weight - peak at center, tapers to edges
            let relativePos = Double(binOffset) / Double(bandwidthBins / 2 + 1)
            let weight = 0.5 * (1.0 + cos(.pi * relativePos))

            totalI += Double(real[bin]) * weight
            totalQ += Double(imag[bin]) * weight
            weightSum += weight
        }

        // Normalize by window sum
        if weightSum > 0 {
            totalI /= weightSum
            totalQ /= weightSum
        }

        // Map I/Q to nearest constellation point
        var minDistance = Double.greatestFiniteMagnitude
        var nearestSymbol = 0

        for (index, point) in constellation.enumerated() {
            let distance = (totalI - point.0) * (totalI - point.0) + (totalQ - point.1) * (totalQ - point.1)
            if distance < minDistance {
                minDistance = distance
                nearestSymbol = index
            }
        }

        symbols.append(nearestSymbol)
        return symbols
    }
    
    private func embedSignal(symbols: [Int], in buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData?[0] else { return buffer }
        let frameCount = Int(buffer.frameLength)
        
        // Generate covert signal
        let covertSignal = modulateSymbols(symbols)
        
        // Embed at low power in high frequency band
        let embedGain = Float(pow(10, config.maxEmbedPower / 20))  // Convert dB to linear
        
        for i in 0..<min(frameCount, covertSignal.count) {
            channelData[i] += covertSignal[i] * embedGain
        }
        
        return buffer
    }
    
    private func applyPulseShaping(_ samples: [Float]) -> [Float] {
        // Raised cosine filter
        let beta: Float = 0.35  // Roll-off factor
        let span = 6
        let sps = Int(config.sampleRate / config.symbolRate)
        
        var filter = [Float](repeating: 0, count: span * sps + 1)
        let halfLen = filter.count / 2
        
        for i in 0..<filter.count {
            let t = Float(i - halfLen) / Float(sps)
            if abs(t) < 0.0001 {
                filter[i] = 1.0
            } else if abs(abs(t) - 1.0 / (2.0 * beta)) < 0.0001 {
                filter[i] = .pi / 4.0 * sin(.pi / (2.0 * beta)) / (.pi / (2.0 * beta))
            } else {
                let num = sin(.pi * t) * cos(.pi * beta * t)
                let den = .pi * t * (1.0 - pow(2.0 * beta * t, 2))
                filter[i] = num / den
            }
        }
        
        // Convolve
        var output = [Float](repeating: 0, count: samples.count + filter.count - 1)
        vDSP_conv(samples, 1, filter, 1, &output, 1, vDSP_Length(output.count), vDSP_Length(filter.count))
        
        return Array(output.prefix(samples.count))
    }
    
    private func measureSignalStrength(_ samples: [Float]) -> Double {
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        return Double(10 * log10(sumSquares / Float(samples.count) + 1e-10))
    }
    
    // MARK: - Packet Encoding/Decoding
    
    private func encodePacket(_ packet: HAMMERPacket) -> [Int] {
        var bits: [UInt8] = []
        
        // Preamble
        bits.append(contentsOf: packet.preamble)
        
        // Header
        bits.append(packet.header.version)
        bits.append(packet.header.packetType.rawValue)
        bits.append(UInt8(packet.header.sequenceNumber >> 8))
        bits.append(UInt8(packet.header.sequenceNumber & 0xFF))
        bits.append(UInt8(packet.header.payloadLength >> 8))
        bits.append(UInt8(packet.header.payloadLength & 0xFF))
        bits.append(contentsOf: withUnsafeBytes(of: packet.header.sourceId.bigEndian) { Array($0) })
        bits.append(contentsOf: withUnsafeBytes(of: packet.header.destinationId.bigEndian) { Array($0) })
        bits.append(packet.header.flags)
        
        // Payload
        bits.append(contentsOf: packet.payload)
        
        // CRC
        bits.append(contentsOf: withUnsafeBytes(of: packet.crc.bigEndian) { Array($0) })
        
        // Apply convolutional coding if enabled
        if config.useConvolutionalCoding {
            bits = convolutionalEncode(bits)
        }
        
        // Interleave
        bits = interleave(bits)
        
        // Convert to symbols
        return bitsToSymbols(bits)
    }
    
    private func decodePacket(symbols: [Int]) -> HAMMERPacket? {
        var bits = symbolsToBits(symbols)
        
        // Deinterleave
        bits = deinterleave(bits)
        
        // Viterbi decode if convolutional coding used
        if config.useConvolutionalCoding {
            bits = viterbiDecode(bits)
        }
        
        // Parse packet structure
        guard bits.count >= 20 else { return nil }
        
        // Verify CRC
        let payloadEnd = bits.count - 4
        let receivedCRC = UInt32(bits[payloadEnd]) << 24 |
                          UInt32(bits[payloadEnd + 1]) << 16 |
                          UInt32(bits[payloadEnd + 2]) << 8 |
                          UInt32(bits[payloadEnd + 3])
        
        let payloadData = Data(bits[16..<payloadEnd])
        let calculatedCRC = calculateCRC(payloadData)
        
        guard receivedCRC == calculatedCRC else {
            Task { @MainActor in self.errorRate += 0.01 }
            return nil
        }
        
        // Decrypt payload
        guard let decryptedPayload = try? decryptPayload(payloadData) else { return nil }
        
        return HAMMERPacket(
            preamble: Array(bits[0..<config.preambleLength]),
            header: HAMMERHeader(
                packetType: HAMMERHeader.PacketType(rawValue: bits[config.preambleLength + 1]) ?? .data,
                sequenceNumber: UInt16(bits[config.preambleLength + 2]) << 8 | UInt16(bits[config.preambleLength + 3]),
                payloadLength: UInt16(bits[config.preambleLength + 4]) << 8 | UInt16(bits[config.preambleLength + 5]),
                sourceId: UInt32(bits[config.preambleLength + 6]) << 24 |
                          UInt32(bits[config.preambleLength + 7]) << 16 |
                          UInt32(bits[config.preambleLength + 8]) << 8 |
                          UInt32(bits[config.preambleLength + 9]),
                destinationId: UInt32(bits[config.preambleLength + 10]) << 24 |
                               UInt32(bits[config.preambleLength + 11]) << 16 |
                               UInt32(bits[config.preambleLength + 12]) << 8 |
                               UInt32(bits[config.preambleLength + 13]),
                flags: bits[config.preambleLength + 14]
            ),
            payload: decryptedPayload,
            crc: receivedCRC,
            timestamp: Date()
        )
    }
    
    // MARK: - Cryptography
    
    private func encryptPayload(_ data: Data) throws -> Data {
        guard let key = sessionKey else {
            print("[HAMMER] No session key established — call setSessionKey() before transmitting")
            throw HAMMERError.noSessionKey
        }

        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(data, using: key, nonce: nonce)

        return sealed.combined ?? Data()
    }
    
    private func decryptPayload(_ data: Data) throws -> Data {
        guard let key = sessionKey else { throw HAMMERError.noSessionKey }
        
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    // MARK: - Helper Functions
    
    private func generatePreamble() -> [UInt8] {
        // Barker code for synchronization
        let barker13: [UInt8] = [1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1]
        var preamble: [UInt8] = []
        for _ in 0..<(config.preambleLength / 13) {
            preamble.append(contentsOf: barker13)
        }
        return Array(preamble.prefix(config.preambleLength))
    }
    
    private func nextSequenceNumber() -> UInt16 {
        sequenceNumber += 1
        return sequenceNumber
    }
    
    private func calculateCRC(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }
    
    private func convolutionalEncode(_ input: [UInt8]) -> [UInt8] {
        // Rate 1/2, constraint length 7 convolutional code
        var output: [UInt8] = []
        var state: UInt8 = 0
        
        for byte in input {
            for bit in 0..<8 {
                let inputBit = (byte >> (7 - bit)) & 1
                state = ((state << 1) | inputBit) & 0x3F
                
                // G1 = 1111001 (octal 171)
                let g1 = (state & 0x01) ^ ((state >> 1) & 0x01) ^ ((state >> 2) & 0x01) ^
                         ((state >> 3) & 0x01) ^ ((state >> 5) & 0x01)
                // G2 = 1011011 (octal 133)
                let g2 = (state & 0x01) ^ ((state >> 1) & 0x01) ^ ((state >> 3) & 0x01) ^
                         ((state >> 4) & 0x01) ^ ((state >> 5) & 0x01)
                
                output.append(g1)
                output.append(g2)
            }
        }
        return output
    }
    
    private func viterbiDecode(_ input: [UInt8]) -> [UInt8] {
        // Rate-1/2, constraint-length-7 Viterbi decoder
        // Standard NASA convolutional code with G1=171, G2=133 (octal)

        let numStates = 64  // 2^(K-1) = 2^6
        let g1: [UInt8] = [0,1,1,0,1,0,0,1,1,0,0,1,0,1,1,0,1,0,0,1,0,1,1,0,0,1,1,0,1,0,0,1,
                           1,0,0,1,0,1,1,0,0,1,1,0,1,0,0,1,0,1,1,0,1,0,0,1,1,0,0,1,0,1,1,0]
        let g2: [UInt8] = [0,1,1,0,0,1,1,0,1,0,0,1,1,0,0,1,1,0,0,1,1,0,0,1,0,1,1,0,0,1,1,0,
                           1,0,0,1,1,0,0,1,0,1,1,0,0,1,1,0,1,0,0,1,1,0,0,1,0,1,1,0,0,1,1,0]

        var pathMetrics = [Int](repeating: 0, count: numStates)
        var survivalPath = [[UInt8]](repeating: [UInt8](), count: numStates)

        // Initialize survival paths for each state
        for state in 0..<numStates {
            survivalPath[state] = []
        }

        // Process each pair of input bits (one symbol)
        for symbolIdx in 0..<input.count/2 {
            let bit0 = Int(input[symbolIdx * 2])
            let bit1 = Int(input[symbolIdx * 2 + 1])

            var newPathMetrics = [Int](repeating: Int.max, count: numStates)
            var newSurvivalPath = [[UInt8]](repeating: [UInt8](), count: numStates)

            // For each current state, compute two possible next states
            for state in 0..<numStates {
                // Input bit 0 -> next state without data bit
                for inputBit in 0..<2 {
                    let nextState = ((state << 1) | inputBit) & 0x3F

                    // Compute expected output bits
                    let expectedG1 = g1[nextState]
                    let expectedG2 = g2[nextState]

                    // Calculate branch metric (Hamming distance)
                    let error0 = (Int(expectedG1) ^ bit0)
                    let error1 = (Int(expectedG2) ^ bit1)
                    let branchMetric = error0 + error1

                    let newMetric = pathMetrics[state] + branchMetric

                    if newMetric < newPathMetrics[nextState] {
                        newPathMetrics[nextState] = newMetric
                        newSurvivalPath[nextState] = survivalPath[state]
                        newSurvivalPath[nextState].append(UInt8(inputBit))
                    }
                }
            }

            pathMetrics = newPathMetrics
            survivalPath = newSurvivalPath
        }

        // Find state with minimum path metric (most likely survivor)
        var minMetric = Int.max
        var bestState = 0
        for state in 0..<numStates {
            if pathMetrics[state] < minMetric {
                minMetric = pathMetrics[state]
                bestState = state
            }
        }

        // Trace back through the survivor path to get output
        var output = survivalPath[bestState]

        // Remove dummy bits added during trellis initialization if needed
        if output.count > (input.count / 4) {
            output = Array(output.dropLast(1))
        }

        return output
    }
    
    private func interleave(_ input: [UInt8]) -> [UInt8] {
        let depth = config.interleaverDepth
        var output = [UInt8](repeating: 0, count: input.count)
        let rows = (input.count + depth - 1) / depth
        
        for i in 0..<input.count {
            let row = i / depth
            let col = i % depth
            let newIndex = col * rows + row
            if newIndex < input.count {
                output[newIndex] = input[i]
            }
        }
        return output
    }
    
    private func deinterleave(_ input: [UInt8]) -> [UInt8] {
        let depth = config.interleaverDepth
        var output = [UInt8](repeating: 0, count: input.count)
        let rows = (input.count + depth - 1) / depth
        
        for i in 0..<input.count {
            let col = i / rows
            let row = i % rows
            let newIndex = row * depth + col
            if newIndex < input.count {
                output[newIndex] = input[i]
            }
        }
        return output
    }
    
    private func bitsToSymbols(_ bits: [UInt8]) -> [Int] {
        let bps = modulation.bitsPerSymbol
        var symbols: [Int] = []
        
        for i in stride(from: 0, to: bits.count - bps + 1, by: bps) {
            var symbol = 0
            for j in 0..<bps {
                symbol = (symbol << 1) | Int(bits[i + j])
            }
            symbols.append(symbol)
        }
        return symbols
    }
    
    private func symbolsToBits(_ symbols: [Int]) -> [UInt8] {
        let bps = modulation.bitsPerSymbol
        var bits: [UInt8] = []
        
        for symbol in symbols {
            for j in (0..<bps).reversed() {
                bits.append(UInt8((symbol >> j) & 1))
            }
        }
        return bits
    }
    
    // MARK: - Audio Playback
    
    private func playAudio(samples: [Float]) async throws {
        guard let player = playerNode, let engine = audioEngine else {
            throw HAMMERError.audioEngineNotInitialized
        }
        
        let format = AVAudioFormat(standardFormatWithSampleRate: config.sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw HAMMERError.bufferCreationFailed
        }
        
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channelData = buffer.floatChannelData?[0] else {
            throw HAMMERError.bufferCreationFailed
        }
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }
        
        try await playBuffer(buffer)
    }
    
    private func playBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard let player = playerNode else { throw HAMMERError.audioEngineNotInitialized }
        
        return try await withCheckedThrowingContinuation { continuation in
            player.scheduleBuffer(buffer) {
                continuation.resume()
            }
            player.play()
        }
    }
}

// MARK: - Errors

enum HAMMERError: Error {
    case audioEngineNotInitialized
    case bufferCreationFailed
    case noSessionKey
    case transmissionFailed
    case decodingFailed
}
