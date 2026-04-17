// ThermalMonitor.swift — Wraps ProcessInfo.thermalState with reactive notifications
// Provides throttling recommendations for LiDAR pipeline components

import Foundation
import Combine

// MARK: - Thermal Level

enum ThermalLevel: Int, Comparable, CaseIterable {
    case nominal = 0   // Normal operation
    case fair = 1      // Slightly warm, minor throttling
    case serious = 2   // Hot, significant throttling
    case critical = 3  // Emergency, minimal processing only

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(from state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    var description: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Throttle Profile

/// Recommended pipeline settings for each thermal level
struct ThrottleProfile {
    let gaussianIterationsPerFrame: Int
    let yoloFrameSkipMultiplier: Int      // Multiplied with base frameSkip
    let kalmanIMURateMultiplier: Double    // 1.0 = full rate, 0.5 = half rate
    let enableRangeExtension: Bool
    let enableClutterFilter: Bool

    // LingBot-Map streaming state throttle controls
    let voxelFusionStride: Int           // 1=every pixel, 2=every 4th, 4=every 16th
    let keyframeIntervalMultiplier: Float // 1.0=normal GCA freq, higher=less frequent
    let enableLingBotIntegration: Bool   // false at critical — skip integrateFrame entirely

    static let nominal = ThrottleProfile(
        gaussianIterationsPerFrame: 100,
        yoloFrameSkipMultiplier: 1,
        kalmanIMURateMultiplier: 1.0,
        enableRangeExtension: true,
        enableClutterFilter: true,
        voxelFusionStride: 1,
        keyframeIntervalMultiplier: 1.0,
        enableLingBotIntegration: true
    )

    static let fair = ThrottleProfile(
        gaussianIterationsPerFrame: 50,
        yoloFrameSkipMultiplier: 2,
        kalmanIMURateMultiplier: 1.0,
        enableRangeExtension: true,
        enableClutterFilter: true,
        voxelFusionStride: 1,
        keyframeIntervalMultiplier: 1.5,
        enableLingBotIntegration: true
    )

    static let serious = ThrottleProfile(
        gaussianIterationsPerFrame: 10,
        yoloFrameSkipMultiplier: 3,
        kalmanIMURateMultiplier: 0.5,
        enableRangeExtension: false,   // Disable expensive gaussian training
        enableClutterFilter: true,
        voxelFusionStride: 2,
        keyframeIntervalMultiplier: 2.0,
        enableLingBotIntegration: true  // VoxelMap is cheap enough to keep on
    )

    static let critical = ThrottleProfile(
        gaussianIterationsPerFrame: 0,  // Stop training entirely
        yoloFrameSkipMultiplier: 5,
        kalmanIMURateMultiplier: 0.5,
        enableRangeExtension: false,
        enableClutterFilter: false,     // Only Kalman + YOLO at low rate
        voxelFusionStride: 4,
        keyframeIntervalMultiplier: 4.0,
        enableLingBotIntegration: false // Skip entirely at critical — raw accumulation only
    )

    static func profile(for level: ThermalLevel) -> ThrottleProfile {
        switch level {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        }
    }
}

// MARK: - ThermalMonitor

final class ThermalMonitor: ObservableObject {

    @Published private(set) var currentLevel: ThermalLevel = .nominal
    @Published private(set) var currentProfile: ThrottleProfile = .nominal
    @Published private(set) var thermalHistory: [(date: Date, level: ThermalLevel)] = []

    private var cancellable: AnyCancellable?
    private let maxHistorySize = 100

    init() {
        // Read initial state
        updateThermalState()

        // Subscribe to thermal state change notifications
        cancellable = NotificationCenter.default
            .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateThermalState()
            }
    }

    private func updateThermalState() {
        let newLevel = ThermalLevel(from: ProcessInfo.processInfo.thermalState)

        if newLevel != currentLevel {
            print("[ThermalMonitor] Thermal state changed: \(currentLevel.description) → \(newLevel.description)")
        }

        currentLevel = newLevel
        currentProfile = ThrottleProfile.profile(for: newLevel)

        thermalHistory.append((Date(), newLevel))
        if thermalHistory.count > maxHistorySize {
            thermalHistory.removeFirst()
        }
    }

    /// Check if we've been at serious/critical for more than `duration` seconds
    func hasBeenHotFor(duration: TimeInterval) -> Bool {
        guard currentLevel >= .serious else { return false }
        let cutoff = Date().addingTimeInterval(-duration)
        return thermalHistory
            .filter { $0.date >= cutoff }
            .allSatisfy { $0.level >= .serious }
    }

    /// Convenience: current throttle multiplier for a base value
    func throttledValue<T: BinaryFloatingPoint>(_ base: T, multiplier: Double) -> T {
        T(Double(base) * multiplier)
    }

    deinit {
        cancellable?.cancel()
    }
}
