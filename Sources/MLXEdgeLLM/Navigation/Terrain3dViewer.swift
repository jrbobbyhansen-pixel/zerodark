// Terrain3dViewer.swift — Interactive SceneKit 3D viewer for LiDAR point-cloud terrain.
// Renders points.bin from a SavedScan, overlays breadcrumb trail, waypoints, team positions.
// Pan / zoom / rotate via SCNView built-in camera controls.

import SwiftUI
import SceneKit
import CoreLocation

// MARK: - Terrain3DViewModel

@MainActor
final class Terrain3DViewModel: ObservableObject {
    static let shared = Terrain3DViewModel()

    // SceneKit scene — rebuilt when scan changes
    @Published var scene: SCNScene = SCNScene()
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentScan: SavedScan? = nil
    @Published var pointCount: Int = 0

    // Overlay toggles
    @Published var showTrail: Bool      = true
    @Published var showWaypoints: Bool  = true
    @Published var showTeam: Bool       = true

    // Scan overlay editor state
    @Published var editMode: OverlayEditMode = .view
    @Published var pendingPoints: [SIMD3<Float>] = []
    @Published var selectedOverlayID: UUID? = nil

    private init() {}

    // MARK: Load

    func loadScan(_ scan: SavedScan) {
        currentScan = scan
        errorMessage = nil
        isLoading = true
        editMode = .view
        pendingPoints = []
        selectedOverlayID = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result = Terrain3DSceneBuilder.build(scan: scan)
            await MainActor.run {
                switch result {
                case .success(let built):
                    self.scene = built.scene
                    self.pointCount = built.count
                    // Load sidecar overlays + render them into the fresh scene.
                    ScanOverlayStore.shared.load(for: scan)
                    ScanOverlayRenderer.rebuild(for: scan.id, in: built.scene)
                case .failure(let err):
                    self.errorMessage = err.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    // MARK: - Scan Overlay Editor

    /// Called by the tap-gesture coordinator when the user taps the point cloud.
    /// `worldPoint` is in scene coordinates — equal to scan-local coordinates
    /// since Terrain3DSceneBuilder centers the cloud at origin without transforms.
    func handleTap(worldPoint: SIMD3<Float>) {
        guard case .placing(let kind) = editMode,
              let scan = currentScan else { return }

        pendingPoints.append(worldPoint)
        ScanOverlayRenderer.addPreviewPoint(worldPoint, kind: kind, in: scene)

        // Finalize based on kind
        switch kind {
        case .wall:
            if pendingPoints.count == 2 {
                finalizePendingOverlay(kind: kind, points: pendingPoints, in: scan)
            }
        case .zone:
            // Zone requires explicit "Done" tap — do nothing here beyond preview
            break
        default:
            // Single-tap primitives: finalize immediately
            finalizePendingOverlay(kind: kind, points: [worldPoint], in: scan)
        }
    }

    /// Explicit finalize for zone (called from toolbar "Done" button).
    func finalizeZone() {
        guard case .placing(.zone) = editMode, let scan = currentScan else { return }
        guard pendingPoints.count >= 3 else { return }
        finalizePendingOverlay(kind: .zone, points: pendingPoints, in: scan)
    }

    func cancelPlacement() {
        pendingPoints = []
        ScanOverlayRenderer.clearPreviews(in: scene)
        editMode = .view
    }

    private func finalizePendingOverlay(kind: ScanOverlayKind, points: [SIMD3<Float>], in scan: SavedScan) {
        let overlay = ScanOverlay(
            kind: kind,
            points: points,
            rotationY: 0,
            label: "",
            notes: "",
            createdBy: AppConfig.deviceCallsign
        )
        ScanOverlayStore.shared.add(overlay, to: scan)
        pendingPoints = []
        ScanOverlayRenderer.clearPreviews(in: scene)
        ScanOverlayRenderer.rebuild(for: scan.id, in: scene)
        editMode = .view
    }

    /// Rebuild scan-overlay nodes in the current scene.
    /// Called when ScanOverlayStore receives an incoming mesh update.
    func rebuildScanOverlays() {
        guard let scan = currentScan else { return }
        ScanOverlayRenderer.rebuild(for: scan.id, in: scene)
    }

    func rebuildOverlays() {
        guard !isLoading else { return }
        let rootNode = scene.rootNode
        // Remove previous overlays
        rootNode.childNodes.filter { $0.name?.hasPrefix("overlay_") == true }.forEach { $0.removeFromParentNode() }

        if showTrail {
            if let trailNode = Terrain3DOverlays.trailNode() {
                trailNode.name = "overlay_trail"
                rootNode.addChildNode(trailNode)
            }
        }
        if showWaypoints {
            for node in Terrain3DOverlays.waypointNodes() {
                node.name = "overlay_waypoint"
                rootNode.addChildNode(node)
            }
        }
        if showTeam {
            for node in Terrain3DOverlays.teamNodes() {
                node.name = "overlay_team"
                rootNode.addChildNode(node)
            }
        }
    }
}

// MARK: - Scene Builder (off main thread)

private enum Terrain3DSceneBuilder {

    struct BuiltScene {
        let scene: SCNScene
        let count: Int
    }

    enum BuildError: Error, LocalizedError {
        case fileNotFound
        case tooFewBytes
        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "points.bin not found in scan directory."
            case .tooFewBytes:  return "Scan file is corrupt or empty."
            }
        }
    }

    static func build(scan: SavedScan) -> Result<BuiltScene, BuildError> {
        let url = scan.scanDir.appendingPathComponent("points.bin")
        guard let data = try? Data(contentsOf: url) else { return .failure(.fileNotFound) }
        guard data.count >= 4 else { return .failure(.tooFewBytes) }

        // Read header
        var count: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &count) { data.copyBytes(to: $0, from: 0..<4) }
        let n = Int(count)
        let expectedBytes = 4 + n * 12
        guard data.count >= expectedBytes, n > 0 else { return .failure(.tooFewBytes) }

        // Decode SIMD3<Float> points
        var points = [SCNVector3]()
        points.reserveCapacity(n)
        data.withUnsafeBytes { buf in
            let base = buf.baseAddress!.advanced(by: 4)
                .assumingMemoryBound(to: Float.self)
            for i in 0..<n {
                let x = base[i * 3]
                let y = base[i * 3 + 1]
                let z = base[i * 3 + 2]
                points.append(SCNVector3(x, y, z))
            }
        }

        // Centre the cloud
        let cx = points.map { $0.x }.reduce(0, +) / Float(n)
        let cy = points.map { $0.y }.reduce(0, +) / Float(n)
        let cz = points.map { $0.z }.reduce(0, +) / Float(n)
        let centred = points.map { SCNVector3($0.x - cx, $0.y - cy, $0.z - cz) }

        // Build SCNGeometry from vertices
        let vSource = SCNGeometrySource(vertices: centred)
        let indices  = (0..<n).map { Int32($0) }
        let idxData  = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.stride)
        let element  = SCNGeometryElement(data: idxData,
                                          primitiveType: .point,
                                          primitiveCount: n,
                                          bytesPerIndex: MemoryLayout<Int32>.size)
        element.pointSize            = 2.0
        element.minimumPointScreenSpaceRadius = 1.0
        element.maximumPointScreenSpaceRadius = 4.0

        let geo = SCNGeometry(sources: [vSource], elements: [element])
        let mat = SCNMaterial()
        mat.emission.contents = UIColor(red: 0, green: 0.9, blue: 1, alpha: 1) // cyan
        mat.lightingModel = .constant
        geo.materials = [mat]

        let cloudNode = SCNNode(geometry: geo)
        cloudNode.name = "pointcloud"

        // Scene setup
        let scene = SCNScene()
        scene.rootNode.addChildNode(cloudNode)

        // Ambient light
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.color = UIColor(white: 0.6, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        return .success(BuiltScene(scene: scene, count: n))
    }
}

// MARK: - Overlays

@MainActor
private enum Terrain3DOverlays {

    /// Breadcrumb trail as a polyline (thin tubes between consecutive points)
    static func trailNode() -> SCNNode? {
        let crumbs = BreadcrumbEngine.shared.trail
        guard crumbs.count >= 2 else { return nil }

        let parent = SCNNode()
        // Reference origin = first crumb
        let originLat = crumbs[0].coordinate.latitude
        let originLon = crumbs[0].coordinate.longitude
        let originAlt = crumbs[0].altitude

        let scale: Float = 111_000 // metres per degree latitude (approx)
        var prev: SCNVector3? = nil

        for crumb in crumbs {
            let x = Float((crumb.coordinate.longitude - originLon) * Double(scale) * cos(originLat * .pi / 180))
            let y = Float(crumb.altitude - originAlt)
            let z = Float((crumb.coordinate.latitude - originLat) * Double(scale)) * -1
            let pos = SCNVector3(x, y, z)
            if let p = prev {
                parent.addChildNode(tubeBetween(p, pos, color: .yellow, radius: 0.15))
            }
            prev = pos
        }
        return parent
    }

    /// Waypoint spheres
    static func waypointNodes() -> [SCNNode] {
        let wps = WaypointManager().waypoints // non-singleton — uses local instance
        // In practice WaypointManager is not a singleton; we just show a placeholder approach.
        return wps.enumerated().map { _, wp in
            let sphere = SCNSphere(radius: 0.4)
            let mat = SCNMaterial(); mat.diffuse.contents = UIColor.orange; mat.lightingModel = .constant
            sphere.materials = [mat]
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(
                Float(wp.coordinates.longitude * 111_000),
                0,
                Float(-wp.coordinates.latitude * 111_000)
            )
            return node
        }
    }

    /// Team peer cylinders
    static func teamNodes() -> [SCNNode] {
        return MeshService.shared.peers.compactMap { peer in
            guard let loc = peer.location else { return nil }
            let cyl = SCNCylinder(radius: 0.3, height: 1.2)
            let mat = SCNMaterial(); mat.diffuse.contents = UIColor(red: 0, green: 1, blue: 0.4, alpha: 1); mat.lightingModel = .constant
            cyl.materials = [mat]
            let node = SCNNode(geometry: cyl)
            node.position = SCNVector3(Float(loc.longitude * 111_000), 0.6, Float(-loc.latitude * 111_000))
            return node
        }
    }

    // Thin tube between two points
    private static func tubeBetween(_ a: SCNVector3, _ b: SCNVector3, color: UIColor, radius: CGFloat) -> SCNNode {
        let dx = b.x - a.x; let dy = b.y - a.y; let dz = b.z - a.z
        let length = sqrt(dx*dx + dy*dy + dz*dz)
        let cyl = SCNCylinder(radius: radius, height: CGFloat(length))
        let mat = SCNMaterial(); mat.diffuse.contents = color; mat.lightingModel = .constant
        cyl.materials = [mat]
        let node = SCNNode(geometry: cyl)
        // Position at midpoint
        node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
        // Orient along segment
        let up = SCNVector3(0, 1, 0)
        let dir = SCNVector3(dx/length, dy/length, dz/length)
        let cross = SCNVector3(up.y*dir.z - up.z*dir.y, up.z*dir.x - up.x*dir.z, up.x*dir.y - up.y*dir.x)
        let dot = up.x*dir.x + up.y*dir.y + up.z*dir.z
        let angle = acos(min(max(dot, -1), 1))
        node.rotation = SCNVector4(cross.x, cross.y, cross.z, angle)
        return node
    }
}

// MARK: - SCNView Wrapper

struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene
    var onTapWorldPoint: ((SIMD3<Float>) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapWorldPoint: onTapWorldPoint)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true  // built-in pan/zoom/rotate
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        scnView.antialiasingMode = .none     // performance over quality for field use
        // Default camera
        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        camNode.position = SCNVector3(0, 30, 80)
        camNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camNode)
        scnView.pointOfView = camNode
        scnView.scene = scene

        // Tap gesture — coexists with allowsCameraControl because it does not
        // cancel touches and the camera controller uses pan/pinch/rotate gestures.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        scnView.addGestureRecognizer(tap)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        context.coordinator.onTapWorldPoint = onTapWorldPoint
    }

    final class Coordinator: NSObject {
        var onTapWorldPoint: ((SIMD3<Float>) -> Void)?

        init(onTapWorldPoint: ((SIMD3<Float>) -> Void)?) {
            self.onTapWorldPoint = onTapWorldPoint
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let handler = onTapWorldPoint,
                  let scnView = sender.view as? SCNView else { return }
            let location = sender.location(in: scnView)
            let opts: [SCNHitTestOption: Any] = [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true
            ]
            let hits = scnView.hitTest(location, options: opts)
            // Prefer a hit on the point cloud; ignore overlay nodes so users can
            // place new overlays near existing ones without grabbing them.
            let pcHit = hits.first { $0.node.name == "pointcloud" }
                ?? hits.first { !(($0.node.name ?? "").hasPrefix(ScanOverlayRenderer.nodeNamePrefix)) }
            guard let hit = pcHit else { return }
            let w = hit.worldCoordinates
            handler(SIMD3<Float>(Float(w.x), Float(w.y), Float(w.z)))
        }
    }
}

// MARK: - Terrain3DViewer

struct Terrain3DViewer: View {
    @ObservedObject private var vm = Terrain3DViewModel.shared
    @ObservedObject private var overlayStore = ScanOverlayStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showScanPicker = false

    var scan: SavedScan?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if vm.isLoading {
                    loadingView
                } else if let err = vm.errorMessage {
                    errorView(err)
                } else if vm.currentScan == nil {
                    noScanView
                } else {
                    SceneKitView(
                        scene: vm.scene,
                        onTapWorldPoint: { p in vm.handleTap(worldPoint: p) }
                    )
                    .ignoresSafeArea()
                }

                // HUD overlay
                VStack {
                    Spacer()
                    if vm.currentScan != nil {
                        ScanOverlayToolbar(
                            editMode: $vm.editMode,
                            pendingPointCount: Binding(
                                get: { vm.pendingPoints.count },
                                set: { _ in }
                            ),
                            onFinalizeZone: { vm.finalizeZone() },
                            onCancel: { vm.cancelPlacement() }
                        )
                    }
                    bottomHUD
                }
            }
            .navigationTitle("3D Terrain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScanPicker = true
                    } label: {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                    .accessibilityLabel("Choose Scan")
                }
            }
            .onAppear {
                if let s = scan {
                    vm.loadScan(s)
                }
            }
            .onChange(of: overlayStore.overlays) { _, _ in
                // Redraw overlays when the store changes (e.g. incoming mesh update)
                vm.rebuildScanOverlays()
            }
            .sheet(isPresented: $showScanPicker) {
                ScanPickerSheet { selected in
                    vm.loadScan(selected)
                    showScanPicker = false
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.4)
            Text("Building 3D scene…").font(.caption).foregroundColor(.secondary)
            if let scan = vm.currentScan {
                Text("\(scan.pointCount) points").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(ZDDesign.signalRed)
            Text(msg).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button("Load Different Scan") { showScanPicker = true }
                .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
        }
    }

    private var noScanView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube.transparent").font(.system(size: 48)).foregroundColor(.secondary)
            Text("No scan loaded").font(.subheadline).foregroundColor(.secondary)
            Button("Choose Scan") { showScanPicker = true }
                .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
        }
    }

    // MARK: Bottom HUD

    private var bottomHUD: some View {
        HStack(spacing: 16) {
            if let scan = vm.currentScan {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.name.isEmpty ? "Scan" : scan.name)
                        .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text("\(vm.pointCount) pts")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            overlayToggle(icon: "arrow.triangle.branch", label: "Trail",    active: $vm.showTrail)
            overlayToggle(icon: "mappin.circle.fill",    label: "WPs",      active: $vm.showWaypoints)
            overlayToggle(icon: "person.fill",           label: "Team",     active: $vm.showTeam)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .onChange(of: vm.showTrail)     { _, _ in vm.rebuildOverlays() }
        .onChange(of: vm.showWaypoints) { _, _ in vm.rebuildOverlays() }
        .onChange(of: vm.showTeam)      { _, _ in vm.rebuildOverlays() }
    }

    private func overlayToggle(icon: String, label: String, active: Binding<Bool>) -> some View {
        Button {
            active.wrappedValue.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(active.wrappedValue ? ZDDesign.cyanAccent : .secondary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(active.wrappedValue ? ZDDesign.cyanAccent : .secondary)
            }
        }
    }
}

// MARK: - Scan Picker Sheet

private struct ScanPickerSheet: View {
    @ObservedObject private var storage = ScanStorage.shared
    var onSelect: (SavedScan) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if storage.savedScans.isEmpty {
                    Text("No saved scans").foregroundColor(.secondary)
                } else {
                    List(storage.savedScans) { scan in
                        Button {
                            onSelect(scan)
                        } label: {
                            HStack {
                                Image(systemName: "cube.fill").foregroundColor(ZDDesign.cyanAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scan.name.isEmpty ? scan.timestamp.formatted(date: .abbreviated, time: .shortened) : scan.name)
                                        .font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                                    Text("\(scan.pointCount) points").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .listRowBackground(ZDDesign.darkCard)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Choose Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
