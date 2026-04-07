// ThreatZoneOverlay.swift — Threat zone circular overlays with color-coded threat levels

import MapKit

/// Threat zone overlay (circle-based)
public class ThreatZoneOverlay: MKCircle, TacticalOverlay {
    private static var threatLevelStorage = [ObjectIdentifier: Int]()
    
    public var threatLevel: Int {  // 1-5
        Self.threatLevelStorage[ObjectIdentifier(self)] ?? 1
    }

    public static func create(center: CLLocationCoordinate2D, radius: CLLocationDistance, threatLevel: Int) -> ThreatZoneOverlay {
        let overlay = ThreatZoneOverlay(center: center, radius: radius)
        threatLevelStorage[ObjectIdentifier(overlay)] = max(1, min(threatLevel, 5))
        return overlay
    }
    
    deinit {
        Self.threatLevelStorage.removeValue(forKey: ObjectIdentifier(self))
    }
}

/// Threat zone renderer
public class ThreatZoneRenderer: MKCircleRenderer {
    private weak var threatZone: ThreatZoneOverlay?

    public init(overlay: ThreatZoneOverlay) {
        self.threatZone = overlay
        super.init(overlay: overlay)
        updateAppearance()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        guard let zone = threatZone else { return }

        let color: UIColor
        let alpha: CGFloat

        switch zone.threatLevel {
        case 1:
            color = UIColor(red: 0, green: 1, blue: 0, alpha: 1)  // Green
            alpha = 0.2
        case 2:
            color = UIColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)  // Cyan
            alpha = 0.25
        case 3:
            color = UIColor(red: 1, green: 0.8, blue: 0, alpha: 1)  // Yellow
            alpha = 0.3
        case 4:
            color = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1)  // Orange
            alpha = 0.35
        default:  // 5
            color = UIColor(red: 1, green: 0, blue: 0, alpha: 1)  // Red
            alpha = 0.4
        }

        fillColor = color.withAlphaComponent(alpha)
        strokeColor = color
        lineWidth = 2
    }
}
