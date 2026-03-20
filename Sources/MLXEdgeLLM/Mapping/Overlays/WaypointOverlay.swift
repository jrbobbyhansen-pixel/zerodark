// WaypointOverlay.swift — Waypoint annotation view for tactical map (uses existing TacticalWaypointAnnotation)

import MapKit
import SwiftUI

/// Waypoint annotation view — renders existing TacticalWaypointAnnotation
public class TacticalWaypointAnnotationView: MKAnnotationView {
    override public var annotation: MKAnnotation? {
        didSet {
            updateAppearance()
        }
    }

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = true
        setupCustomView()
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCustomView() {
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)

        let container = UIView(frame: bounds)
        container.backgroundColor = .clear

        // Icon container
        let iconView = UIView(frame: bounds)
        iconView.backgroundColor = UIColor(red: 0, green: 0.8, blue: 0.8, alpha: 0.8)
        iconView.layer.cornerRadius = 20
        container.addSubview(iconView)

        // Icon label
        let label = UILabel(frame: bounds)
        label.text = "📍"
        label.font = UIFont.systemFont(ofSize: 20)
        label.textAlignment = .center
        container.addSubview(label)

        addSubview(container)
    }

    private func updateAppearance() {
        // Update icon based on annotation title or type
        if let label = subviews.first?.subviews.last as? UILabel {
            label.text = "📍"  // Default marker
        }
    }
}
