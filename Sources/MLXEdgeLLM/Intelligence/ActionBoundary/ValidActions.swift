// ValidActions.swift — DoD combee pattern: enumerate all valid tactical actions upfront

import Foundation
import CoreLocation

/// All valid actions the AI can request (combee pattern: enumerate upfront)
public enum ValidAction: String, Codable, CaseIterable {
    // Navigation
    case navigate
    case markWaypoint
    case setRallyPoint

    // Communication
    case sendAlert
    case broadcastMessage
    case requestCheckIn

    // Tactical
    case reportIncident
    case updateThreatLevel
    case requestSupport

    // System
    case enablePowerSave
    case startScan
    case stopScan
}

/// Structured action call from AI
public struct ActionCall: Codable {
    let action: ValidAction
    let parameters: ActionParameters
    let reasoning: String?

    public struct ActionParameters: Codable {
        // Navigation params
        var coordinate: CodableCoordinate?
        var waypointName: String?
        var waypointType: String?

        // Communication params
        var recipient: String?  // "all" or peer ID
        var message: String?
        var priority: AlertPriority?

        // Tactical params
        var incidentType: String?
        var threatLevel: Int?
        var description: String?

        public enum AlertPriority: String, Codable {
            case low, medium, high, critical
        }

        public init() {}
    }

    public init(action: ValidAction, parameters: ActionParameters, reasoning: String? = nil) {
        self.action = action
        self.parameters = parameters
        self.reasoning = reasoning
    }
}

public struct CodableCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    public var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
