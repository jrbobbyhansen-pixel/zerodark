// LineOfSight.swift — LOS computation backed by LOSRaycastEngine + TerrainEngine DEM
// Provides ViewModel for map integration and standalone LOS queries

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - LineOfSight

struct LineOfSight {
    let startPoint: CLLocationCoordinate2D
    let endPoint: CLLocationCoordinate2D
    let observerHeight: Double

    init(startPoint: CLLocationCoordinate2D, endPoint: CLLocationCoordinate2D, observerHeight: Double = 1.8) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.observerHeight = observerHeight
    }

    func compute() -> LOSResult {
        LOSRaycastEngine.shared.computeLOS(
            from: startPoint,
            to: endPoint,
            observerHeight: observerHeight
        )
    }

    func isVisible() -> Bool {
        compute().isVisible
    }
}

// MARK: - ViewModel

class LineOfSightViewModel: ObservableObject {
    @Published var startPoint: CLLocationCoordinate2D
    @Published var endPoint: CLLocationCoordinate2D
    @Published var result: LOSResult?
    @Published var isVisible: Bool = false

    init(startPoint: CLLocationCoordinate2D, endPoint: CLLocationCoordinate2D) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        updateVisibility()
    }

    func updateEndPoint(_ newEndPoint: CLLocationCoordinate2D) {
        endPoint = newEndPoint
        updateVisibility()
    }

    private func updateVisibility() {
        let los = LineOfSight(startPoint: startPoint, endPoint: endPoint)
        result = los.compute()
        isVisible = result?.isVisible ?? false
    }
}

// MARK: - LOS View

struct LineOfSightView: View {
    @StateObject private var viewModel: LineOfSightViewModel

    init(from start: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
         to end: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7760, longitude: -122.4180)) {
        _viewModel = StateObject(wrappedValue: LineOfSightViewModel(startPoint: start, endPoint: end))
    }

    var body: some View {
        VStack(spacing: 16) {
            if let result = viewModel.result {
                HStack {
                    Image(systemName: result.isVisible ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(result.isVisible ? .green : .red)
                    Text(result.isVisible ? "Line of Sight Clear" : "Line of Sight Blocked")
                        .font(.headline)
                }

                Text("Observer: \(String(format: "%.0f", result.observerElevation))m | Target: \(String(format: "%.0f", result.targetElevation))m")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(result.segments.count) segments (\(result.segments.filter(\.isVisible).count) visible)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - LOS Map Snippet (standalone map preview)

struct LOSMapSnippet: UIViewRepresentable {
    @ObservedObject var viewModel: LineOfSightViewModel

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        uiView.removeOverlays(uiView.overlays)

        // Add start/end annotations
        let startPin = MKPointAnnotation()
        startPin.coordinate = viewModel.startPoint
        startPin.title = "Observer"
        uiView.addAnnotation(startPin)

        let endPin = MKPointAnnotation()
        endPin.coordinate = viewModel.endPoint
        endPin.title = "Target"
        uiView.addAnnotation(endPin)

        // Add LOS segments as polylines
        if let result = viewModel.result {
            for segment in result.segments {
                var coords = [segment.start, segment.end]
                let polyline = MKPolyline(coordinates: &coords, count: 2)
                polyline.title = segment.isVisible ? "visible" : "blocked"
                uiView.addOverlay(polyline)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = polyline.title == "visible" ? .green : .red
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
