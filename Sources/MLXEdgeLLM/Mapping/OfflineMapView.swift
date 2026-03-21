// OfflineMapView.swift — MKMapView with offline tile support
// Uses OfflineTileProvider for MBTiles/PMTiles rendering

import SwiftUI
import MapKit
import CoreLocation

/// UIViewRepresentable wrapper for MKMapView with offline tile overlay
struct OfflineMapView: UIViewRepresentable {
    @ObservedObject var tileProvider = OfflineTileProvider.shared
    @Binding var region: MKCoordinateRegion?
    var showsUserLocation: Bool = true
    var waypoints: [Waypoint] = []
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showsUserLocation
        mapView.mapType = .mutedStandard  // Muted base layer for overlay visibility
        mapView.overrideUserInterfaceStyle = .dark
        
        // Add offline tile overlay as the base layer
        let offlineOverlay = OfflineTileOverlay()
        offlineOverlay.canReplaceMapContent = true  // Replace Apple Maps tiles completely
        mapView.addOverlay(offlineOverlay, level: .aboveLabels)
        
        // Store reference for updates
        context.coordinator.offlineOverlay = offlineOverlay
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region if provided
        if let region = region {
            let currentCenter = mapView.region.center
            let newCenter = region.center
            
            // Only update if significantly different to avoid jitter
            let latDiff = abs(currentCenter.latitude - newCenter.latitude)
            let lonDiff = abs(currentCenter.longitude - newCenter.longitude)
            
            if latDiff > 0.001 || lonDiff > 0.001 {
                mapView.setRegion(region, animated: true)
            }
        }
        
        // Update waypoint annotations
        let existingWaypoints = mapView.annotations.compactMap { $0 as? WaypointAnnotation }
        let existingIDs = Set(existingWaypoints.map { $0.waypoint.id })
        let newIDs = Set(waypoints.map { $0.id })
        
        // Remove old
        for annotation in existingWaypoints where !newIDs.contains(annotation.waypoint.id) {
            mapView.removeAnnotation(annotation)
        }
        
        // Add new
        for waypoint in waypoints where !existingIDs.contains(waypoint.id) {
            let annotation = WaypointAnnotation(waypoint: waypoint)
            mapView.addAnnotation(annotation)
        }
        
        // Refresh tiles if map changed
        if context.coordinator.currentMapName != tileProvider.currentMap {
            context.coordinator.currentMapName = tileProvider.currentMap
            // Force tile refresh by removing and re-adding overlay
            if let overlay = context.coordinator.offlineOverlay {
                mapView.removeOverlay(overlay)
                let newOverlay = OfflineTileOverlay()
                newOverlay.canReplaceMapContent = true
                mapView.addOverlay(newOverlay, level: .aboveLabels)
                context.coordinator.offlineOverlay = newOverlay
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: OfflineMapView
        var offlineOverlay: OfflineTileOverlay?
        weak var mapView: MKMapView?
        var currentMapName: String?
        
        init(parent: OfflineMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil  // Use default blue dot
            }
            
            if let waypointAnnotation = annotation as? WaypointAnnotation {
                let identifier = "WaypointPin"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: waypointAnnotation, reuseIdentifier: identifier)
                    view?.canShowCallout = true
                }
                
                view?.annotation = waypointAnnotation
                view?.markerTintColor = .cyan
                view?.glyphImage = UIImage(systemName: "mappin.circle.fill")
                
                return view
            }
            
            return nil
        }
    }
}

// MARK: - Waypoint Annotation

final class WaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: Waypoint
    
    var coordinate: CLLocationCoordinate2D {
        waypoint.coordinate
    }
    
    var title: String? {
        waypoint.name
    }
    
    var subtitle: String? {
        // Show altitude if available
        String(format: "%.0fm", waypoint.altitude)
    }
    
    init(waypoint: Waypoint) {
        self.waypoint = waypoint
        super.init()
    }
}

// MARK: - Map Status Overlay

struct MapStatusOverlay: View {
    @ObservedObject var tileProvider = OfflineTileProvider.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // Offline indicator
            if tileProvider.hasOfflineMaps {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(tileProvider.currentMap ?? "Offline")
                        .font(.caption)
                        .foregroundColor(ZDDesign.pureWhite)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.orange)
                    Text("No offline maps")
                        .font(.caption)
                        .foregroundColor(ZDDesign.pureWhite)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OfflineMapView(
        region: .constant(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 29.4241, longitude: -98.4936),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
    )
}
