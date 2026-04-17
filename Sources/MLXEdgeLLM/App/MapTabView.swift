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
    @ObservedObject var offlineTiles = OfflineTileProvider.shared
    @ObservedObject var waypointStore = TacticalWaypointStore.shared
    @ObservedObject var mesh = MeshService.shared
    @ObservedObject var camService = TrafficCamService.shared
    @ObservedObject var breadcrumb = BreadcrumbEngine.shared
    @ObservedObject private var deadReckoning = DeadReckoningEngine.shared
    @ObservedObject private var weather = WeatherForecaster.shared
    @ObservedObject private var celestial = CelestialNavigator.shared
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
    @State private var isGeneratingContours = false
    @State private var mapSelection: MKMapItem?
    @State private var losResult: LOSResult?
    @State private var losTarget: CLLocationCoordinate2D?
    @State private var losMode = false
    @State private var showLOSDetails = false
    @State private var losTerrainWarning = false
    @State private var isComputingViewshed = false
    @State private var viewshedPoints: [(coordinate: CLLocationCoordinate2D, isVisible: Bool)] = []
    @State private var shareURL: URL?
    @State private var selectedWaypoint: TacticalWaypoint?
    // MGRS grid cached — only regenerated on camera-stop, not every render
    @State private var cachedMGRSLines: [[CLLocationCoordinate2D]] = []
    // Navigation mode (merged from NavTabView)
    @State private var navMode = false
    @State private var isComputingNavViewshed = false

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
                        UserAnnotation()
                        mapPeersContent
                        mapWaypointsContent
                        mapOverlaysContent
                        mapAnalysisContent
                        mapNavContent
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
                        if appState.mapLayerConfig.showMGRS {
                            cachedMGRSLines = mgrsGridLines()
                        }
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
                                                losTarget = coord
                                                if let userLoc = appState.currentLocation {
                                                    if TerrainEngine.shared.elevationAt(coordinate: coord) == nil {
                                                        losTerrainWarning = true
                                                    }
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
                                        if TerrainEngine.shared.elevationAt(coordinate: coord) == nil {
                                            losTerrainWarning = true
                                        }
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

                // Navigation HUD (bottom-left)
                VStack {
                    Spacer()
                    HStack {
                        NavigationHUD(breadcrumb: breadcrumb)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                // Tactical toolbar (bottom) + optional nav status bar above it
                VStack {
                    Spacer()
                    if navMode {
                        navStatusBar
                    }
                    tacticalToolbar
                }

                // Nav HUD strip (top) — shown when navMode is active
                if navMode {
                    VStack {
                        navHUDStrip
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
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
                                    await camService.fetchNearbyCameras(location: loc)
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
                NavigationStack {
                    ComingSoonView(title: "Operations Coordination", icon: "person.2.wave.2.fill", description: "Multi-agency coordination, incident command & resource management")
                }
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
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(item: $selectedWaypoint) { wp in
                WaypointDetailSheet(waypoint: wp, store: waypointStore)
            }
            .alert("No Terrain Data", isPresented: $losTerrainWarning) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No elevation data is available for this area. LOS results assume flat terrain and may be inaccurate. Load HGT tiles in Settings to enable accurate line-of-sight.")
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
                if appState.mapLayerConfig.showMGRS {
                    cachedMGRSLines = mgrsGridLines()
                }
            }

            ToolbarToggle(
                icon: isGeneratingContours ? "hourglass" : "mountain.2.fill",
                label: "Terrain",
                active: appState.mapLayerConfig.showContours
            ) {
                appState.mapLayerConfig.showContours.toggle()
                if appState.mapLayerConfig.showContours && contourLines.isEmpty && !isGeneratingContours {
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
                Button(isComputingViewshed ? "Computing…" : "Show Viewshed") {
                    guard let userLoc = appState.currentLocation, !isComputingViewshed else { return }
                    if TerrainEngine.shared.elevationAt(coordinate: userLoc) == nil {
                        losTerrainWarning = true
                    }
                    isComputingViewshed = true
                    Task.detached {
                        let points = LOSRaycastEngine.shared.computeViewshed(from: userLoc, radius: 2000, resolution: 36)
                        await MainActor.run {
                            viewshedPoints = points
                            isComputingViewshed = false
                        }
                    }
                }
                .disabled(isComputingViewshed)
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

            ToolbarToggle(text: "NAV", active: navMode) {
                navMode.toggle()
            }

            if offlineTiles.hasOfflineMaps {
                Menu {
                    ForEach(offlineTiles.availableMaps, id: \.self) { name in
                        Button {
                            offlineTiles.selectMap(name)
                        } label: {
                            if name == offlineTiles.currentMap {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "internaldrive")
                            .font(.title3)
                        Text("MAP")
                            .font(.caption2)
                    }
                    .foregroundColor(ZDDesign.cyanAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                }
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
        isGeneratingContours = true
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
                isGeneratingContours = false
            }
        }
    }

    // MARK: - Nav Mode Overlays

    private var navHUDStrip: some View {
        HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(String(format: "%.1f", appState.navState.speed))
                    .font(.system(.callout, design: .monospaced, weight: .bold))
                    .foregroundColor(ZDDesign.pureWhite)
                Text("m/s").font(.caption2).foregroundColor(ZDDesign.mediumGray)
            }
            Divider().frame(height: 28)
            VStack(spacing: 1) {
                Text(String(format: "%03.0f\u{00B0}", appState.navState.heading))
                    .font(.system(.callout, design: .monospaced, weight: .bold))
                    .foregroundColor(ZDDesign.pureWhite)
                Text("HDG").font(.caption2).foregroundColor(ZDDesign.mediumGray)
            }
            Divider().frame(height: 28)
            VStack(spacing: 1) {
                Text(String(format: "%.0fm", appState.navState.altitude))
                    .font(.system(.callout, design: .monospaced, weight: .bold))
                    .foregroundColor(ZDDesign.pureWhite)
                Text("ALT").font(.caption2).foregroundColor(ZDDesign.mediumGray)
            }
            Divider().frame(height: 28)
            VStack(spacing: 1) {
                Text(String(format: "%.1fm", appState.navState.ekfUncertainty))
                    .font(.system(.callout, design: .monospaced, weight: .bold))
                    .foregroundColor(appState.navState.ekfUncertainty > 10 ? ZDDesign.signalRed : ZDDesign.pureWhite)
                Text("ERR").font(.caption2).foregroundColor(ZDDesign.mediumGray)
            }
            Spacer()
            Button {
                Task { await computeNavViewshed() }
            } label: {
                if isComputingNavViewshed {
                    ProgressView().tint(ZDDesign.cyanAccent)
                } else {
                    Image(systemName: "eye.circle")
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .disabled(isComputingNavViewshed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ZDDesign.darkCard.opacity(0.92))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var navStatusBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 4) {
                Image(systemName: appState.navState.canopyDetected ? "leaf.fill" : "leaf")
                    .foregroundColor(appState.navState.canopyDetected ? .orange : .green)
                Text(appState.navState.canopyDetected ? "CANOPY" : "OPEN")
                    .font(.caption).foregroundColor(ZDDesign.pureWhite)
            }
            HStack(spacing: 4) {
                Image(systemName: "shoeprints.fill").foregroundColor(ZDDesign.cyanAccent)
                Text("ZUPT:\(appState.navState.zuptCount)")
                    .font(.caption).foregroundColor(ZDDesign.pureWhite)
            }
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundColor(celestial.detectedStarCount >= 2 ? .yellow : ZDDesign.mediumGray)
                Text("\(celestial.detectedStarCount)★")
                    .font(.caption).foregroundColor(ZDDesign.pureWhite)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: navBatteryIcon).foregroundColor(navBatteryColor)
                Text(String(format: "%.0fm", appState.navState.batteryMinutesRemaining))
                    .font(.caption).foregroundColor(ZDDesign.pureWhite)
            }
            HStack(spacing: 4) {
                Image(systemName: navBaroIcon).foregroundColor(ZDDesign.cyanAccent)
                Text(weather.barometricPressureTrend == .stable ? "STABLE" :
                     weather.barometricPressureTrend == .rapidDrop ? "DROP" : "RISE")
                    .font(.caption).foregroundColor(ZDDesign.pureWhite)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(ZDDesign.darkCard.opacity(0.92))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var navBatteryIcon: String {
        let level = appState.navState.batteryTrend
        if level > 0.75 { return "battery.100" }
        if level > 0.5  { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }

    private var navBatteryColor: Color {
        appState.navState.batteryMinutesRemaining < 30 ? Color(ZDDesign.signalRed) :
        appState.navState.batteryMinutesRemaining < 60 ? .orange : .green
    }

    private var navBaroIcon: String {
        switch weather.barometricPressureTrend {
        case .stable: return "barometer"
        case .rapidDrop: return "arrow.down.circle"
        case .rapidRise: return "arrow.up.circle"
        }
    }

    private func computeNavViewshed() async {
        guard let pos = appState.navState.position else { return }
        isComputingNavViewshed = true
        defer { isComputingNavViewshed = false }
        let points = LOSRaycastEngine.shared.computeViewshed(from: pos, radius: 2000, resolution: 36)
        await MainActor.run {
            viewshedPoints = points
        }
    }

    // MARK: - Sharing

    private func shareWaypoints() {
        let gpxData = waypointStore.exportGPX()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("waypoints_\(Int(Date().timeIntervalSince1970)).gpx")
        try? gpxData.write(to: url)
        shareURL = url
    }
}

// MARK: - Map Content Helpers

extension MapTabView {
    @MapContentBuilder
    var mapPeersContent: some MapContent {
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
        if appState.mapLayerConfig.showMeshPeers {
            ForEach(mesh.peers) { peer in
                if let loc = peer.location {
                    Annotation(peer.name, coordinate: loc) {
                        MeshPeerDot(peer: peer)
                    }
                }
            }
        }
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
    }

    @MapContentBuilder
    var mapWaypointsContent: some MapContent {
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
                    .onTapGesture { selectedWaypoint = wp }
            }
        }
        if appState.mapLayerConfig.showThreatPins {
            ForEach(tak.peers.filter { $0.type.contains("a-h") }, id: \.uid) { threat in
                Annotation("Threat", coordinate: CLLocationCoordinate2D(latitude: threat.lat, longitude: threat.lon)) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(ZDDesign.signalRed))
                        .font(.title3)
                }
            }
        }
    }

    @MapContentBuilder
    var mapOverlaysContent: some MapContent {
        if appState.mapLayerConfig.showContours {
            ForEach(Array(contourLines.enumerated()), id: \.offset) { _, contour in
                MapPolyline(coordinates: contour.coordinates)
                    .stroke(
                        Color.brown.opacity(contour.isMajor ? 0.8 : 0.4),
                        lineWidth: contour.isMajor ? 1.5 : 0.8
                    )
            }
        }
        if appState.mapLayerConfig.showBreadcrumbs && breadcrumb.trail.count >= 2 {
            MapPolyline(coordinates: breadcrumb.trail.map(\.coordinate))
                .stroke(.cyan, lineWidth: 3)
        }
        if appState.mapLayerConfig.showRangeRings, let loc = appState.currentLocation {
            ForEach([100, 250, 500, 1000, 2000], id: \.self) { radius in
                MapCircle(center: loc, radius: CLLocationDistance(radius))
                    .stroke(Color(ZDDesign.cyanAccent).opacity(0.6), lineWidth: 1.5)
            }
        }
        if appState.mapLayerConfig.showMGRS {
            ForEach(Array(cachedMGRSLines.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line)
                    .stroke(Color(ZDDesign.safetyYellow).opacity(0.5), lineWidth: 0.8)
            }
        }
    }

    @MapContentBuilder
    var mapAnalysisContent: some MapContent {
        if let result = losResult {
            ForEach(Array(result.segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: [segment.start, segment.end])
                    .stroke(segment.isVisible ? .green : .red, lineWidth: 3)
            }
        }
        ForEach(Array(viewshedPoints.enumerated()), id: \.offset) { _, point in
            Annotation("", coordinate: point.coordinate) {
                Circle()
                    .fill(point.isVisible ? Color.green.opacity(0.4) : Color.red.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
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

// MARK: - Nav Content (DR/EKF rings overlay)

extension MapTabView {
    @MapContentBuilder
    var mapNavContent: some MapContent {
        if navMode, let pos = appState.navState.position {
            Annotation("", coordinate: pos) {
                ZStack {
                    if deadReckoning.isActive {
                        Circle()
                            .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                            .frame(
                                width: CGFloat(max(24, deadReckoning.confidenceRadius)),
                                height: CGFloat(max(24, deadReckoning.confidenceRadius))
                            )
                    }
                    Circle()
                        .fill(Color.cyan.opacity(0.25))
                        .frame(
                            width: CGFloat(max(14, appState.navState.ekfUncertainty)),
                            height: CGFloat(max(14, appState.navState.ekfUncertainty))
                        )
                }
            }
        }
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

// MARK: - Navigation HUD

private struct NavigationHUD: View {
    @ObservedObject var breadcrumb: BreadcrumbEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // GPS status
            HStack(spacing: 4) {
                Circle()
                    .fill(gpsColor)
                    .frame(width: 6, height: 6)
                Text(breadcrumb.gpsStatus.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(gpsColor)
            }

            // MGRS position
            if let pos = breadcrumb.currentPosition {
                Text(MGRSConverter.toMGRS(coordinate: pos, precision: 4))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Elevation
            if let pos = breadcrumb.currentPosition,
               let elev = TerrainEngine.shared.elevationAt(coordinate: pos) {
                Text("\(Int(elev))m / \(Int(elev * 3.28084))ft")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Speed + heading
            HStack(spacing: 8) {
                Text(String(format: "%.1f m/s", breadcrumb.speedMps))
                    .font(.system(size: 9, design: .monospaced))
                Text(String(format: "HDG %03.0f°", breadcrumb.heading))
                    .font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(.secondary)

            // GPS accuracy
            Text("±\(Int(breadcrumb.lastGPSAccuracy))m")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(breadcrumb.lastGPSAccuracy > 30 ? ZDDesign.signalRed :
                                breadcrumb.lastGPSAccuracy > 10 ? ZDDesign.safetyYellow : .secondary)
        }
        .padding(8)
        .background(Color.black.opacity(0.75))
        .cornerRadius(8)
    }

    private var gpsColor: Color {
        switch breadcrumb.gpsStatus {
        case .good:     return ZDDesign.successGreen
        case .degraded: return ZDDesign.safetyYellow
        case .denied:   return ZDDesign.signalRed
        }
    }

}

// MARK: - Waypoint Detail Sheet

private struct WaypointDetailSheet: View {
    let waypoint: TacticalWaypoint
    @ObservedObject var store: TacticalWaypointStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("Location") {
                    LabeledContent("MGRS") {
                        Text(MGRSConverter.toMGRS(coordinate: waypoint.coordinate, precision: 5))
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Lat / Lon") {
                        Text(String(format: "%.5f, %.5f", waypoint.lat, waypoint.lon))
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                Section("Details") {
                    LabeledContent("Type", value: waypoint.type.rawValue.capitalized)
                    if !waypoint.publicDescription.isEmpty {
                        LabeledContent("Description", value: waypoint.publicDescription)
                    }
                    if !waypoint.tacticalNotes.isEmpty {
                        LabeledContent("Notes", value: waypoint.tacticalNotes)
                    }
                    LabeledContent("Created by", value: waypoint.createdBy)
                    LabeledContent("Created") {
                        Text(waypoint.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Waypoint", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(waypoint.displayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete \"\(waypoint.displayLabel)\"?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    store.remove(id: waypoint.id)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    MapTabView()
        .environmentObject(AppState.shared)
}
