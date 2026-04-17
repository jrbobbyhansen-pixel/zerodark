// DeviceCapability.swift — Runtime chip detection and feature scaling for Pro-universal support
// Gates LiDAR pipeline features based on device hardware capabilities

import Foundation
import ARKit

// MARK: - Chip Generation

enum ChipGeneration: Int, Comparable {
    case a15Pro = 15
    case a16Pro = 16
    case a17Pro = 17
    case a18Pro = 18
    case unknown = 0

    static func < (lhs: ChipGeneration, rhs: ChipGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DeviceCapability

struct DeviceCapability {
    let chipGeneration: ChipGeneration
    let hasLiDAR: Bool
    let totalMemoryGB: Int

    // Scaling knobs derived from chip generation
    var maxGaussians: Int {
        switch chipGeneration {
        case .a18Pro: return 50_000
        case .a17Pro: return 40_000
        case .a16Pro: return 30_000
        case .a15Pro: return 20_000
        case .unknown: return 15_000
        }
    }

    var yoloFrameSkip: Int {
        switch chipGeneration {
        case .a18Pro, .a17Pro: return 3   // 10 Hz
        case .a16Pro: return 4            // ~7.5 Hz
        case .a15Pro: return 5            // 6 Hz
        case .unknown: return 6
        }
    }

    var kalmanIMURate: Double {
        switch chipGeneration {
        case .a18Pro, .a17Pro: return 100.0
        case .a16Pro: return 75.0
        case .a15Pro: return 50.0
        case .unknown: return 50.0
        }
    }

    var neuralEngineTeraOps: Float {
        switch chipGeneration {
        case .a18Pro: return 38.0
        case .a17Pro: return 35.0
        case .a16Pro: return 17.0
        case .a15Pro: return 15.8
        case .unknown: return 11.0
        }
    }

    /// Per-device Kalman filter baseline config
    var kalmanConfig: KalmanConfig {
        KalmanConfig.recommended(for: self)
    }

    var enableRangeExtension: Bool { hasLiDAR && chipGeneration >= .a16Pro }
    var enableKalmanFusion: Bool { hasLiDAR }
    var enableYOLO: Bool { true } // Works on all devices, throttled by yoloFrameSkip
    var useMonocularDepth: Bool { !hasLiDAR } // Fallback for non-LiDAR

    var gaussianTrainingResolution: (width: Int, height: Int) {
        switch chipGeneration {
        case .a18Pro: return (256, 192)
        case .a17Pro: return (192, 144)
        default: return (128, 96)
        }
    }

    /// Maximum voxel count for VoxelStreamMap (scales with chip/RAM)
    var maxVoxelCount: Int {
        switch chipGeneration {
        case .a18Pro: return 2_000_000
        case .a17Pro: return 1_500_000
        case .a16Pro: return 1_000_000
        case .a15Pro: return 500_000
        case .unknown: return 300_000
        }
    }

    /// Depth image resolution for Metal VoxelFusion kernel dispatch
    var voxelFusionResolution: (width: Int, height: Int) {
        switch chipGeneration {
        case .a18Pro: return (256, 192)
        case .a17Pro: return (192, 144)
        default:      return (128, 96)
        }
    }

    // MARK: - Detection

    static let current: DeviceCapability = {
        let chip = detectChipGeneration()
        let lidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let memGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        return DeviceCapability(chipGeneration: chip, hasLiDAR: lidar, totalMemoryGB: memGB)
    }()

    private static func detectChipGeneration() -> ChipGeneration {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)

        // iPhone model mapping to chip generation
        // iPhone 13 Pro/Max = iPhone14,2/3 = A15 Pro
        // iPhone 14 Pro/Max = iPhone15,2/3 = A16 Pro
        // iPhone 15 Pro/Max = iPhone16,1/2 = A17 Pro
        // iPhone 16 Pro/Max = iPhone17,1/2/3/4 = A18 Pro
        if identifier.hasPrefix("iPhone17,") {
            return .a18Pro
        } else if identifier.hasPrefix("iPhone16,") {
            return .a16Pro // iPhone 15 non-Pro are A16, Pro are A17
                           // Refine below
        } else if identifier.hasPrefix("iPhone15,") {
            return .a16Pro
        } else if identifier.hasPrefix("iPhone14,") {
            return .a15Pro
        }

        // Refine iPhone16,x — Pro models (1,2) are A17, non-Pro are A16
        if identifier == "iPhone16,1" || identifier == "iPhone16,2" {
            return .a17Pro
        }

        // Simulator or unknown — use memory heuristic
        let memGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if memGB >= 8 { return .a17Pro }
        if memGB >= 6 { return .a16Pro }
        return .a15Pro
    }
}

// MARK: - LiDARScanConfig Extension

extension LiDARScanConfig {
    /// Factory that produces a recommended config for the current device
    static func recommended(for capability: DeviceCapability = .current) -> LiDARScanConfig {
        var config = LiDARScanConfig()
        config.maxRange = capability.enableRangeExtension ? 20.0 : 8.0
        config.meshDetail = capability.chipGeneration >= .a17Pro ? .high : .medium
        return config
    }
}
