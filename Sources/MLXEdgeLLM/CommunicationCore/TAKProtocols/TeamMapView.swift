// TeamMapView.swift — TAK Team Peer Visualization on Map
// Displays CoT events from TAK server and BLE as map annotations

import SwiftUI
import MapKit
import CoreLocation

struct TeamMapView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @ObservedObject var tak = FreeTAKConnector.shared
    @ObservedObject var takBle = TAKBLEBridge.shared
    @State private var selectedPeer: CoTEvent?
    @State private var showPeerDetails = false
    @State private var showRangeRings = false
    @State private var showMGRS = false
    @State private var showThreatPins = true
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationManager = CLLocationManager()
    @State private var shouldCenterOnUser = false
    @State private var useSatelliteMap = false
    @ObservedObject private var offlineTiles = OfflineTileProvider.shared
    @ObservedObject private var waypointStore = TacticalWaypointStore.shared
    @ObservedObject private var mesh = MeshService.shared
    @State private var tacticalMode = false
    @State private var showWaypointPicker = false
    @State private var pendingCoord: CLLocationCoordinate2D?
    @State private var showOps = false
    @State private var showContours = false
    @State private var contourOverlay: ContourOverlay?
    @ObservedObject private var camService = TrafficCamService.shared
    @State private var showCameras = false
    @State private var selectedCam: TrafficCamera?
    @State private var showCelestialNav = false
    @State private var shareURL: URL?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),  // Updated by LocationManager on appear
        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)  // ~1.5km tactical view
    )
    @State private var hasInitializedRegion = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                // Map with overlays
                MapViewWithOverlays(
                    peers: tak.peers,
                    showMGRS: showMGRS,
                    showRangeRings: showRangeRings,
                    userLocation: $userLocation,
                    shouldCenterOnUser: $shouldCenterOnUser,
                    useSatelliteMap: useSatelliteMap,
                    useOfflineTiles: offlineTiles.hasOfflineMaps,
                    waypoints: waypointStore.waypoints,
                    tacticalMode: tacticalMode,
                    region: $mapRegion,
                    cameras: showCameras ? camService.cameras : [],
                    selectedCam: $selectedCam,
                    showContours: showContours,
                    contourOverlay: contourOverlay,
                    onLongPress: { coord in
                        pendingCoord = coord
                        showWaypointPicker = true
                    }
                )
                .ignoresSafeArea()
                .onAppear {
                    locationManager.requestWhenInUseAuthorization()
                    locationManager.startUpdatingLocation()
                    if let location = locationManager.location {
                        userLocation = location.coordinate
                        // Center map on user location with tactical zoom
                        if !hasInitializedRegion {
                            mapRegion = MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                            )
                            hasInitializedRegion = true
                        }
                    }
                    offlineTiles.scanForMaps()
                }
                .task {
                    // Wait briefly for location to become available, then center
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 sec
                    if let location = locationManager.location, !hasInitializedRegion {
                        mapRegion = MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                        )
                        hasInitializedRegion = true
                        shouldCenterOnUser = true
                    }
                }

                // MGRS HUD (top)
                if showMGRS, let location = userLocation {
                    Text(MGRSConverter.toMGRS(coordinate: location, precision: 5))
                        .font(.caption.monospaced())
                        .foregroundColor(ZDDesign.safetyYellow)
                        .padding(8)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                        .padding(.top, 8)
                        .padding(.leading, 12)
                }

                // Status badges (top-left)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(mesh.isActive ? ZDDesign.successGreen : ZDDesign.signalRed)
                            .frame(width: 10, height: 10)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(mesh.isActive ? ZDDesign.successGreen : ZDDesign.mediumGray)
                        Text("Mesh")
                            .font(.caption)
                            .foregroundColor(ZDDesign.pureWhite)
                        Text("\(mesh.peers.count) peers")
                            .font(.caption2)
                            .foregroundColor(ZDDesign.mediumGray)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                }
                .padding(12)

                // Tactical toolbar (bottom)
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        // Range rings toggle
                        Button {
                            showRangeRings.toggle()
                        } label: {
                            Image(systemName: showRangeRings ? "target" : "circle")
                                .foregroundColor(showRangeRings ? ZDDesign.safetyYellow : .white)
                                .font(.title3)
                                .padding(10)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        }

                        // MGRS toggle
                        Button {
                            showMGRS.toggle()
                        } label: {
                            Text("MGRS")
                                .font(.caption.bold())
                                .foregroundColor(showMGRS ? ZDDesign.safetyYellow : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        }

                        // Terrain contour toggle
                        Button {
                            showContours.toggle()
                            if showContours && contourOverlay == nil {
                                // Generate contours for current region
                                Task {
                                    let overlay = ContourOverlay(region: mapRegion, contourInterval: 30)
                                    await Task.detached {
                                        overlay.generateContours(resolution: 40)
                                    }.value
                                    await MainActor.run {
                                        contourOverlay = overlay
                                    }
                                }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "mountain.2.fill")
                                    .font(.title3)
                                Text("Terrain")
                                    .font(.caption2)
                            }
                            .foregroundColor(showContours ? ZDDesign.cyanAccent : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                        }

                        // Threat pins toggle
                        Button {
                            showThreatPins.toggle()
                        } label: {
                            Image(systemName: showThreatPins ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                .foregroundColor(showThreatPins ? ZDDesign.signalRed : .white)
                                .font(.title3)
                                .padding(10)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Team Map")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showOps = true } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(ZDDesign.signalRed)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCameras.toggle()
                        if showCameras && camService.cameras.isEmpty {
                            Task {
                                if let loc = LocationManager.shared.currentLocation {
                                    await camService.fetchNearbyCameras(location: loc)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: showCameras ? "video.fill" : "video")
                            .foregroundColor(showCameras ? ZDDesign.cyanAccent : .white)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Refresh Peers") { tak.sendPing() }
                        Button("Center on Me") {
                            if userLocation != nil { shouldCenterOnUser = true }
                        }
                        Button("Toggle Satellite") { useSatelliteMap.toggle() }
                        Button("Toggle Tactical") { tacticalMode.toggle() }
                        Button(showMGRS ? "Hide MGRS Grid" : "Show MGRS Grid") { showMGRS.toggle() }
                        Button {
                            showCelestialNav = true
                        } label: {
                            Label("Star Navigation", systemImage: "star.circle")
                        }
                        Button("Export Waypoints") { shareWaypoints() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showPeerDetails) {
                if let peer = selectedPeer {
                    PeerDetailsView(event: peer)
                }
            }
            .sheet(isPresented: $showOps) {
                Text("Operations Coordination").font(.title2).padding()
            }
            .sheet(isPresented: $showWaypointPicker) {
                if let coord = pendingCoord {
                    WaypointPickerSheet(coordinate: coord)
                }
            }
            .sheet(item: $selectedCam) { cam in
                CameraFeedView(camera: cam)
            }
            .sheet(isPresented: $showCelestialNav) {
                CelestialNavStatusView()
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    private func isLocationEvent(_ event: CoTEvent) -> Bool {
        return event.type.contains("a-") || event.type.contains("b-m-p")
    }

    private func shareWaypoints() {
        let gpxData = waypointStore.exportGPX()
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("waypoints.gpx")
        try? gpxData.write(to: tmpURL)
        shareURL = tmpURL
    }

    private func affiliationColor(_ type: String) -> Color {
        if type.contains("a-f") {
            return .blue  // Friendly
        } else if type.contains("a-h") {
            return .red   // Hostile
        } else if type.contains("b-m-p-s-p-i") {
            return .orange  // Emergency marker
        } else {
            return .yellow  // Unknown
        }
    }
}

struct PeerDetailsView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    let event: CoTEvent

    var body: some View {
        NavigationStack {
            List {
                Section("Identity") {
                    LabeledContent("Callsign", value: event.detail?.contact?.callsign ?? "Unknown")
                    LabeledContent("UID", value: event.uid.prefix(16) + "...")
                }

                Section("Position") {
                    LabeledContent("Latitude", value: String(format: "%.6f", event.lat))
                    LabeledContent("Longitude", value: String(format: "%.6f", event.lon))

                    if event.hae != 9999999 {
                        LabeledContent("Altitude", value: String(format: "%.1f m", event.hae))
                    }

                    if event.ce != 9999999 {
                        LabeledContent("Accuracy (CE)", value: String(format: "±%.1f m", event.ce))
                    }
                }

                Section("Status") {
                    LabeledContent("Type", value: event.type)
                    LabeledContent("How", value: event.how)

                    if let battery = event.detail?.status?.battery {
                        HStack {
                            Text("Battery")
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon(battery))
                                    .foregroundColor(batteryColor(battery))
                                Text("\(battery)%")
                            }
                        }
                    }

                    let formatter = ISO8601DateFormatter()
                    LabeledContent("Last Update", value: formatter.string(from: event.time))
                }

                Section("Movement") {
                    if let track = event.detail?.track {
                        LabeledContent("Speed", value: String(format: "%.1f m/s (%.1f km/h)", track.speed, track.speed * 3.6))
                        LabeledContent("Course", value: String(format: "%.0f°", track.course))
                    } else {
                        Text("No movement data")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }

                Section("Device") {
                    if let takv = event.detail?.takv {
                        LabeledContent("Device", value: takv.device)
                        LabeledContent("Platform", value: takv.platform)
                        LabeledContent("OS", value: takv.os)
                        LabeledContent("Version", value: takv.version)
                    } else {
                        Text("No device info")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
            }
            .navigationTitle(event.detail?.contact?.callsign ?? "Unknown Peer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func batteryIcon(_ percent: Int) -> String {
        switch percent {
        case 75...100: return "battery.100"
        case 50...74: return "battery.75"
        case 25...49: return "battery.50"
        case 1...24: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryColor(_ percent: Int) -> Color {
        if percent > 50 {
            return .green
        } else if percent > 20 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - MGRS Grid Overlay

final class MGRSGridOverlayGenerator {
    enum GridLevel {
        case gzd, km100, km10, km1
    }

    static func gridLines(for region: MKCoordinateRegion, level: GridLevel) -> [MKPolyline] {
        var polylines: [MKPolyline] = []
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        let spacing: Double
        switch level {
        case .gzd: spacing = 6.0
        case .km100: spacing = 1.0
        case .km10: spacing = 0.1
        case .km1: spacing = 0.01
        }

        var lon = (minLon / spacing).rounded(.down) * spacing
        while lon <= maxLon {
            var coords = [
                CLLocationCoordinate2D(latitude: minLat, longitude: lon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: lon)
            ]
            polylines.append(MKPolyline(coordinates: &coords, count: 2))
            lon += spacing
        }

        var lat = (minLat / spacing).rounded(.down) * spacing
        while lat <= maxLat {
            var coords = [
                CLLocationCoordinate2D(latitude: lat, longitude: minLon),
                CLLocationCoordinate2D(latitude: lat, longitude: maxLon)
            ]
            polylines.append(MKPolyline(coordinates: &coords, count: 2))
            lat += spacing
        }
        return polylines
    }

    static func levelForSpan(_ span: MKCoordinateSpan) -> GridLevel {
        let delta = max(span.latitudeDelta, span.longitudeDelta)
        if delta > 10 { return .gzd }
        if delta > 1 { return .km100 }
        if delta > 0.1 { return .km10 }
        return .km1
    }
}

final class MGRSGridRenderer: MKOverlayRenderer {
    let polylines: [MKPolyline]

    init(polylines: [MKPolyline], overlay: MKOverlay) {
        self.polylines = polylines
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setStrokeColor(UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 0.6).cgColor)
        context.setLineWidth(1.0 / zoomScale)

        for polyline in polylines {
            guard polyline.boundingMapRect.intersects(mapRect) else { continue }
            let path = CGMutablePath()
            var firstPoint = true

            for i in 0..<polyline.pointCount {
                let mapPoint = polyline.points()[i]
                let point = self.point(for: mapPoint)
                if firstPoint {
                    path.move(to: point)
                    firstPoint = false
                } else {
                    path.addLine(to: point)
                }
            }
            context.addPath(path)
            context.strokePath()
        }
    }
}

final class MGRSGridOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }
    var boundingMapRect: MKMapRect { MKMapRect.world }
}

// MARK: - Range Ring Overlay

final class RangeRingGenerator {
    static func rings(center: CLLocationCoordinate2D) -> [MKCircle] {
        [100, 250, 500, 1000, 2000].map { distance in
            MKCircle(center: center, radius: Double(distance))
        }
    }
}

final class RangeRingRenderer: MKCircleRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        let labelPoint = point(for: MKMapPoint(circle.coordinate))
        let offsetPoint = CGPoint(x: labelPoint.x, y: labelPoint.y - circle.radius * Double(zoomScale) - 20)
        let label = formatDistance(circle.radius)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10 / zoomScale, weight: .medium),
            .foregroundColor: UIColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1.0)
        ]
        label.draw(at: offsetPoint, withAttributes: attributes)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}

// MARK: - Map with Overlay Support

struct MapViewWithOverlays: UIViewRepresentable {
    let peers: [CoTEvent]
    let showMGRS: Bool
    let showRangeRings: Bool
    @Binding var userLocation: CLLocationCoordinate2D?
    @Binding var shouldCenterOnUser: Bool
    let useSatelliteMap: Bool
    let useOfflineTiles: Bool
    let waypoints: [TacticalWaypoint]
    let tacticalMode: Bool
    @Binding var region: MKCoordinateRegion
    let cameras: [TrafficCamera]
    @Binding var selectedCam: TrafficCamera?
    let showContours: Bool
    let contourOverlay: ContourOverlay?
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .standard
        mapView.overrideUserInterfaceStyle = .dark

        // Add offline tile overlay if available
        if useOfflineTiles {
            let offlineOverlay = OfflineTileOverlay()
            offlineOverlay.canReplaceMapContent = true
            mapView.addOverlay(offlineOverlay, level: .aboveLabels)
        }

        // Add long-press gesture for waypoint creation
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update overlays
        mapView.removeOverlays(mapView.overlays)

        if showMGRS {
            let mgrsOverlay = MGRSGridOverlay()
            mapView.addOverlay(mgrsOverlay, level: .aboveLabels)
        }

        if showRangeRings, let location = userLocation {
            let rings = RangeRingGenerator.rings(center: location)
            mapView.addOverlays(rings, level: .aboveLabels)
        }
        
        // Add contour overlay if enabled
        if showContours, let overlay = contourOverlay {
            mapView.addOverlay(overlay, level: .aboveLabels)
        }

        // Update peer annotations
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) && !($0 is TacticalAnnotation) && !($0 is CameraMapAnnotation) })

        for peer in peers {
            if peer.lat != 0 && peer.lon != 0 {
                let annotation = MKPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: peer.lat, longitude: peer.lon)
                annotation.title = peer.detail?.contact?.callsign ?? "Unknown"
                mapView.addAnnotation(annotation)
            }
        }

        // Update waypoint annotations
        for waypoint in waypoints {
            let annotation = TacticalAnnotation(waypoint: waypoint, tacticalMode: tacticalMode)
            mapView.addAnnotation(annotation)
        }

        // Update camera annotations
        for camera in cameras {
            mapView.addAnnotation(CameraMapAnnotation(camera: camera))
        }

        // Update user location binding
        if let location = mapView.userLocation.location?.coordinate {
            DispatchQueue.main.async {
                self.userLocation = location
            }
        }

        // Satellite toggle
        mapView.mapType = useSatelliteMap ? .satellite : .standard

        // Center on user
        if shouldCenterOnUser, let location = userLocation {
            let region = MKCoordinateRegion(center: location, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
            DispatchQueue.main.async { self.shouldCenterOnUser = false }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithOverlays

        init(_ parent: MapViewWithOverlays) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(overlay: tileOverlay)
            }

            if overlay is MGRSGridOverlay {
                let region = mapView.region
                let level = MGRSGridOverlayGenerator.levelForSpan(region.span)
                let polylines = MGRSGridOverlayGenerator.gridLines(for: region, level: level)
                return MGRSGridRenderer(polylines: polylines, overlay: overlay)
            }

            if let circle = overlay as? MKCircle {
                let renderer = RangeRingRenderer(overlay: circle)
                renderer.strokeColor = UIColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 0.7)
                renderer.lineWidth = 1.5
                renderer.lineDashPattern = [8, 4]
                renderer.fillColor = nil
                return renderer
            }
            
            if let contour = overlay as? ContourOverlay {
                return ContourOverlayRenderer(overlay: contour)
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            if let camAnnotation = annotation as? CameraMapAnnotation {
                let id = "CamAnno"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: camAnnotation, reuseIdentifier: id)
                view.annotation = camAnnotation
                view.canShowCallout = false
                view.subviews.forEach { $0.removeFromSuperview() }

                let hosting = UIHostingController(rootView: CameraAnnotationView(
                    camera: camAnnotation.camera,
                    isSelected: camAnnotation.camera.id == self.parent.selectedCam?.id,
                    onTap: { self.parent.selectedCam = camAnnotation.camera }
                ))
                hosting.view.backgroundColor = .clear
                hosting.view.frame = CGRect(x: -30, y: -30, width: 60, height: 60)
                view.addSubview(hosting.view)
                view.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
                return view
            }

            if let tacticalAnnotation = annotation as? TacticalAnnotation {
                let identifier = "tactical"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                if view == nil {
                    view = MKAnnotationView(annotation: tacticalAnnotation, reuseIdentifier: identifier)
                } else {
                    view?.annotation = tacticalAnnotation
                }
                let iconColor = parent.tacticalMode ? UIColor.systemOrange : UIColor.systemGreen
                view?.image = UIImage(systemName: tacticalAnnotation.waypoint.type.icon)?
                    .withTintColor(iconColor, renderingMode: .alwaysOriginal)
                view?.canShowCallout = true
                view?.calloutOffset = CGPoint(x: 0, y: 8)
                return view
            }

            let identifier = "PeerPin"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = true
            } else {
                view?.annotation = annotation
            }

            view?.markerTintColor = .systemBlue
            view?.glyphImage = UIImage(systemName: "person.fill")

            return view
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onLongPress(coordinate)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            if let location = userLocation.location?.coordinate {
                DispatchQueue.main.async {
                    self.parent.userLocation = location
                }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }
    }
}

// MARK: - Tactical Annotation

class TacticalAnnotation: MKPointAnnotation {
    let waypoint: TacticalWaypoint
    let tacticalMode: Bool

    init(waypoint: TacticalWaypoint, tacticalMode: Bool) {
        self.waypoint = waypoint
        self.tacticalMode = tacticalMode
        super.init()
        self.coordinate = waypoint.coordinate
        self.title = tacticalMode ? waypoint.tacticalLabel : waypoint.displayLabel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Waypoint Picker Sheet

struct WaypointPickerSheet: View {
    let coordinate: CLLocationCoordinate2D
    @ObservedObject private var store = TacticalWaypointStore.shared
    @Environment(\.dismiss) var dismiss: DismissAction
    @State private var selectedType: TacticalMarker = .cache
    @State private var tacticalNotes = ""
    @State private var publicDescription = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Marker Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TacticalMarker.allCases, id: \.self) { marker in
                            Label(marker.hikingLabel, systemImage: marker.icon)
                                .tag(marker)
                        }
                    }
                }

                Section("Tactical Notes") {
                    TextField("Details (hidden in hiking mode)", text: $tacticalNotes, axis: .vertical)
                        .lineLimit(3...)
                }

                Section("Public Description") {
                    TextField("Hiking-friendly description", text: $publicDescription, axis: .vertical)
                        .lineLimit(2...)
                }

                Section {
                    Button("Add Waypoint") {
                        store.add(
                            type: selectedType,
                            coordinate: coordinate,
                            tacticalNotes: tacticalNotes,
                            publicDescription: publicDescription.isEmpty ? selectedType.hikingLabel : publicDescription
                        )
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(ZDDesign.successGreen)
                }
            }
            .navigationTitle("Add Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Celestial Navigation Status View

struct CelestialNavStatusView: View {
    @StateObject private var celestial = CelestialNavigator()
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(ZDDesign.cyanAccent)

                    Text("Celestial Navigation")
                        .font(.title2)
                        .foregroundColor(ZDDesign.pureWhite)

                    VStack(spacing: 8) {
                        HStack {
                            Circle()
                                .fill(celestial.isSessionRunning ? ZDDesign.successGreen : ZDDesign.mediumGray)
                                .frame(width: 8, height: 8)
                            Text(celestial.isSessionRunning ? "Session Active" : "Session Inactive")
                                .foregroundColor(celestial.isSessionRunning ? ZDDesign.successGreen : ZDDesign.mediumGray)
                        }

                        Text("Stars Detected: \(celestial.detectedStarCount)")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)

                        if let heading = celestial.estimatedHeading {
                            Text("Heading: \(String(format: "%.1f°", heading))")
                                .font(.headline)
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }

                    Text("Point camera at night sky to detect stars")
                        .foregroundColor(ZDDesign.mediumGray)
                        .multilineTextAlignment(.center)
                        .font(.caption)

                    HStack(spacing: 16) {
                        Button(celestial.isSessionRunning ? "Stop" : "Start") {
                            if celestial.isSessionRunning {
                                celestial.stopSession()
                            } else {
                                celestial.startSession()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(celestial.isSessionRunning ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Star Nav")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            celestial.stopSession()
        }
    }
}

#Preview {
    TeamMapView()
}
