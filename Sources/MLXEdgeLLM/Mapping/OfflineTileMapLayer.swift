// OfflineTileMapLayer.swift — Thin UIViewRepresentable for offline tile backing layer
// Used behind SwiftUI Map in ZStack when offline tiles are active (iOS 17 workaround)
// iOS 18+ can replace this with native MapTileOverlay

import SwiftUI
import MapKit

struct OfflineTileMapLayer: UIViewRepresentable {
    @Binding var cameraPosition: MapCameraPosition
    let mapRegion: MKCoordinateRegion  // Fallback from AppState

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isUserInteractionEnabled = false
        mapView.showsUserLocation = false
        mapView.overrideUserInterfaceStyle = .dark

        let tileOverlay = OfflineTileOverlay()
        tileOverlay.canReplaceMapContent = true
        mapView.addOverlay(tileOverlay, level: .aboveLabels)

        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Resolve region from camera position, falling back to AppState region
        let targetRegion: MKCoordinateRegion
        switch cameraPosition {
        case .region(let region):
            targetRegion = region
        case .camera(let camera):
            targetRegion = MKCoordinateRegion(
                center: camera.centerCoordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: max(0.001, 360.0 / pow(2.0, Double(camera.distance) / 5000.0)),
                    longitudeDelta: max(0.001, 360.0 / pow(2.0, Double(camera.distance) / 5000.0))
                )
            )
        default:
            // .userLocation, .automatic, .rect — use AppState's tracked region
            targetRegion = mapRegion
        }

        let current = mapView.region
        let latDiff = abs(current.center.latitude - targetRegion.center.latitude)
        let lonDiff = abs(current.center.longitude - targetRegion.center.longitude)
        let spanDiff = abs(current.span.latitudeDelta - targetRegion.span.latitudeDelta)

        if latDiff > 0.0001 || lonDiff > 0.0001 || spanDiff > 0.001 {
            mapView.setRegion(targetRegion, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
