// RouteOverlay.swift — Tactical route overlays with type-specific styling

import MapKit

/// Route type enum
public enum TacticalRouteType: String, CaseIterable {
    case planned
    case actual
    case alternate
    case bypass

    public var color: UIColor {
        switch self {
        case .planned:
            return UIColor(red: 0, green: 0.8, blue: 0.8, alpha: 1)  // Cyan
        case .actual:
            return UIColor(red: 0, green: 1, blue: 0, alpha: 1)  // Green
        case .alternate:
            return UIColor(red: 1, green: 0.8, blue: 0, alpha: 1)  // Yellow
        case .bypass:
            return UIColor(red: 1, green: 0, blue: 0, alpha: 1)  // Red
        }
    }

    public var dashPattern: [NSNumber] {
        switch self {
        case .planned:
            return [4, 4]  // Dashed
        case .actual:
            return []  // Solid
        case .alternate:
            return [8, 4]  // Long dash
        case .bypass:
            return [2, 2]  // Dotted
        }
    }
}

/// Tactical route overlay (polyline-based)
public class TacticalRouteOverlay: MKPolyline, TacticalOverlay {
    private static var routeTypeStorage = [ObjectIdentifier: TacticalRouteType]()
    
    public var routeType: TacticalRouteType {
        Self.routeTypeStorage[ObjectIdentifier(self)] ?? .planned
    }

    public static func create(coordinates: [CLLocationCoordinate2D], type: TacticalRouteType) -> TacticalRouteOverlay {
        var coords = coordinates
        let overlay = TacticalRouteOverlay(coordinates: &coords, count: coords.count)
        routeTypeStorage[ObjectIdentifier(overlay)] = type
        return overlay
    }
    
    deinit {
        Self.routeTypeStorage.removeValue(forKey: ObjectIdentifier(self))
    }
}

/// Tactical route renderer
public class TacticalRouteRenderer: MKPolylineRenderer {
    private weak var route: TacticalRouteOverlay?

    public init(overlay: TacticalRouteOverlay) {
        self.route = overlay
        super.init(overlay: overlay)
        updateAppearance()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        guard let route = route else { return }

        strokeColor = route.routeType.color
        lineWidth = 2
        lineDashPattern = route.routeType.dashPattern
    }
}
