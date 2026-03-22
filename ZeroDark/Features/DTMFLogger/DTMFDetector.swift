import Foundation
import AVFoundation
import Observation

struct DTMFEvent: Codable, Identifiable {
    let id: UUID
    let character: String
    let timestamp: Date
    let snr: Float

    init(character: String, timestamp: Date = .now, snr: Float) {
        self.id = UUID()
        self.character = character
        self.timestamp = timestamp
        self.snr = snr
    }
}

@Observable
final class DTMFDetector {
    var isDetecting = false
    var recentEvents: [DTMFEvent] = []
    var sessionLog: [DTMFEvent] = []

    private let audioEngine = AVAudioEngine()
    private let vault = VaultManager.shared
    private var sessionStart: Date?

    // DTMF frequency table: row freqs × col freqs → character
    private static let rowFreqs: [Float] = [697, 770, 852, 941]
    private static let colFreqs: [Float] = [1209, 1336, 1477, 1633]
    private static let dtmfTable: [[Character]] = [
        ["1", "2", "3", "A"],
        ["4", "5", "6", "B"],
        ["7", "8", "9", "C"],
        ["*", "0", "#", "D"]
    ]

    // Goertzel state per frequency
    private struct GoertzelState {
        var s1: Float = 0
        var s2: Float = 0
        let coeff: Float
        let freq: Float
        var sampleCount = 0
        let blockSize: Int

        init(targetFreq: Float, sampleRate: Float, blockSize: Int) {
            self.freq = targetFreq
            self.blockSize = blockSize
            let k = Int(0.5 + Float(blockSize) * targetFreq / sampleRate)
            let omega = 2.0 * Float.pi * Float(k) / Float(blockSize)
            self.coeff = 2.0 * cos(omega)
        }

        mutating func process(sample: Float) {
            let s0 = sample + coeff * s1 - s2
            s2 = s1; s1 = s0
            sampleCount += 1
        }

        var power: Float {
            s1 * s1 + s2 * s2 - coeff * s1 * s2
        }

        mutating func reset() {
            s1 = 0; s2 = 0; sampleCount = 0
        }
    }

    private let sampleRate: Float = 44100
    private let blockSize = 1764  // ~40ms at 44100 Hz — minimum valid DTMF tone duration
    private var rowStates: [GoertzelState] = []
    private var colStates: [GoertzelState] = []
    private var sampleBuffer: [Float] = []
    private var lastDetectedChar: Character? = nil
    private var consecutiveMatchCount = 0
    private static let requiredConsecutiveMatches = 2  // 2 blocks = ~80ms confirmed tone

    func startDetecting() throws {
        guard !isDetecting else { return }
        try configureAudioSession()

        rowStates = Self.rowFreqs.map { GoertzelState(targetFreq: $0, sampleRate: sampleRate, blockSize: blockSize) }
        colStates = Self.colFreqs.map { GoertzelState(targetFreq: $0, sampleRate: sampleRate, blockSize: blockSize) }
        sampleBuffer = []
        sessionStart = Date()
        sessionLog = []

        let inputNode = audioEngine.inputNode
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            self?.processSamples(buffer: buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isDetecting = true
    }

    func stopDetecting() {
        guard isDetecting else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isDetecting = false
        saveLog()
    }

    // MARK: - DSP

    private func processSamples(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        sampleBuffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))

        while sampleBuffer.count >= blockSize {
            let block = Array(sampleBuffer.prefix(blockSize))
            sampleBuffer.removeFirst(blockSize)
            analyzeBlock(block)
        }
    }

    private func analyzeBlock(_ samples: [Float]) {
        // Reset and feed samples to all Goertzel filters
        for i in 0..<rowStates.count {
            rowStates[i].reset()
            for s in samples { rowStates[i].process(sample: s) }
        }
        for i in 0..<colStates.count {
            colStates[i].reset()
            for s in samples { colStates[i].process(sample: s) }
        }

        let rowPowers = rowStates.map { $0.power }
        let colPowers = colStates.map { $0.power }
        let totalPower = rowPowers.reduce(0, +) + colPowers.reduce(0, +)

        guard totalPower > 1e-6 else {
            // Silence — reset consecutive count
            lastDetectedChar = nil
            consecutiveMatchCount = 0
            return
        }

        guard let rowIdx = rowPowers.indices.max(by: { rowPowers[$0] < rowPowers[$1] }),
              let colIdx = colPowers.indices.max(by: { colPowers[$0] < colPowers[$1] }) else { return }

        let rowDominance = rowPowers[rowIdx] / (totalPower / Float(rowPowers.count + colPowers.count))
        let colDominance = colPowers[colIdx] / (totalPower / Float(rowPowers.count + colPowers.count))

        // Both row and col must be dominant (DTMF dual-tone requirement)
        guard rowDominance > 2.0 && colDominance > 2.0 else {
            lastDetectedChar = nil; consecutiveMatchCount = 0
            return
        }

        let detected = Self.dtmfTable[rowIdx][colIdx]
        let snr = (rowPowers[rowIdx] + colPowers[colIdx]) / totalPower * 10.0

        if detected == lastDetectedChar {
            consecutiveMatchCount += 1
            if consecutiveMatchCount == Self.requiredConsecutiveMatches {
                // Confirmed tone
                let event = DTMFEvent(character: String(detected), snr: snr)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    recentEvents.insert(event, at: 0)
                    if recentEvents.count > 50 { recentEvents.removeLast() }
                    sessionLog.append(event)
                }
            }
        } else {
            lastDetectedChar = detected
            consecutiveMatchCount = 1
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, options: [.allowBluetooth])
        try session.setActive(true)
    }

    private func saveLog() {
        guard !sessionLog.isEmpty, let start = sessionStart else { return }
        let formatter = ISO8601DateFormatter()
        let filename = "dtmf_\(formatter.string(from: start)).json"
        try? vault.saveJSON(sessionLog, filename: filename)
    }
}
