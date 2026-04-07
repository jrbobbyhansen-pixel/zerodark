import Foundation
import SwiftUI
import CoreHaptics

// MARK: - HapticFeedbackManager

final class HapticFeedbackManager: ObservableObject {
    @Published private(set) var isSilentModeEnabled: Bool = false
    @Published private(set) var intensity: HapticIntensity = .medium
    
    private var hapticEngine: CHHapticEngine?
    
    init() {
        setupHapticEngine()
    }
    
    func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Failed to create haptic engine: \(error)")
        }
    }
    
    func triggerHapticFeedback(pattern: HapticPattern) {
        guard !isSilentModeEnabled else { return }
        
        let intensityValue = intensity.rawValue
        
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensityValue),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: intensityValue)
        ], relativeTime: 0)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to trigger haptic feedback: \(error)")
        }
    }
    
    func toggleSilentMode() {
        isSilentModeEnabled.toggle()
    }
    
    func setIntensity(_ intensity: HapticIntensity) {
        self.intensity = intensity
    }
}

// MARK: - HapticIntensity

enum HapticIntensity: Float {
    case low = 0.25
    case medium = 0.5
    case high = 0.75
}

// MARK: - HapticPattern

enum HapticPattern {
    case success
    case error
    case warning
    case notification
}

// MARK: - Tactical Haptic Extensions

extension HapticFeedbackManager {
    /// Play a continuous tactical haptic pattern with variable intensity.
    /// Uses hapticContinuous events for sustained feedback during threat proximity.
    func playTacticalPattern(_ pattern: TacticalHapticPattern, intensity: Float = 0.5) {
        guard !isSilentModeEnabled, let hapticEngine else { return }

        let clampedIntensity = max(0, min(1, intensity))

        do {
            let hapticPattern: CHHapticPattern

            switch pattern {
            case .proximity(let distance, let maxRange):
                let scaledIntensity = max(0, min(1, 1.0 - (distance / maxRange)))
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: scaledIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0,
                    duration: 0.2
                )
                hapticPattern = try CHHapticPattern(events: [event], parameters: [])

            case .threatLow:
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity * 0.3),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                    ],
                    relativeTime: 0
                )
                hapticPattern = try CHHapticPattern(events: [event], parameters: [])

            case .threatMedium:
                let events = [0.0, 0.15].map { time in
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity * 0.5),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                        ],
                        relativeTime: time
                    )
                }
                hapticPattern = try CHHapticPattern(events: events, parameters: [])

            case .threatHigh:
                let events = (0..<3).map { i in
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity * 0.75),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                        ],
                        relativeTime: Double(i) * 0.1
                    )
                }
                hapticPattern = try CHHapticPattern(events: events, parameters: [])

            case .threatCritical:
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: clampedIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                    ],
                    relativeTime: 0,
                    duration: 0.3
                )
                hapticPattern = try CHHapticPattern(events: [event], parameters: [])

            case .clear:
                return
            }

            let player = try hapticEngine.makePlayer(with: hapticPattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play tactical haptic: \(error)")
        }
    }
}

// MARK: - HapticFeedbackView

struct HapticFeedbackView: View {
    @StateObject private var feedbackManager = HapticFeedbackManager()
    
    var body: some View {
        VStack {
            Toggle("Silent Mode", isOn: $feedbackManager.isSilentModeEnabled)
                .padding()
            
            HStack {
                Text("Intensity:")
                Picker("Intensity", selection: $feedbackManager.intensity) {
                    ForEach(HapticIntensity.allCases, id: \.self) { intensity in
                        Text("\(intensity.rawValue)")
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            
            Button(action: {
                feedbackManager.triggerHapticFeedback(pattern: .success)
            }) {
                Text("Trigger Success Haptic")
            }
            .padding()
            
            Button(action: {
                feedbackManager.triggerHapticFeedback(pattern: .error)
            }) {
                Text("Trigger Error Haptic")
            }
            .padding()
            
            Button(action: {
                feedbackManager.triggerHapticFeedback(pattern: .warning)
            }) {
                Text("Trigger Warning Haptic")
            }
            .padding()
            
            Button(action: {
                feedbackManager.triggerHapticFeedback(pattern: .notification)
            }) {
                Text("Trigger Notification Haptic")
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct HapticFeedbackView_Previews: PreviewProvider {
    static var previews: some View {
        HapticFeedbackView()
    }
}