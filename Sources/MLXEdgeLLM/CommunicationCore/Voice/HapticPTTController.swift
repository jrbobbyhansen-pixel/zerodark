// HapticPTTController.swift — Fused Haptic + PTT coordinator
// Unifies PTTController and HapticComms into a single comms mode controller
// BUILD_SPEC v6.2: Haptic/PTT fuse

import Foundation

@MainActor
final class HapticPTTController: ObservableObject {
    static let shared = HapticPTTController()

    @Published var mode: CommsMode = .ptt

    enum CommsMode: String, CaseIterable {
        case ptt    = "PTT"
        case haptic = "Haptic"
        case silent = "Silent"

        var icon: String {
            switch self {
            case .ptt: return "mic.fill"
            case .haptic: return "hand.tap.fill"
            case .silent: return "speaker.slash.fill"
            }
        }
    }

    private let ptt = PTTController.shared
    private let haptic = HapticComms.shared

    private init() {}

    // MARK: - Transmit Control

    var isTransmitting: Bool { ptt.isTransmitting }
    var isReceiving: Bool { ptt.isReceiving }

    func startTransmit() {
        switch mode {
        case .ptt:
            ptt.startTransmit()
        case .haptic:
            // Haptic uses discrete codes, not continuous transmit
            break
        case .silent:
            break
        }
    }

    func stopTransmit() {
        ptt.stopTransmit()
    }

    // MARK: - Haptic Codes

    func sendHapticCode(_ code: TacticalHapticCode) {
        haptic.send(code)
    }

    // MARK: - Mode Cycling

    func cycleMode() {
        let modes = CommsMode.allCases
        guard let idx = modes.firstIndex(of: mode) else { return }
        let nextIdx = (idx + 1) % modes.count
        mode = modes[nextIdx]
    }
}
