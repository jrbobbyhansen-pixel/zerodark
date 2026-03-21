// ActionBoundary.swift — Validates AI outputs against allowed action schema (DoD combee pattern)

import Foundation
import CoreLocation

/// Validates AI outputs against allowed action schema (combee pattern)
public actor ActionBoundary {
    public static let shared = ActionBoundary()

    // combee: Define bounds for each parameter type
    private let maxMessageLength = 500
    private let validThreatLevels = 1...5
    private let maxWaypointNameLength = 50

    // combee: Coordinate bounds (reasonable Earth coordinates)
    private let latitudeBounds = -90.0...90.0
    private let longitudeBounds = -180.0...180.0

    private init() {}

    /// Parse and validate AI output string into ActionCall
    /// Returns nil if invalid (combee: reject, don't correct)
    public func validate(aiOutput: String) -> ActionCall? {
        // Step 1: Extract JSON from AI output
        guard let jsonString = extractJSON(from: aiOutput) else {
            return nil
        }

        // Step 2: Decode to ActionCall
        guard let data = jsonString.data(using: .utf8),
              let call = try? JSONDecoder().decode(ActionCall.self, from: data) else {
            return nil
        }

        // Step 3: Validate action is in allowed set
        guard ValidAction.allCases.contains(call.action) else {
            return nil
        }

        // Step 4: Validate parameters for this action type
        guard validateParameters(for: call) else {
            return nil
        }

        return call
    }

    /// Extract JSON object from potentially messy AI output
    private func extractJSON(from text: String) -> String? {
        // Find first { and last }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    /// Validate parameters based on action type (combee: strict bounds)
    private func validateParameters(for call: ActionCall) -> Bool {
        let params = call.parameters

        switch call.action {
        case .navigate, .markWaypoint, .setRallyPoint:
            // Must have valid coordinate
            guard let coord = params.coordinate,
                  latitudeBounds.contains(coord.latitude),
                  longitudeBounds.contains(coord.longitude) else {
                return false
            }
            // Waypoint needs name
            if call.action == .markWaypoint {
                guard let name = params.waypointName,
                      !name.isEmpty,
                      name.count <= maxWaypointNameLength else {
                    return false
                }
            }
            return true

        case .sendAlert, .broadcastMessage:
            // Must have message
            guard let message = params.message,
                  !message.isEmpty,
                  message.count <= maxMessageLength else {
                return false
            }
            return true

        case .requestCheckIn:
            // Recipient optional (defaults to all)
            return true

        case .reportIncident:
            // Must have incident type and description
            guard let type = params.incidentType,
                  !type.isEmpty,
                  let desc = params.description,
                  !desc.isEmpty else {
                return false
            }
            return true

        case .updateThreatLevel:
            // Must have valid threat level
            guard let level = params.threatLevel,
                  validThreatLevels.contains(level) else {
                return false
            }
            return true

        case .requestSupport, .enablePowerSave, .startScan, .stopScan:
            // No required parameters
            return true
        }
    }
}
