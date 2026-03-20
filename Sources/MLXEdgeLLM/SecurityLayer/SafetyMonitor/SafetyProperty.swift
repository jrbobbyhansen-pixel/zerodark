// SafetyProperty.swift — Declarative safety properties (NASA Ogma pattern)

import Foundation

/// Declarative safety properties (NASA Ogma pattern)
public enum SafetyProperty: String, CaseIterable, Identifiable {
    // Communication properties
    case teamMemberReachable = "At least one team member reachable"
    case meshNetworkHealthy = "Mesh network has no anomalies"

    // Navigation properties
    case positionKnown = "Position fix within acceptable age"
    case withinGeofence = "Within defined operational area"

    // System properties
    case batteryAboveThreshold = "Battery above minimum threshold"
    case storageAvailable = "Sufficient storage available"
    case modelLoaded = "AI model loaded and ready"

    // Temporal properties
    case checkInOnSchedule = "Team check-ins on schedule"
    case missionTimeRemaining = "Mission time remaining"

    public var id: String { rawValue }

    /// How often to check this property
    public var checkInterval: TimeInterval {
        switch self {
        case .teamMemberReachable: return 300      // 5 minutes
        case .meshNetworkHealthy: return 60        // 1 minute
        case .positionKnown: return 600            // 10 minutes
        case .withinGeofence: return 30            // 30 seconds
        case .batteryAboveThreshold: return 60     // 1 minute
        case .storageAvailable: return 300         // 5 minutes
        case .modelLoaded: return 60               // 1 minute
        case .checkInOnSchedule: return 300        // 5 minutes
        case .missionTimeRemaining: return 60      // 1 minute
        }
    }

    /// Severity when violated
    public var severity: ViolationSeverity {
        switch self {
        case .teamMemberReachable: return .warning
        case .meshNetworkHealthy: return .critical
        case .positionKnown: return .warning
        case .withinGeofence: return .critical
        case .batteryAboveThreshold: return .warning
        case .storageAvailable: return .info
        case .modelLoaded: return .info
        case .checkInOnSchedule: return .warning
        case .missionTimeRemaining: return .info
        }
    }

    /// SF Symbol for UI
    public var icon: String {
        switch self {
        case .teamMemberReachable: return "person.2.fill"
        case .meshNetworkHealthy: return "network"
        case .positionKnown: return "location.fill"
        case .withinGeofence: return "square.dashed"
        case .batteryAboveThreshold: return "battery.25"
        case .storageAvailable: return "internaldrive"
        case .modelLoaded: return "brain"
        case .checkInOnSchedule: return "clock.fill"
        case .missionTimeRemaining: return "timer"
        }
    }
}

public enum ViolationSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: ViolationSeverity, rhs: ViolationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
