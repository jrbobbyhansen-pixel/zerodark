// ScanGalleryView.swift — LiDAR Scan History with 3D Viewer (Phase 15)

import SwiftUI
import SceneKit

struct ScanGalleryView: View {
    @StateObject private var storage = ScanStorage.shared
    @Environment(\.dismiss) var dismiss: DismissAction
    @State private var scanToAlert: SavedScan?
    @State private var showBrokenAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if storage.savedScans.isEmpty {
                    VStack {
                        Image(systemName: "cube.fill")
                            .font(.largeTitle)
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("No scans yet")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(storage.savedScans) { scan in
                        if scan.hasUSDZ {
                            NavigationLink(destination: scanDetailView(scan)) {
                                ScanRow(scan: scan)
                            }
                        } else {
                            ScanRow(scan: scan).onTapGesture {
                                scanToAlert = scan
                                showBrokenAlert = true
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Scan Incomplete", isPresented: $showBrokenAlert, presenting: scanToAlert) { s in
                Button("Delete", role: .destructive) { storage.deleteScan(s) }
                Button("OK", role: .cancel) {}
            } message: { _ in
                Text("3D model export failed. Point data saved but cannot be viewed. Delete and rescan?")
            }
        }
    }

    @ViewBuilder
    private func scanDetailView(_ scan: SavedScan) -> some View {
        ScanDetailView(scan: scan)
    }
}

// MARK: - Scan Row

struct ScanRow: View {
    let scan: SavedScan

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or placeholder
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.2))
                if let img = loadThumbnail() {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "cube.transparent").foregroundColor(.gray)
                }
            }
            .frame(width: 60, height: 60).cornerRadius(8).clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(scan.name.isEmpty ? defaultName : scan.name)
                    .font(.headline).lineLimit(1)
                HStack(spacing: 8) {
                    Text(formatPointCount(scan.pointCount))
                        .font(.caption).foregroundColor(ZDDesign.mediumGray)
                    Text("•").foregroundColor(ZDDesign.mediumGray)
                    Text(scan.timestamp.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundColor(ZDDesign.mediumGray)
                }
            }
            Spacer()
            statusBadge
            Image(systemName: "chevron.right").font(.caption).foregroundColor(ZDDesign.mediumGray)
        }
        .padding(.vertical, 4)
    }

    var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: scan.hasUSDZ ? "cube.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(scan.hasUSDZ ? ZDDesign.cyanAccent : .orange)
            Text(scan.hasUSDZ ? "3D" : "No model")
                .font(.caption2.bold())
                .foregroundColor(scan.hasUSDZ ? ZDDesign.cyanAccent : .orange)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.gray.opacity(0.15)).cornerRadius(6)
    }

    var defaultName: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return "Scan \(f.string(from: scan.timestamp))"
    }

    func formatPointCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM pts", Double(n)/1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK pts", Double(n)/1_000) }
        return "\(n) pts"
    }

    func loadThumbnail() -> UIImage? {
        guard let data = try? Data(contentsOf: scan.scanDir.appendingPathComponent("thumbnail.jpg")) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Scan Detail View with Editing

struct ScanDetailView: View {
    let scan: SavedScan
    @State private var scanName: String = ""
    @State private var isEditingName = false
    @State private var showMetadata = false
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Editable name field - compact
                HStack {
                    if isEditingName {
                        TextField("Scan name", text: $scanName)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .onSubmit { saveName() }
                    } else {
                        Text(scanName.isEmpty ? "Unnamed Scan" : scanName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(scanName.isEmpty ? .secondary : .primary)
                    }
                    Spacer()
                    Button {
                        if isEditingName { saveName() }
                        isEditingName.toggle()
                    } label: {
                        Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil.circle")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // 3D Preview - takes all available space
                if scan.hasUSDZ {
                    Scan3DView(usdzURL: scan.usdzURL, scanDir: scan.scanDir)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.largeTitle)
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("3D model not available")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }

                // Compact metadata bar
                metadataBar
            }
        }
        .background(Color.black)
        .navigationTitle("Scan Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { scanName = scan.name }
    }
    
    private var metadataBar: some View {
        HStack(spacing: 16) {
            // Points
            Label(formatPoints(scan.pointCount), systemImage: "cube.fill")
                .font(.caption2)
                .foregroundColor(ZDDesign.mediumGray)
            
            // Location
            if let coords = scan.coordinateString {
                Label(coords, systemImage: "location.fill")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.cyanAccent)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Threat level badge
            if let risk = scan.riskScore {
                Text(risk < 0.3 ? "LOW" : risk < 0.7 ? "ELEVATED" : "HIGH")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(risk < 0.3 ? ZDDesign.successGreen.opacity(0.2) : risk < 0.7 ? ZDDesign.safetyYellow.opacity(0.2) : ZDDesign.signalRed.opacity(0.2))
                    .foregroundColor(risk < 0.3 ? ZDDesign.successGreen : risk < 0.7 ? ZDDesign.safetyYellow : ZDDesign.signalRed)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
    }
    
    private func formatPoints(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n)/1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n)/1_000) }
        return "\(n)"
    }
    
    private func saveName() {
        ScanStorage.shared.updateScanName(scan, newName: scanName)
    }
}

// MARK: - Tactical 3D Scene Viewer (Mil-Spec)

enum TacticalViewMode: String, CaseIterable {
    case solid = "Solid"
    case wireframe = "Wire"
    case topDown = "Plan"
}

struct Scan3DView: View {
    let usdzURL: URL
    let scanDir: URL
    @State private var viewMode: TacticalViewMode = .solid
    @StateObject private var measurementManager = MeasurementManager()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Mode selector
                Picker("View", selection: $viewMode) {
                    ForEach(TacticalViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // 3D View with measurements
                TacticalSceneView(
                    usdzURL: usdzURL,
                    mode: viewMode,
                    measurementManager: measurementManager
                )
            }

            // Measurement overlay
            MeasurementOverlayView(manager: measurementManager)
        }
        .background(Color.black)
        .onAppear {
            measurementManager.loadAnnotations(for: scanDir)
        }
    }
}

struct TacticalSceneView: UIViewRepresentable {
    let usdzURL: URL
    let mode: TacticalViewMode
    @ObservedObject var measurementManager: MeasurementManager

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.showsStatistics = false
        scnView.autoenablesDefaultLighting = false

        // Add tap gesture for measurements
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        if let scene = try? SCNScene(url: usdzURL) {
            // Professional 3-point lighting setup
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = UIColor(white: 0.15, alpha: 1.0)
            ambientLight.light?.intensity = 300
            scene.rootNode.addChildNode(ambientLight)

            // Key light (main)
            let keyLight = SCNNode()
            keyLight.light = SCNLight()
            keyLight.light?.type = .directional
            keyLight.light?.color = UIColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1.0)
            keyLight.light?.intensity = 1200
            keyLight.light?.castsShadow = true
            keyLight.light?.shadowMode = .deferred
            keyLight.light?.shadowSampleCount = 8
            keyLight.position = SCNVector3(5, 10, 8)
            keyLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(keyLight)
            
            // Fill light (softer, opposite side)
            let fillLight = SCNNode()
            fillLight.light = SCNLight()
            fillLight.light?.type = .directional
            fillLight.light?.color = UIColor(red: 0.1, green: 0.6, blue: 0.8, alpha: 1.0)
            fillLight.light?.intensity = 400
            fillLight.position = SCNVector3(-8, 5, 5)
            fillLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(fillLight)
            
            // Rim light (edge highlighting)
            let rimLight = SCNNode()
            rimLight.light = SCNLight()
            rimLight.light?.type = .directional
            rimLight.light?.color = UIColor(red: 0.0, green: 1.0, blue: 0.6, alpha: 1.0)
            rimLight.light?.intensity = 600
            rimLight.position = SCNVector3(0, 3, -10)
            rimLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(rimLight)

            // Apply high-quality PBR materials
            scene.rootNode.enumerateChildNodes { node, _ in
                if let geometry = node.geometry {
                    let material = SCNMaterial()
                    material.lightingModel = .physicallyBased
                    material.diffuse.contents = UIColor(red: 0.08, green: 0.35, blue: 0.15, alpha: 1.0)
                    material.metalness.contents = 0.1
                    material.roughness.contents = 0.6
                    material.emission.contents = UIColor(red: 0.0, green: 0.08, blue: 0.03, alpha: 1.0)
                    material.isDoubleSided = true
                    geometry.materials = [material]
                }
            }

            // Subtle grid floor
            let gridGeometry = SCNFloor()
            gridGeometry.reflectivity = 0.05
            let gridMaterial = SCNMaterial()
            gridMaterial.diffuse.contents = UIColor(red: 0.02, green: 0.08, blue: 0.04, alpha: 0.5)
            gridMaterial.isDoubleSided = true
            gridGeometry.materials = [gridMaterial]
            let gridNode = SCNNode(geometry: gridGeometry)
            gridNode.position = SCNVector3(0, -0.01, 0)
            scene.rootNode.addChildNode(gridNode)

            // Create measurement visualization node
            let measurementNode = SCNNode()
            measurementNode.name = "measurementOverlay"
            scene.rootNode.addChildNode(measurementNode)

            scnView.scene = scene
            context.coordinator.scene = scene
            context.coordinator.scnView = scnView
            context.coordinator.measurementNode = measurementNode
            context.coordinator.measurementManager = measurementManager
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = context.coordinator.scene else { return }

        // Apply view mode
        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.name != "measurementOverlay",
                  node.name != "measurementPoint",
                  node.name != "measurementLine",
                  let geometry = node.geometry else { return }

            switch mode {
            case .wireframe:
                let wireMaterial = SCNMaterial()
                wireMaterial.fillMode = .lines
                wireMaterial.diffuse.contents = UIColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 1.0)
                wireMaterial.emission.contents = UIColor(red: 0.0, green: 0.4, blue: 0.2, alpha: 1.0)
                wireMaterial.isDoubleSided = true
                geometry.materials = [wireMaterial]

            case .solid:
                let material = SCNMaterial()
                material.lightingModel = .physicallyBased
                material.diffuse.contents = UIColor(red: 0.08, green: 0.35, blue: 0.15, alpha: 1.0)
                material.metalness.contents = 0.1
                material.roughness.contents = 0.6
                material.emission.contents = UIColor(red: 0.0, green: 0.08, blue: 0.03, alpha: 1.0)
                material.isDoubleSided = true
                geometry.materials = [material]

            case .topDown:
                let material = SCNMaterial()
                material.lightingModel = .physicallyBased
                material.diffuse.contents = UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1.0)
                material.metalness.contents = 0.0
                material.roughness.contents = 0.8
                material.isDoubleSided = true
                geometry.materials = [material]
            }
        }

        // Top-down orthographic view
        if mode == .topDown {
            uiView.pointOfView?.camera?.usesOrthographicProjection = true
            uiView.pointOfView?.camera?.orthographicScale = 5
            uiView.pointOfView?.position = SCNVector3(0, 10, 0)
            uiView.pointOfView?.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
        } else {
            uiView.pointOfView?.camera?.usesOrthographicProjection = false
        }

        // Update measurement visualization
        context.coordinator.updateMeasurementVisualization()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: TacticalSceneView
        var scene: SCNScene?
        var scnView: SCNView?
        var measurementNode: SCNNode?
        var measurementManager: MeasurementManager?

        init(_ parent: TacticalSceneView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }

            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: false
            ])

            // Find first hit on mesh geometry
            if let hit = hitResults.first(where: {
                $0.node.name != "measurementPoint" &&
                $0.node.name != "measurementLine" &&
                $0.node.name != "measurementOverlay"
            }) {
                let worldPos = hit.worldCoordinates
                let point = SIMD3<Float>(Float(worldPos.x), Float(worldPos.y), Float(worldPos.z))

                Task { @MainActor in
                    guard let measurementManager = self.measurementManager,
                          measurementManager.isActive else { return }
                    measurementManager.addPoint(point)
                    self.updateMeasurementVisualization()
                }

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }

        @MainActor
        func updateMeasurementVisualization() {
            guard let measurementNode = measurementNode,
                  let measurementManager = measurementManager else { return }

            // Clear existing visualization
            measurementNode.childNodes.forEach { $0.removeFromParentNode() }

            // Draw current measurement points
            for point in measurementManager.currentPoints {
                let marker = createPointMarker(at: point, color: .cyan)
                measurementNode.addChildNode(marker)
            }

            // Draw lines between current points
            if measurementManager.currentPoints.count >= 2 {
                for i in 0..<(measurementManager.currentPoints.count - 1) {
                    let line = createLine(
                        from: measurementManager.currentPoints[i],
                        to: measurementManager.currentPoints[i + 1],
                        color: .cyan
                    )
                    measurementNode.addChildNode(line)
                }

                // Close polygon for area
                if measurementManager.currentType == .area && measurementManager.currentPoints.count >= 3 {
                    guard let lastPt = measurementManager.currentPoints.last,
                          let firstPt = measurementManager.currentPoints.first else { return }
                    let closingLine = createLine(
                        from: lastPt,
                        to: firstPt,
                        color: .cyan.withAlphaComponent(0.5)
                    )
                    measurementNode.addChildNode(closingLine)
                }
            }

            // Draw saved measurements
            for annotation in measurementManager.annotations.measurements {
                let color = UIColor(red: 0, green: 0.8, blue: 0.4, alpha: 0.8)  // Saved = green

                // Points
                for codablePoint in annotation.points {
                    let marker = createPointMarker(at: codablePoint.simd, color: color, radius: 0.03)
                    measurementNode.addChildNode(marker)
                }

                // Lines
                if annotation.points.count >= 2 {
                    for i in 0..<(annotation.points.count - 1) {
                        let line = createLine(
                            from: annotation.points[i].simd,
                            to: annotation.points[i + 1].simd,
                            color: color
                        )
                        measurementNode.addChildNode(line)
                    }

                    // Close polygon for area
                    if annotation.type == .area {
                        guard let lastPt = annotation.points.last?.simd,
                              let firstPt = annotation.points.first?.simd else { continue }
                        let closingLine = createLine(
                            from: lastPt,
                            to: firstPt,
                            color: color
                        )
                        measurementNode.addChildNode(closingLine)
                    }
                }
            }
        }

        private func createPointMarker(at position: SIMD3<Float>, color: UIColor, radius: CGFloat = 0.05) -> SCNNode {
            let sphere = SCNSphere(radius: radius)
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color.withAlphaComponent(0.5)
            sphere.materials = [material]

            let node = SCNNode(geometry: sphere)
            node.name = "measurementPoint"
            node.position = SCNVector3(position.x, position.y, position.z)
            return node
        }

        private func createLine(from start: SIMD3<Float>, to end: SIMD3<Float>, color: UIColor) -> SCNNode {
            let distance = simd_distance(start, end)
            let cylinder = SCNCylinder(radius: 0.01, height: CGFloat(distance))

            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color.withAlphaComponent(0.3)
            cylinder.materials = [material]

            let node = SCNNode(geometry: cylinder)
            node.name = "measurementLine"

            // Position at midpoint
            let midpoint = (start + end) / 2
            node.position = SCNVector3(midpoint.x, midpoint.y, midpoint.z)

            // Rotate to align with line direction
            let direction = normalize(end - start)
            let up = SIMD3<Float>(0, 1, 0)

            if abs(dot(direction, up)) < 0.999 {
                let axis = cross(up, direction)
                let angle = acos(dot(up, direction))
                node.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
            }

            return node
        }
    }
}

#Preview {
    ScanGalleryView()
}
