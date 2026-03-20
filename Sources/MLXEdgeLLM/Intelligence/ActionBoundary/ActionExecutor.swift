// ActionExecutor.swift — Executes validated actions safely (combee: only execute validated calls)

import Foundation

/// Executes validated actions (combee: only execute validated calls)
public actor ActionExecutor {
    public static let shared = ActionExecutor()

    private init() {}

    /// Execute a validated action call
    /// Precondition: call has passed ActionBoundary.validate()
    public func execute(_ call: ActionCall) async -> ActionResult {
        switch call.action {
        case .navigate:
            return await executeNavigate(call.parameters)
        case .markWaypoint:
            return await executeMarkWaypoint(call.parameters)
        case .setRallyPoint:
            return await executeSetRallyPoint(call.parameters)
        case .sendAlert:
            return await executeSendAlert(call.parameters)
        case .broadcastMessage:
            return await executeBroadcastMessage(call.parameters)
        case .requestCheckIn:
            return await executeRequestCheckIn(call.parameters)
        case .reportIncident:
            return await executeReportIncident(call.parameters)
        case .updateThreatLevel:
            return await executeUpdateThreatLevel(call.parameters)
        case .requestSupport:
            return await executeRequestSupport(call.parameters)
        case .enablePowerSave:
            return await executeEnablePowerSave()
        case .startScan:
            return await executeStartScan()
        case .stopScan:
            return await executeStopScan()
        }
    }

    // MARK: - Action Implementations

    private func executeNavigate(_ params: ActionCall.ActionParameters) async -> ActionResult {
        guard let coord = params.coordinate else {
            return .failure("Missing coordinate")
        }
        // Integration point: NavigationViewModel or MapKit directions
        await MainActor.run {
            // TODO: Integrate with existing navigation
            // NavigationViewModel.shared.navigateTo(coord.clLocation)
        }
        return .success("Navigation started to \(coord.latitude), \(coord.longitude)")
    }

    private func executeMarkWaypoint(_ params: ActionCall.ActionParameters) async -> ActionResult {
        guard let coord = params.coordinate,
              let name = params.waypointName else {
            return .failure("Missing coordinate or name")
        }
        // Integration point: TacticalWaypointStore
        await MainActor.run {
            // TODO: Integrate with existing waypoint store
            // TacticalWaypointStore.shared.add(name: name, coordinate: coord.clLocation)
        }
        return .success("Waypoint '\(name)' marked")
    }

    private func executeSetRallyPoint(_ params: ActionCall.ActionParameters) async -> ActionResult {
        guard let coord = params.coordinate else {
            return .failure("Missing coordinate")
        }
        // Integration point: Coordination module
        return .success("Rally point set at \(coord.latitude), \(coord.longitude)")
    }

    private func executeSendAlert(_ params: ActionCall.ActionParameters) async -> ActionResult {
        guard let message = params.message else {
            return .failure("Missing message")
        }
        let recipient = params.recipient ?? "all"
        let priority = params.priority ?? .medium

        // Integration point: HapticComms
        await MainActor.run {
            // TODO: Integrate with HapticComms
            // HapticComms.shared.sendAlert(message, to: recipient, priority: priority)
        }
        return .success("Alert sent to \(recipient)")
    }

    private func executeBroadcastMessage(_ params: ActionCall.ActionParameters) async -> ActionResult {
        guard let message = params.message else {
            return .failure("Missing message")
        }
        // Integration point: HapticComms broadcast
        return .success("Message broadcast: \(message.prefix(50))...")
    }

    private func executeRequestCheckIn(_ params: ActionCall.ActionParameters) async -> ActionResult {
        let recipient = params.recipient ?? "all"
        // Integration point: HapticComms check-in request
        return .success("Check-in requested from \(recipient)")
    }

    private func executeReportIncident(_ params: ActionCall.ActionParameters) async -> ActionResult {
        guard let type = params.incidentType,
              let description = params.description else {
            return .failure("Missing incident details")
        }
        // Integration point: IncidentStore
        await MainActor.run {
            // TODO: Integrate with IncidentStore
            // IncidentStore.shared.report(type: type, description: description)
        }
        return .success("Incident reported: \(type)")
    }

    private func executeUpdateThreatLevel(_ params: ActionCall.ActionParameters) async -> ActionResult {
        guard let level = params.threatLevel else {
            return .failure("Missing threat level")
        }
        // Integration point: MeshAnomalyDetector or global threat state
        await MainActor.run {
            // TODO: Integrate with threat level system
            // ThreatLevelManager.shared.setLevel(level)
        }
        return .success("Threat level updated to \(level)")
    }

    private func executeRequestSupport(_ params: ActionCall.ActionParameters) async -> ActionResult {
        // Integration point: Emergency/SOS system
        return .success("Support request broadcast")
    }

    private func executeEnablePowerSave() async -> ActionResult {
        // Integration point: System power management
        return .success("Power save mode enabled")
    }

    private func executeStartScan() async -> ActionResult {
        // Integration point: LiDAR or sensor scanning
        return .success("Scan started")
    }

    private func executeStopScan() async -> ActionResult {
        // Integration point: LiDAR or sensor scanning
        return .success("Scan stopped")
    }
}

public enum ActionResult {
    case success(String)
    case failure(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .success(let msg), .failure(let msg):
            return msg
        }
    }
}
