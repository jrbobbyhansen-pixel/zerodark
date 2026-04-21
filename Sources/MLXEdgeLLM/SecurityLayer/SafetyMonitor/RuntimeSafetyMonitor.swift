// RuntimeSafetyMonitor.swift — Runtime safety monitor (NASA Ogma pattern)

import Foundation
import UIKit
import UserNotifications

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

    // Escalation tracking: how long a single property has been in violation.
    // Used to escalate from passive alert → active SOS after sustained failure.
    private var violationStartedAt: [SafetyProperty: Date] = [:]
    public var sosEscalationDelay: TimeInterval = 300  // 5 min of sustained loss → auto-SOS on reachability

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

    }

    /// Stop monitoring
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
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
            clearEscalation(for: property)
        }
    }

    /// Evaluate if a property is satisfied
    private func evaluateProperty(_ property: SafetyProperty) async -> Bool {
        switch property {
        case .teamMemberReachable:
            return MeshService.shared.peers.contains { $0.status != .offline }

        case .meshNetworkHealthy:
            // No active anomaly alerts = healthy
            let criticalAlerts = MeshAnomalyDetector.shared.alerts.filter {
                $0.severity == .high || $0.severity == .critical
            }
            return criticalAlerts.isEmpty

        case .positionKnown:
            return LocationManager.shared.currentLocation != nil

        case .withinGeofence:
            guard let coord = LocationManager.shared.currentLocation else { return true }
            let codable = CodableCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            return GeofenceManager.shared.status(for: codable) == .safe

        case .batteryAboveThreshold:
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level < 0 || level > batteryThreshold  // -1 means unknown/charging

        case .storageAvailable:
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
               let freeSpace = attrs[.systemFreeSize] as? Int64 {
                return freeSpace > storageThreshold
            }
            return true

        case .modelLoaded:
            return LocalInferenceEngine.shared.modelState == .ready

        case .checkInOnSchedule:
            return CheckInSystem.shared.overdueCheckIns.isEmpty

        case .missionTimeRemaining:
            guard let start = MissionClock.shared.missionStartDate,
                  let end = MissionClock.shared.missionEndDate else { return true }
            let total = end.timeIntervalSince(start)
            guard total > 0 else { return true }
            let elapsed = Date().timeIntervalSince(start)
            return elapsed < total * 0.80  // violation when <20% of mission time remains
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

        // Mark handler as triggered
        if let idx = activeViolations.firstIndex(where: { $0.id == violation.id }) {
            activeViolations[idx].handlerTriggered = true
        }

        // Track first time we saw this property in violation (for escalation timing).
        if violationStartedAt[property] == nil {
            violationStartedAt[property] = Date()
        }

        // User-visible alert: local notification + haptic.
        postNotification(for: property, violation: violation)
        triggerHaptic(for: property)

        // Property-specific actions.
        switch property {
        case .teamMemberReachable:
            // Attempt mesh reconnect; if prolonged loss, auto-broadcast SOS so survivors
            // are alerted even if the operator is incapacitated. Opt-in via the duration cap.
            if let started = violationStartedAt[property],
               Date().timeIntervalSince(started) >= sosEscalationDelay,
               !MeshService.shared.sosActive {
                MeshService.shared.broadcastSOS()
            }

        case .meshNetworkHealthy:
            // Mesh stack is already auto-restarting — alert + haptic above are the visible action.
            break

        case .positionKnown:
            // Request an immediate CLLocation update. Breadcrumb EKF / celestial fallback
            // already run passively; this nudges the location manager to try again.
            LocationManager.shared.forcePositionUpdate()

        case .withinGeofence:
            // Alert handled by the notification above. UI surfaces the violation in TeamDashSection.
            break

        case .batteryAboveThreshold:
            // Enter conservation mode: tell downstream subsystems to shed non-essential load.
            NotificationCenter.default.post(name: .zdEnterPowerSave, object: nil)

        case .storageAvailable:
            // Suggest cleanup via notification (handled above).
            break

        case .modelLoaded:
            // Fire-and-forget reload attempt; LocalInferenceEngine is @MainActor.
            Task { await LocalInferenceEngine.shared.reloadIfNeeded() }

        case .checkInOnSchedule:
            // Prompt handled by notification; CheckInSystem UI already shows overdue state.
            break

        case .missionTimeRemaining:
            // Notification + haptic are the actionable signal; countdown is visible in MissionClock UI.
            break
        }
    }

    /// Clear escalation start time when property transitions back to satisfied.
    /// Called from checkProperty whenever an existing violation resolves.
    private func clearEscalation(for property: SafetyProperty) {
        violationStartedAt.removeValue(forKey: property)
    }

    // MARK: - Alert delivery

    private func postNotification(for property: SafetyProperty, violation: SafetyViolation) {
        let content = UNMutableNotificationContent()
        content.title = "Safety Alert"
        content.body = violation.details
        content.sound = property.rawValue == SafetyProperty.teamMemberReachable.rawValue
            ? .defaultCritical
            : .default
        content.categoryIdentifier = "zd.safety.\(property.rawValue)"

        let request = UNNotificationRequest(
            identifier: violation.id.uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func triggerHaptic(for property: SafetyProperty) {
        #if canImport(UIKit)
        switch property {
        case .teamMemberReachable, .positionKnown, .batteryAboveThreshold:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .meshNetworkHealthy, .withinGeofence, .missionTimeRemaining:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .storageAvailable, .modelLoaded, .checkInOnSchedule:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
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

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted when a safety violation requires the app to shed non-essential load.
    /// Downstream subsystems (AI inference, LiDAR capture, mesh audio) can subscribe
    /// to pause or degrade accordingly. Payload: none.
    static let zdEnterPowerSave = Notification.Name("ZDEnterPowerSave")
}
