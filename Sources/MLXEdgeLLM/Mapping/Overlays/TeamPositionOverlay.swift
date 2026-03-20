// TeamPositionOverlay.swift — Team member position annotations on tactical map

import MapKit
import SwiftUI

/// Team member annotation model
public class TeamMemberAnnotation: NSObject, MKAnnotation {
    public dynamic var coordinate: CLLocationCoordinate2D
    public let peerID: String
    public let callsign: String
    public var heading: CLHeading?
    public var speed: CLLocationSpeed = 0
    public var status: String = "online"

    public init(peerID: String, callsign: String, coordinate: CLLocationCoordinate2D) {
        self.peerID = peerID
        self.callsign = callsign
        self.coordinate = coordinate
    }
}

/// Team member annotation view
public class TeamMemberAnnotationView: MKAnnotationView {
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

        // Circle background
        let circle = UIView(frame: bounds)
        circle.backgroundColor = UIColor(red: 0, green: 0.8, blue: 0.8, alpha: 0.8)
        circle.layer.cornerRadius = 20
        container.addSubview(circle)

        // Icon
        let label = UILabel(frame: bounds)
        label.text = "👤"
        label.font = UIFont.systemFont(ofSize: 20)
        label.textAlignment = .center
        container.addSubview(label)

        addSubview(container)
    }

    private func updateAppearance() {
        guard let annotation = annotation as? TeamMemberAnnotation else { return }

        // Update title and subtitle for callout
        if let label = subviews.first?.subviews.last as? UILabel {
            switch annotation.status {
            case "online":
                label.text = "👤"
            case "offline":
                label.text = "❌"
            default:
                label.text = "❓"
            }
        }
    }
}
