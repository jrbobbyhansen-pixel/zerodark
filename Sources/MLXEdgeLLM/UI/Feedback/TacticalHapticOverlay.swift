// TacticalHapticOverlay.swift — Proximity-scaled haptic feedback for threat detection
// Subscribes to active YOLO detections and drives CoreHaptics patterns based on distance/level

import Foundation
import CoreHaptics
import Combine
import simd

// MARK: - Tactical Haptic Pattern

enum TacticalHapticPattern {
    case proximity(distance: Float, maxRange: Float)  // Continuous, intensity scales with distance
    case threatLow                                     // Single gentle pulse every 2s
    case threatMedium                                  // Double pulse every 1s
    case threatHigh                                    // Rapid triple pulse every 0.5s
    case threatCritical                                // Continuous buzz, 0.3s period
    case coverNearby(distance: Float)                  // Gentle guiding pulse toward cover
    case clear                                         // Stop all haptics
}

// MARK: - TacticalHapticOverlay

@MainActor
final class TacticalHapticOverlay: ObservableObject {

    @Published private(set) var isActive = false
    @Published private(set) var currentThreatLevel: TacticalThreatLevel = .none
    @Published private(set) var nearestThreatDistance: Float = .infinity

    private var hapticEngine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var updateTimer: Timer?

    /// Maximum range for haptic feedback (meters)
    var maxRange: Float = 15.0

    /// Minimum interval between pattern changes (seconds)
    private let updateInterval: TimeInterval = 0.1

    /// Current device pose for distance calculation
    var devicePosition: SIMD3<Float> = .zero

    /// Active YOLO detections to drive haptics from
    var activeDetections: [YOLODetection] = [] {
        didSet { updateHapticState() }
    }

    init() {
        setupEngine()
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.stoppedHandler = { [weak self] reason in
                Task { @MainActor in
                    self?.isActive = false
                }
            }
            hapticEngine?.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.hapticEngine?.start()
                }
            }
            try hapticEngine?.start()
        } catch {
            print("[TacticalHapticOverlay] Engine setup failed: \(error)")
        }
    }

    // MARK: - Haptic State Management

    private func updateHapticState() {
        // Find highest-priority threat: highest level, then closest distance
        var priorityDetection: YOLODetection?
        var priorityLevel: TacticalThreatLevel = .none
        var closestDistance: Float = .infinity

        for detection in activeDetections {
            guard let dist = detection.distance, dist < maxRange else { continue }

            let level = detection.tacticalLevel()
            if level > priorityLevel || (level == priorityLevel && dist < closestDistance) {
                priorityDetection = detection
                priorityLevel = level
                closestDistance = dist
            }
        }

        currentThreatLevel = priorityLevel
        nearestThreatDistance = closestDistance

        if priorityLevel == .none {
            stopHaptics()
            return
        }

        playThreatPattern(level: priorityLevel, distance: closestDistance)
    }

    // MARK: - Pattern Playback

    private func playThreatPattern(level: TacticalThreatLevel, distance: Float) {
        guard let hapticEngine else { return }

        // Stop existing pattern
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)

        let intensity = max(0, min(1, 1.0 - (distance / maxRange)))

        do {
            let pattern = try buildPattern(level: level, intensity: intensity)
            continuousPlayer = try hapticEngine.makeAdvancedPlayer(with: pattern)
            try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
            isActive = true
        } catch {
            print("[TacticalHapticOverlay] Pattern playback failed: \(error)")
        }
    }

    private func buildPattern(level: TacticalThreatLevel, intensity: Float) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)

        switch level {
        case .none:
            break

        case .low:
            // Single gentle pulse
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.3)
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParam, sharpness],
                relativeTime: 0,
                duration: 0.1
            ))

        case .medium:
            // Double pulse
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.5)
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParam, sharpness],
                relativeTime: 0, duration: 0.08
            ))
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensityParam, sharpness],
                relativeTime: 0.15, duration: 0.08
            ))

        case .high:
            // Rapid triple pulse
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.75)
            for i in 0..<3 {
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensityParam, sharpness],
                    relativeTime: Double(i) * 0.1, duration: 0.06
                ))
            }

        case .critical:
            // Continuous buzz
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let sharpParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensityParam, sharpParam],
                relativeTime: 0,
                duration: 0.3
            ))
        }

        return try CHHapticPattern(events: events, parameters: [])
    }

    func stopHaptics() {
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        continuousPlayer = nil
        isActive = false
        currentThreatLevel = .none
    }

    // MARK: - Lifecycle

    func start() {
        guard hapticEngine == nil else { return }
        setupEngine()
    }

    func shutdown() {
        stopHaptics()
        hapticEngine?.stop()
        hapticEngine = nil
    }

    // MARK: - Factory: threatVibe

    /// Builds a CHHapticPattern for a given threat level and distance.
    /// Use this to create one-shot haptic alerts from external callers.
    static func threatVibe(level: TacticalThreatLevel, distance: Float, maxRange: Float = 15.0) -> CHHapticPattern? {
        let intensity = max(0, min(1, 1.0 - (distance / maxRange)))
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
        var events: [CHHapticEvent] = []

        switch level {
        case .none:
            return nil
        case .low:
            let ip = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.3)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [ip, sharpness], relativeTime: 0, duration: 0.1))
        case .medium:
            let ip = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.5)
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [ip, sharpness], relativeTime: 0, duration: 0.08))
            events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [ip, sharpness], relativeTime: 0.15, duration: 0.08))
        case .high:
            let ip = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.75)
            for i in 0..<3 {
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [ip, sharpness], relativeTime: Double(i) * 0.1, duration: 0.06))
            }
        case .critical:
            let ip = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let sp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [ip, sp], relativeTime: 0, duration: 0.3))
        }

        return try? CHHapticPattern(events: events, parameters: [])
    }

    /// Builds a gentle guiding haptic for nearby cover positions.
    static func coverVibePattern(distance: Float, maxRange: Float = 10.0) -> CHHapticPattern? {
        let intensity = max(0, min(0.4, 0.4 * (1.0 - distance / maxRange)))
        let ip = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [ip, sp], relativeTime: 0, duration: 0.15)
        return try? CHHapticPattern(events: [event], parameters: [])
    }

    deinit {
        hapticEngine?.stop()
    }
}
