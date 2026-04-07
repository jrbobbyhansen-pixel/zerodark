// MapTabView.swift — SwiftUI Map (iOS 17+) replacement for TeamMapView
// Renders: TAK peers, waypoints, breadcrumbs, range rings, MGRS, mesh peers, cameras
// Uses MapContentBuilder with Annotation, MapPolyline, MapCircle

import SwiftUI
import MapKit
import CoreLocation

struct MapTabView: View {
    // Singletons (same as TeamMapView)
    @ObservedObject var tak = FreeTAKConnector.shared
    @ObservedObject var takBle = TAKBLEBridge.shared
    @StateObject var offlineTiles = OfflineTileProvider.shared
    @StateObject var waypointStore = TacticalWaypointStore.shared
    @StateObject var mesh = MeshService.shared
    @StateObject var camService = TrafficCamService.shared
    @StateObject var breadcrumb = BreadcrumbEngine.shared
    @StateObject var gisOverlays = GISOverlayProvider.shared
    @StateObject var hotZone = HotZoneClassifier.shared
    @EnvironmentObject var appState: AppState

    // Map state
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedPeer: CoTEvent?
    @State private var showPeerDetails = false
    @State private var showOps = false
    @State private var showWaypointPicker = false
    @State private var pendingCoord: CLLocationCoordinate2D?
    @State private var selectedCam: TrafficCamera?
    @State private var showCelestialNav = false
    @State private var contourLines: [ContourLineData] = []
    @State private var mapSelection: MapSelection<MKMapItem>?
    @State private var losResult: LOSResult?
    @State private var losTarget: CLLocationCoordinate2D?
    @State private var losMode = false
    @State private var showLOSDetails = false
    @State private var viewshedPoints: [(coordinate: CLLocationCoordinate2D, isVisible: Bool)] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                // Offline tile backing layer
                if offlineTiles.hasOfflineMaps {
                    OfflineTileMapLayer(cameraPosition: $cameraPosition, mapRegion: appState.mapRegion)
                        .ignoresSafeArea()
                }

                // Main SwiftUI Map
                MapReader { proxy in
                    Map(position: $cameraPosition, selection: $mapSelection) {
                        // User location
                        UserAnnotation()

                        // TAK peers
                        ForEach(tak.peers, id: \.uid) { peer in
                            if peer.lat != 0 && peer.lon != 0 {
                                Annotation(
                                    peer.detail?.contact?.callsign ?? "Unknown",
                                    coordinate: CLLocationCoordinate2D(latitude: peer.lat, longitude: peer.lon)
                                ) {
                                    PeerDot(peer: peer, tacticalMode: appState.mapLayerConfig.tacticalMode)
                                        .onTapGesture {
                                            selectedPeer = peer
                                            showPeerDetails = true
                                        }
                                }
                            }
                        }

                        // Tactical waypoints
                        ForEach(waypointStore.waypoints) { wp in
                            Annotation(
                                appState.mapLayerConfig.tacticalMode ? wp.tacticalLabel : wp.displayLabel,
                                coordinate: wp.coordinate
                            ) {
                                Image(systemName: wp.type.icon)
                                    .font(.title3)
                                    .foregroundStyle(appState.mapLayerConfig.tacticalMode ? .orange : .green)
                                    .padding(6)
                                    .background(.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                        }

                        // Terrain contour lines
                        if appState.mapLayerConfig.showContours {
                            ForEach(Array(contourLines.enumerated()), id: \.offset) { _, contour in
                                MapPolyline(coordinates: contour.coordinates)
                                    .stroke(
                                        Color.brown.opacity(contour.isMajor ? 0.8 : 0.4),
                                        lineWidth: contour.isMajor ? 1.5 : 0.8
                                    )
                            }
                        }

                        // Breadcrumb trail
                        if appState.mapLayerConfig.showBreadcrumbs && breadcrumb.trail.count >= 2 {
                            MapPolyline(coordinates: breadcrumb.trail)
                                .stroke(.cyan, lineWidth: 3)
                        }

                        // Range rings
                        if appState.mapLayerConfig.showRangeRings, let loc = appState.currentLocation {
                            ForEach([100, 250, 500, 1000, 2000], id: \.self) { radius in
                                MapCircle(center: loc, radius: CLLocationDistance(radius))
                                    .stroke(Color(ZDDesign.cyanAccent).opacity(0.6), lineWidth: 1.5)
                            }
                        }

                        // MGRS grid lines
                        if appState.mapLayerConfig.showMGRS {
                            ForEach(mgrsGridLines(), id: \.self) { line in
                                MapPolyline(coordinates: line)
                                    .stroke(Color(ZDDesign.safetyYellow).opacity(0.5), lineWidth: 0.8)
                            }
                        }

                        // Mesh peer dots
                        if appState.mapLayerConfig.showMeshPeers {
                            ForEach(mesh.peers) { peer in
                                if let loc = peer.location {
                                    Annotation(peer.name, coordinate: loc) {
                                        MeshPeerDot(peer: peer)
                                    }
                                }
                            }
                        }

                        // Traffic cameras
                        if appState.mapLayerConfig.showCameras {
                            ForEach(camService.cameras) { camera in
                                Annotation(camera.name, coordinate: camera.coordinate) {
                                    Image(systemName: "video.fill")
                                        .font(.caption)
                                        .foregroundStyle(selectedCam?.id == camera.id ? Color(ZDDesign.cyanAccent) : .white)
                                        .padding(4)
                                        .background(.black.opacity(0.7))
                                        .clipShape(Circle())
                                        .onTapGesture { selectedCam = camera }
                                }
                            }
                        }

                        // Threat pins
                        if appState.mapLayerConfig.showThreatPins {
                            ForEach(tak.peers.filter { $0.type.contains("a-h") }, id: \.uid) { threat in
                                Annotation("Threat", coordinate: CLLocationCoordinate2D(latitude: threat.lat, longitude: threat.lon)) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color(ZDDesign.signalRed))
                                        .font(.title3)
                                }
                            }
                        }

                        // GIS overlays (KML/Shapefile)
                        if appState.mapLayerConfig.showGISOverlays {
                            ForEach(gisOverlays.overlays) { overlay in
                                switch overlay {
                                case .polygon(_, let name, let coords, let color):
                                    MapPolygon(coordinates: coords)
                                        .foregroundStyle(color.opacity(0.3))
                                        .stroke(color, lineWidth: 2)
                                case .polyline(_, let name, let coords, let color):
                                    MapPolyline(coordinates: coords)
                                        .stroke(color, lineWidth: 2)
                                case .point(_, let name, let coord):
                                    Annotation(name, coordinate: coord) {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundStyle(.purple)
                                    }
                                }
                            }
                        }

                        // LOS raycast segments
                        if let result = losResult {
                            ForEach(Array(result.segments.enumerated()), id: \.offset) { _, segment in
                                MapPolyline(coordinates: [segment.start, segment.end])
                                    .stroke(segment.isVisible ? .green : .red, lineWidth: 3)
                            }
                        }

                        // Viewshed visibility dots (360° LOS)
                        ForEach(Array(viewshedPoints.enumerated()), id: \.offset) { _, point in
                            Annotation("", coordinate: point.coordinate) {
                                Circle()
                                    .fill(point.isVisible ? Color.green.opacity(0.4) : Color.red.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }

                        // HotZone classification overlays
                        ForEach(hotZone.classifications) { zone in
                            MapCircle(center: zone.center, radius: zone.radiusMeters)
                                .foregroundStyle(
                                    Color(red: zone.type.color.r, green: zone.type.color.g, blue: zone.type.color.b)
                                        .opacity(zone.type.color.a)
                                )
                                .stroke(
                                    Color(red: zone.type.color.r, green: zone.type.color.g, blue: zone.type.color.b),
                                    lineWidth: 2
                                )
                        }
                    }
                    .mapStyle(currentMapStyle)
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                        MapUserLocationButton()
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        appState.mapRegion = context.region
                        appState.currentLocation = context.region.center
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded { value in
                                switch value {
                                case .second(true, let drag):
                                    if let location = drag?.location {
                                        if let coord = proxy.convert(location, from: .local) {
                                            if losMode {
                                                // LOS mode: compute line-of-sight from user to tapped point
                                                losTarget = coord
                                                if let userLoc = appState.currentLocation {
                                                    losResult = LOSRaycastEngine.shared.computeLOS(from: userLoc, to: coord)
                                                    showLOSDetails = true
                                                }
                                            } else {
                                                pendingCoord = coord
                                                showWaypointPicker = true
                                            }
                                        }
                                    }
                                default: break
                                }
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard losMode else { return }
                                if let coord = proxy.convert(value.location, from: .local) {
                                    losTarget = coord
                                    if let userLoc = appState.currentLocation {
                                        losResult = LOSRaycastEngine.shared.computeLOS(from: userLoc, to: coord)
                                        showLOSDetails = true
                                    }
                                }
                            }
                    )
                }
                .ignoresSafeArea()
                .onAppear {
                    offlineTiles.scanForMaps()
                    gisOverlays.scanForGISFiles()
                    if !breadcrumb.isRecording {
                        breadcrumb.startRecording()
                    }
                }

                // MGRS HUD
                if appState.mapLayerConfig.showMGRS, let loc = appState.currentLocation {
                    Text(MGRSConverter.toMGRS(coordinate: loc, precision: 5))
                        .font(.caption.monospaced())
                        .foregroundColor(Color(ZDDesign.safetyYellow))
                        .padding(8)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                        .padding(.top, 8)
                        .padding(.leading, 12)
                }

                // Mesh status badge
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(mesh.isActive ? Color(ZDDesign.successGreen) : Color(ZDDesign.signalRed))
                            .frame(width: 10, height: 10)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(mesh.isActive ? Color(ZDDesign.successGreen) : Color(ZDDesign.mediumGray))
                        Text("Mesh")
                            .font(.caption)
                            .foregroundColor(Color(ZDDesign.pureWhite))
                        Text("\(mesh.peers.count) peers")
                            .font(.caption2)
                            .foregroundColor(Color(ZDDesign.mediumGray))
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
                    tacticalToolbar
                }
            }
            .navigationTitle("Map")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showOps = true } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(ZDDesign.signalRed))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appState.mapLayerConfig.showCameras.toggle()
                        if appState.mapLayerConfig.showCameras && camService.cameras.isEmpty {
                            Task {
                                if let loc = appState.currentLocation {
                                    await camService.fetchNearbyCameras(location: CLLocation(latitude: loc.latitude, longitude: loc.longitude))
                                }
                            }
                        }
                    } label: {
                        Image(systemName: appState.mapLayerConfig.showCameras ? "video.fill" : "video")
                            .foregroundColor(appState.mapLayerConfig.showCameras ? Color(ZDDesign.cyanAccent) : .white)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Refresh Peers") { tak.sendPing() }
                        Button("Center on Me") {
                            cameraPosition = .userLocation(fallback: .automatic)
                        }
                        Button("Toggle Satellite") { appState.mapLayerConfig.useSatellite.toggle() }
                        Button("Toggle Tactical") { appState.mapLayerConfig.tacticalMode.toggle() }
                        Button(appState.mapLayerConfig.showMGRS ? "Hide MGRS Grid" : "Show MGRS Grid") {
                            appState.mapLayerConfig.showMGRS.toggle()
                        }
                        Button("Night Mode") { appState.mapLayerConfig.nightMode.toggle() }
                        Button {
                            showCelestialNav = true
                        } label: {
                            Label("Star Navigation", systemImage: "star.circle")
                        }
                        Button("Export Waypoints") { shareWaypoints() }
                        Button("Mark HotZone") {
                            if let loc = appState.currentLocation {
                                Task {
                                    let reading = HazmatSensorReading(
                                        timestamp: Date(),
                                        coordinate: loc,
                                        gasConcentrationPPM: nil,
                                        radiationUSvH: nil,
                                        temperatureCelsius: nil,
                                        oxygenPercent: nil
                                    )
                                    _ = await hotZone.classify(reading)
                                }
                            }
                        }
                        if breadcrumb.isRecording {
                            Button("Stop Breadcrumbs") { breadcrumb.stopRecording() }
                        } else {
                            Button("Start Breadcrumbs") { breadcrumb.startRecording() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Color(ZDDesign.cyanAccent))
                    }
                }
            }
            .sheet(isPresented: $showPeerDetails) {
                if let peer = selectedPeer {
                    PeerDetailsSheet(event: peer)
                }
            }
            .sheet(isPresented: $showOps) {
                CoordinationView()
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
                CelestialNavSheet()
            }
            .sheet(isPresented: $showLOSDetails) {
                if let result = losResult,
                   let userLoc = appState.currentLocation,
                   let target = losTarget {
                    NavigationStack {
                        VStack(spacing: 16) {
                            LineOfSightView(from: userLoc, to: target)

                            if result.segments.count > 1 {
                                LOSMapSnippet(viewModel: LineOfSightViewModel(
                                    startPoint: userLoc,
                                    endPoint: target
                                ))
                                .frame(height: 250)
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                        .navigationTitle("Line of Sight")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showLOSDetails = false }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .onReceive(appState.mapEventBus) { event in
                handleMapEvent(event)
            }
        }
    }

    // MARK: - Map Style

    private var currentMapStyle: MapStyle {
        if appState.mapLayerConfig.nightMode {
            return .standard(pointsOfInterest: .excludingAll)
        } else if appState.mapLayerConfig.useSatellite {
            return .hybrid
        } else {
            return .standard
        }
    }

    // MARK: - Tactical Toolbar

    private var tacticalToolbar: some View {
        HStack(spacing: 12) {
            ToolbarToggle(
                icon: appState.mapLayerConfig.showRangeRings ? "target" : "circle",
                active: appState.mapLayerConfig.showRangeRings
            ) {
                appState.mapLayerConfig.showRangeRings.toggle()
            }

            ToolbarToggle(text: "MGRS", active: appState.mapLayerConfig.showMGRS) {
                appState.mapLayerConfig.showMGRS.toggle()
            }

            ToolbarToggle(icon: "mountain.2.fill", label: "Terrain", active: appState.mapLayerConfig.showContours) {
                appState.mapLayerConfig.showContours.toggle()
                if appState.mapLayerConfig.showContours && contourLines.isEmpty {
                    generateContourLines()
                }
            }

            ToolbarToggle(
                icon: appState.mapLayerConfig.showThreatPins ? "exclamationmark.triangle.fill" : "exclamationmark.triangle",
                active: appState.mapLayerConfig.showThreatPins,
                activeColor: Color(ZDDesign.signalRed)
            ) {
                appState.mapLayerConfig.showThreatPins.toggle()
            }

            Menu {
                Button(losMode ? "Disable LOS Mode" : "Enable LOS Mode") {
                    losMode.toggle()
                    if !losMode {
                        losResult = nil
                        losTarget = nil
                        viewshedPoints = []
                    }
                }
                if losResult != nil {
                    Button("LOS Details") {
                        showLOSDetails = true
                    }
                }
                Button("Show Viewshed") {
                    guard let userLoc = appState.currentLocation else { return }
                    Task.detached {
                        let points = LOSRaycastEngine.shared.computeViewshed(from: userLoc, radius: 2000, resolution: 36)
                        await MainActor.run {
                            viewshedPoints = points
                        }
                    }
                }
                if !viewshedPoints.isEmpty {
                    Button("Clear Viewshed") {
                        viewshedPoints = []
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "eye.fill")
                        .font(.title3)
                    Text("LOS")
                        .font(.caption2)
                }
                .foregroundColor(losMode ? .green : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - MGRS Grid Lines

    private func mgrsGridLines() -> [[CLLocationCoordinate2D]] {
        let region = appState.mapRegion
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)

        let spacing: Double
        if span > 10 { spacing = 6.0 }
        else if span > 1 { spacing = 1.0 }
        else if span > 0.1 { spacing = 0.1 }
        else { spacing = 0.01 }

        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        var lines: [[CLLocationCoordinate2D]] = []

        // Vertical lines
        var lon = (minLon / spacing).rounded(.down) * spacing
        while lon <= maxLon {
            lines.append([
                CLLocationCoordinate2D(latitude: minLat, longitude: lon),
                CLLocationCoordinate2D(latitude: maxLat, longitude: lon)
            ])
            lon += spacing
        }

        // Horizontal lines
        var lat = (minLat / spacing).rounded(.down) * spacing
        while lat <= maxLat {
            lines.append([
                CLLocationCoordinate2D(latitude: lat, longitude: minLon),
                CLLocationCoordinate2D(latitude: lat, longitude: maxLon)
            ])
            lat += spacing
        }

        return lines
    }

    // MARK: - Event Handling

    private func handleMapEvent(_ event: MapEvent) {
        switch event {
        case .centerOnCoordinate(let coord):
            cameraPosition = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        case .highlightWaypoint(let id):
            appState.selectedWaypointId = id
            if let wp = waypointStore.waypoints.first(where: { $0.id == id }) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: wp.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))
            }
        case .showLOS(let from, let to):
            losTarget = to
            losResult = LOSRaycastEngine.shared.computeLOS(from: from, to: to)
        case .zoomToRegion(let region):
            cameraPosition = .region(region)
        case .refreshPeers:
            tak.sendPing()
        }
    }

    // MARK: - Contour Generation

    private func generateContourLines() {
        let region = appState.mapRegion
        Task.detached {
            let overlay = ContourOverlay(region: region, contourInterval: 30)
            overlay.generateContours(resolution: 40)
            let lines: [ContourLineData] = overlay.contourLines.compactMap { contour in
                let coords = contour.points.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                }
                guard coords.count >= 2 else { return nil }
                return ContourLineData(
                    coordinates: coords,
                    elevation: contour.elevation,
                    isMajor: contour.isMajor
                )
            }
            await MainActor.run {
                contourLines = lines
            }
        }
    }

    // MARK: - Sharing

    private func shareWaypoints() {
        let gpxData = waypointStore.exportGPX()
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("waypoints.gpx")
        try? gpxData.write(to: tmpURL)
        let ac = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first?.rootViewController?
            .present(ac, animated: true)
    }
}

// MARK: - Peer Dot

private struct PeerDot: View {
    let peer: CoTEvent
    let tacticalMode: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(affiliationColor)
                .clipShape(Circle())

            Text(peer.detail?.contact?.callsign ?? "?")
                .font(.caption2)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private var affiliationColor: Color {
        if peer.type.contains("a-f") { return .blue }
        if peer.type.contains("a-h") { return .red }
        if peer.type.contains("b-m-p-s-p-i") { return .orange }
        return .yellow
    }
}

// MARK: - Mesh Peer Dot

private struct MeshPeerDot: View {
    let peer: ZDPeer

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 12, height: 12)
            .overlay(
                Circle().stroke(.black, lineWidth: 1)
            )
    }

    private var statusColor: Color {
        switch peer.status {
        case .online: return .green
        case .away: return .yellow
        case .sos: return .red
        case .offline: return .gray
        }
    }
}

// MARK: - Toolbar Toggle Button

private struct ToolbarToggle: View {
    var icon: String?
    var text: String?
    var label: String?
    var active: Bool
    var activeColor: Color = Color(ZDDesign.safetyYellow)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                }
                if let text {
                    Text(text)
                        .font(.caption.bold())
                }
                if let label {
                    Text(label)
                        .font(.caption2)
                }
            }
            .foregroundColor(active ? activeColor : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
        }
    }
}

// MARK: - Contour Line Data

struct ContourLineData: Hashable {
    let coordinates: [CLLocationCoordinate2D]
    let elevation: Double
    let isMajor: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(elevation)
        hasher.combine(coordinates.count)
        hasher.combine(isMajor)
    }

    static func == (lhs: ContourLineData, rhs: ContourLineData) -> Bool {
        lhs.elevation == rhs.elevation && lhs.coordinates.count == rhs.coordinates.count
    }
}

// MARK: - Hashable Array of Coordinates (for ForEach)

extension Array: @retroactive Hashable where Element == CLLocationCoordinate2D {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        if let first { hasher.combine(first.latitude); hasher.combine(first.longitude) }
        if let last { hasher.combine(last.latitude); hasher.combine(last.longitude) }
    }
}

#Preview {
    MapTabView()
        .environmentObject(AppState.shared)
}
