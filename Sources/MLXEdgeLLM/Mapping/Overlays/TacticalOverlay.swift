// TacticalOverlay.swift — Base tactical overlay protocol (DoD ATAK-CIV pattern)

import MapKit

/// Base protocol for tactical overlays
public protocol TacticalOverlay: MKOverlay {}

/// Tactical overlay types
public enum TacticalOverlayType: String, CaseIterable {
    case teamPosition
    case threatZone
    case route
    case waypoint

    public var displayName: String {
        switch self {
        case .teamPosition: return "Team Positions"
        case .threatZone: return "Threat Zones"
        case .route: return "Routes"
        case .waypoint: return "Waypoints"
        }
    }

    public var icon: String {
        switch self {
        case .teamPosition: return "person.fill"
        case .threatZone: return "exclamationmark.triangle.fill"
        case .route: return "line.diagonal"
        case .waypoint: return "mappin.circle.fill"
        }
    }
}

/// Tactical overlay manager singleton
@MainActor
public class TacticalOverlayManager: NSObject, ObservableObject {
    public static let shared = TacticalOverlayManager()

    @Published public var overlays: [MKOverlay] = []
    @Published public var selectedOverlay: MKOverlay? = nil

    private override init() {}

    /// Add overlay to map
    public func add(_ overlay: MKOverlay) {
        overlays.append(overlay)
    }

    /// Remove overlay from map
    public func remove(_ overlay: MKOverlay) {
        overlays.removeAll { $0 === overlay }
    }

    /// Clear all overlays
    public func clear() {
        overlays.removeAll()
    }
}
