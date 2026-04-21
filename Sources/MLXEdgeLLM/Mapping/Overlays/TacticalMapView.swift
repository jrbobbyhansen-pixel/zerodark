// TacticalMapView.swift — Tactical MapKit view with all overlays (DoD ATAK-CIV pattern)

import MapKit
import SwiftUI

/// Tactical map view with overlay support
struct TacticalMapView: UIViewRepresentable {
    @ObservedObject var overlayManager = TacticalOverlayManager.shared

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .satellite

        // Register annotation views
        mapView.register(TeamMemberAnnotationView.self, forAnnotationViewWithReuseIdentifier: "team")
        mapView.register(TacticalWaypointAnnotationView.self, forAnnotationViewWithReuseIdentifier: "waypoint")

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update overlays
        let currentOverlays = Set(mapView.overlays.compactMap { $0 as? NSObject })
        let newOverlays = Set(overlayManager.overlays.compactMap { $0 as? NSObject })

        let toRemove = currentOverlays.subtracting(newOverlays)
        let toAdd = newOverlays.subtracting(currentOverlays)

        for overlay in toRemove {
            if let mkOverlay = overlay as? MKOverlay {
                mapView.removeOverlay(mkOverlay)
            }
        }

        for overlay in toAdd {
            if let mkOverlay = overlay as? MKOverlay {
                mapView.addOverlay(mkOverlay)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let threatZone = overlay as? ThreatZoneOverlay {
                return ThreatZoneRenderer(overlay: threatZone)
            } else if let route = overlay as? TacticalRouteOverlay {
                return TacticalRouteRenderer(overlay: route)
            } else if let contour = overlay as? ContourOverlay {
                return ContourOverlayRenderer(overlay: contour)
            } else {
                // Default renderer for unknown overlays
                return MKOverlayRenderer(overlay: overlay)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let teamMember = annotation as? TeamMemberAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "team", for: annotation) as? TeamMemberAnnotationView
                view?.annotation = teamMember
                return view
            } else if annotation is MKUserLocation {
                return nil  // Use default user location marker
            }
            return nil
        }
    }
}

/// Preview
#Preview {
    TacticalMapView()
        .frame(height: 300)
}
