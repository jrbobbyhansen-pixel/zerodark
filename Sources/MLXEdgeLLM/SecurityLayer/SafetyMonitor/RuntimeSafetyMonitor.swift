// RuntimeSafetyMonitor.swift — Runtime safety monitor (NASA Ogma pattern)

import Foundation
import UIKit

/// Runtime safety monitor (NASA Ogma pattern)
@MainActor
public class RuntimeSafetyMonitor: ObservableObject {
    public static let shared = RuntimeSafetyMonitor()

    @Published public private(set) var activeViolations: [SafetyViolation] = []
    @Published public private(set) var propertyStatus: [SafetyProperty: Bool] = [:]
    @Published public private(set) var isMonitoring = false

    private var monitoringTask: Task<Void, Never>?
    private var lastChecked: [SafetyProperty: Date] = [:]

    // Thresholds (configurable)
    public var batteryThreshold: Float = 0.10  // 10%
    public var positionAgeThreshold: TimeInterval = 600  // 10 minutes
    public var storageThreshold: Int64 = 100_000_000  // 100 MB

    private init() {
        // Initialize all properties as unknown
        for property in SafetyProperty.allCases {
            propertyStatus[property] = true  // Assume OK initially
        }
    }

    /// Start monitoring
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitoringTask = Task {
            await monitorLoop()
        }

        print("[SafetyMonitor] Started monitoring \(SafetyProperty.allCases.count) properties")
    }

    /// Stop monitoring
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
        print("[SafetyMonitor] Stopped")
    }

    /// Main monitoring loop
    private func monitorLoop() async {
        while !Task.isCancelled {
            for property in SafetyProperty.allCases {
                // Check if enough time has passed
                let lastCheck = lastChecked[property] ?? .distantPast
                if Date().timeIntervalSince(lastCheck) >= property.checkInterval {
                    await checkProperty(property)
                    lastChecked[property] = Date()
                }
            }

            // Small sleep between cycles
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        }
    }

    /// Check a single property
    private func checkProperty(_ property: SafetyProperty) async {
        let satisfied = await evaluateProperty(property)
        propertyStatus[property] = satisfied

        if !satisfied {
            // Check if we already have an active violation for this
            let hasActiveViolation = activeViolations.contains {
                $0.property == property.rawValue && !$0.resolved
            }

            if !hasActiveViolation {
                let violation = SafetyViolation(
                    property: property,
                    details: describeViolation(property)
                )
                activeViolations.append(violation)

                // Trigger handler (Ogma pattern: automatic response)
                await triggerHandler(for: property, violation: violation)
            }
        } else {
            // Resolve any existing violations
            for i in activeViolations.indices {
                if activeViolations[i].property == property.rawValue && !activeViolations[i].resolved {
                    activeViolations[i].resolved = true
                    activeViolations[i].resolvedAt = Date()
                }
            }
        }
    }

    /// Evaluate if a property is satisfied
    private func evaluateProperty(_ property: SafetyProperty) async -> Bool {
        switch property {
        case .teamMemberReachable:
            // TODO: Integration with HapticComms
            // return HapticComms.shared.connectedPeers.count > 0
            return true  // Placeholder

        case .meshNetworkHealthy:
            // Integration with MeshAnomalyDetector
            if let detector = NSClassFromString("MLXEdgeLLM.MeshAnomalyDetector") as? AnyObject {
                // Safe runtime check if MeshAnomalyDetector exists
                return true  // Placeholder
            }
            return true

        case .positionKnown:
            // TODO: Integration with LocationManager
            // let age = Date().timeIntervalSince(LocationManager.shared.lastFix)
            // return age < positionAgeThreshold
            return true  // Placeholder

        case .withinGeofence:
            // TODO: Integration with geofencing
            return true  // Placeholder

        case .batteryAboveThreshold:
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level < 0 || level > batteryThreshold  // -1 means unknown

        case .storageAvailable:
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
               let freeSpace = attrs[.systemFreeSize] as? Int64 {
                return freeSpace > storageThreshold
            }
            return true

        case .modelLoaded:
            // TODO: Integration with LocalInferenceEngine
            // return LocalInferenceEngine.shared.modelState == .ready
            return true  // Placeholder

        case .checkInOnSchedule:
            // TODO: Integration with check-in tracking
            return true  // Placeholder

        case .missionTimeRemaining:
            // TODO: Integration with mission timer
            return true  // Placeholder
        }
    }

    /// Describe a violation for logging/display
    private func describeViolation(_ property: SafetyProperty) -> String {
        switch property {
        case .teamMemberReachable:
            return "No team members currently reachable"
        case .meshNetworkHealthy:
            return "Mesh network anomaly detected"
        case .positionKnown:
            return "Position fix is stale or unavailable"
        case .withinGeofence:
            return "Current position outside operational area"
        case .batteryAboveThreshold:
            let level = Int(UIDevice.current.batteryLevel * 100)
            return "Battery at \(level)% (below \(Int(batteryThreshold * 100))% threshold)"
        case .storageAvailable:
            return "Storage space critically low"
        case .modelLoaded:
            return "AI model not loaded"
        case .checkInOnSchedule:
            return "Team check-in overdue"
        case .missionTimeRemaining:
            return "Mission time limit approaching"
        }
    }

    /// Trigger automatic handler for violation (Ogma pattern)
    private func triggerHandler(for property: SafetyProperty, violation: SafetyViolation) async {
        print("[SafetyMonitor] VIOLATION: \(property.rawValue)")

        // Mark handler as triggered
        if let idx = activeViolations.firstIndex(where: { $0.id == violation.id }) {
            activeViolations[idx].handlerTriggered = true
        }

        // Execute property-specific handler
        switch property {
        case .teamMemberReachable:
            // Attempt reconnection, escalate to SOS if prolonged
            // TODO: HapticComms.shared.attemptReconnection()
            break

        case .meshNetworkHealthy:
            // Alert user immediately
            // TODO: Send local notification
            break

        case .positionKnown:
            // Attempt position fix methods in order
            // TODO: Try GPS, then celestial, then dead reckoning
            break

        case .withinGeofence:
            // Alert user, suggest return path
            // TODO: HapticComms.shared.send(.danger, to: "all")
            break

        case .batteryAboveThreshold:
            // Enable power saving
            // TODO: PowerManager.shared.enableConservation()
            break

        case .storageAvailable:
            // Suggest cleanup
            break

        case .modelLoaded:
            // Attempt reload (try to avoid main thread blocking)
            // TODO: LocalInferenceEngine.shared.loadModel()
            break

        case .checkInOnSchedule:
            // Prompt user to check in
            break

        case .missionTimeRemaining:
            // Reminder notification
            break
        }
    }

    /// Get all unresolved violations sorted by severity
    public var unresolvedViolations: [SafetyViolation] {
        activeViolations
            .filter { !$0.resolved }
            .sorted { $0.severity > $1.severity }
    }

    /// Clear resolved violations older than specified age
    public func pruneResolved(olderThan age: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-age)
        activeViolations.removeAll {
            $0.resolved && ($0.resolvedAt ?? Date()) < cutoff
        }
    }
}
