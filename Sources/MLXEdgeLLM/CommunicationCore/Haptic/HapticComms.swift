// HapticComms.swift — Tactical Haptic Communication via Mesh
// Send/receive coded vibration patterns for silent communication

import UIKit
import CoreHaptics
import Foundation

// MARK: - Haptic Codes

enum TacticalHapticCode: String, CaseIterable, Codable {
    case acknowledge = "ACK"           // Single pulse - "Got it"
    case stop = "STOP"                 // Two quick pulses - "Halt"
    case move = "MOVE"                 // Long pulse - "Move out"
    case danger = "DANGER"             // Three rapid pulses - "Threat"
    case rally = "RALLY"               // Pulse-pause-pulse - "Regroup"
    case quiet = "QUIET"               // Soft pulse - "Go silent"
    case attention = "ATTN"            // Rising pulses - "Look at me"
    case yes = "YES"                   // Single strong pulse
    case no = "NO"                     // Two pulses
    case sosReceived = "SOS_RX"        // Continuous vibration

    var displayName: String {
        switch self {
        case .acknowledge: return "Acknowledge"
        case .stop: return "Stop/Halt"
        case .move: return "Move Out"
        case .danger: return "Danger"
        case .rally: return "Rally Point"
        case .quiet: return "Go Quiet"
        case .attention: return "Attention"
        case .yes: return "Yes"
        case .no: return "No"
        case .sosReceived: return "SOS Received"
        }
    }

    var icon: String {
        switch self {
        case .acknowledge: return "checkmark.circle"
        case .stop: return "hand.raised.fill"
        case .move: return "arrow.forward.circle"
        case .danger: return "exclamationmark.triangle.fill"
        case .rally: return "flag.fill"
        case .quiet: return "speaker.slash.fill"
        case .attention: return "eye.fill"
        case .yes: return "checkmark"
        case .no: return "xmark"
        case .sosReceived: return "waveform.path.ecg"
        }
    }
}

// MARK: - Haptic Engine

@MainActor
final class HapticComms: ObservableObject {
    static let shared = HapticComms()

    @Published var lastReceivedCode: TacticalHapticCode?
    @Published var lastSender: String?
    @Published var isPlaying = false

    private var engine: CHHapticEngine?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        setupEngine()
    }

    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()
            try engine?.start()

            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
        } catch {
        }
    }

    // MARK: - Send Haptic Code

    func send(_ code: TacticalHapticCode) {
        // Play locally
        playPattern(for: code)

        // Broadcast to mesh
        MeshService.shared.sendHapticCode(code)
    }

    // MARK: - Receive Haptic Code

    func receive(_ code: TacticalHapticCode, from sender: String) {
        lastReceivedCode = code
        lastSender = sender

        // Play the haptic pattern
        playPattern(for: code)

        // Clear after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.lastReceivedCode = nil
            self?.lastSender = nil
        }
    }

    // MARK: - Haptic Patterns

    private func playPattern(for code: TacticalHapticCode) {
        isPlaying = true

        switch code {
        case .acknowledge:
            // Single strong pulse
            impactGenerator.impactOccurred(intensity: 1.0)

        case .stop:
            // Two quick pulses
            impactGenerator.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.impactGenerator.impactOccurred(intensity: 1.0)
            }

        case .move:
            // Long pulse (simulated with rapid sequence)
            playLongPulse(duration: 0.5)

        case .danger:
            // Three rapid pulses
            notificationGenerator.notificationOccurred(.warning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.notificationGenerator.notificationOccurred(.warning)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.notificationGenerator.notificationOccurred(.warning)
            }

        case .rally:
            // Pulse - pause - pulse
            impactGenerator.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.impactGenerator.impactOccurred(intensity: 1.0)
            }

        case .quiet:
            // Soft pulse
            impactGenerator.impactOccurred(intensity: 0.3)

        case .attention:
            // Rising pulses
            impactGenerator.impactOccurred(intensity: 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.impactGenerator.impactOccurred(intensity: 0.6)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.impactGenerator.impactOccurred(intensity: 1.0)
            }

        case .yes:
            // Single strong pulse
            notificationGenerator.notificationOccurred(.success)

        case .no:
            // Two pulses (error style)
            notificationGenerator.notificationOccurred(.error)

        case .sosReceived:
            // Continuous SOS pattern
            playSOSPattern()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isPlaying = false
        }
    }

    private func playLongPulse(duration: TimeInterval) {
        guard let engine = engine else { return }

        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: duration)

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Fallback to simple impact
            impactGenerator.impactOccurred(intensity: 1.0)
        }
    }

    private func playSOSPattern() {
        // S = ... (3 short)
        // O = --- (3 long)
        // S = ... (3 short)
        let shortDelay = 0.1
        let longDelay = 0.3
        let letterGap = 0.5

        var time = 0.0

        // S
        for _ in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                self.impactGenerator.impactOccurred(intensity: 0.7)
            }
            time += shortDelay
        }
        time += letterGap

        // O
        for _ in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                self.playLongPulse(duration: 0.2)
            }
            time += longDelay
        }
        time += letterGap

        // S
        for _ in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                self.impactGenerator.impactOccurred(intensity: 0.7)
            }
            time += shortDelay
        }
    }
}
