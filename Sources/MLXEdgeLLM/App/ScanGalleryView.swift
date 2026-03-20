// ScanGalleryView.swift — LiDAR Scan History with 3D Viewer (Phase 15)

import SwiftUI
import SceneKit

struct ScanGalleryView: View {
    @StateObject private var storage = ScanStorage.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if storage.savedScans.isEmpty {
                    VStack {
                        Image(systemName: "cube.fill")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No scans yet")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(storage.savedScans) { scan in
                        NavigationLink(destination: scanDetailView(scan)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(scan.pointCount.formatted()) points")
                                        .font(.headline)
                                    Text(scan.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let risk = scan.riskScore {
                                        let level = risk < 0.3 ? "Low" : risk < 0.7 ? "Elevated" : "High"
                                        let color = risk < 0.3 ? ZDDesign.successGreen : risk < 0.7 ? ZDDesign.safetyYellow : ZDDesign.signalRed
                                        Text(level)
                                            .font(.caption)
                                            .foregroundColor(color)
                                    }
                                }
                                Spacer()
                                if scan.hasUSDZ {
                                    Image(systemName: scan.scanType == .reconWalk ? "figure.walk" : "cube.transparent.fill")
                                        .foregroundColor(scan.scanType == .reconWalk ? ZDDesign.safetyYellow : ZDDesign.cyanAccent)
                                }
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
        }
    }

    @ViewBuilder
    private func scanDetailView(_ scan: SavedScan) -> some View {
        ScanDetailView(scan: scan)
    }
}

// MARK: - Scan Detail View with Editing

struct ScanDetailView: View {
    let scan: SavedScan
    @State private var scanName: String = ""
    @State private var isEditingName = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Editable name field
            HStack {
                if isEditingName {
                    TextField("Scan name", text: $scanName)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .onSubmit { saveName() }
                } else {
                    Text(scanName.isEmpty ? "Unnamed Scan" : scanName)
                        .font(.headline)
                        .foregroundColor(scanName.isEmpty ? .secondary : .primary)
                }
                Spacer()
                Button {
                    if isEditingName {
                        saveName()
                    }
                    isEditingName.toggle()
                } label: {
                    Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil.circle")
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .padding(.horizontal)
            
            // 3D Preview (simplified for performance)
            if scan.hasUSDZ {
                Scan3DView(usdzURL: scan.usdzURL, scanDir: scan.scanDir)
                    .frame(height: 250)
                    .cornerRadius(8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("3D model not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            }

            // Metadata card
            VStack(alignment: .leading, spacing: 8) {
                // Points
                HStack {
                    Label("Points", systemImage: "cube.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(scan.pointCount.formatted())
                        .font(.caption.bold())
                        .monospaced()
                }
                
                Divider()
                
                // GPS Coordinates
                HStack {
                    Label("Location", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let coords = scan.coordinateString {
                        Text(coords)
                            .font(.caption.monospaced())
                            .foregroundColor(ZDDesign.cyanAccent)
                    } else {
                        Text("No GPS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Timestamp
                HStack {
                    Label("Captured", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(scan.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
                
                // Risk Score
                if let risk = scan.riskScore {
                    Divider()
                    HStack {
                        Label("Threat Level", systemImage: "exclamationmark.shield")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(risk < 0.3 ? "LOW" : risk < 0.7 ? "ELEVATED" : "HIGH")
                            .font(.caption.bold())
                            .foregroundColor(risk < 0.3 ? ZDDesign.successGreen : risk < 0.7 ? ZDDesign.safetyYellow : ZDDesign.signalRed)
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
        .navigationTitle("Scan Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scanName = scan.name
        }
    }
    
    private func saveName() {
        // Save updated name via storage manager
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
            // Add tactical lighting
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = UIColor(red: 0.0, green: 0.3, blue: 0.1, alpha: 1.0)
            ambientLight.light?.intensity = 500
            scene.rootNode.addChildNode(ambientLight)

            let directionalLight = SCNNode()
            directionalLight.light = SCNLight()
            directionalLight.light?.type = .directional
            directionalLight.light?.color = UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1.0)
            directionalLight.light?.intensity = 800
            directionalLight.position = SCNVector3(0, 10, 10)
            directionalLight.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(directionalLight)

            // Apply tactical green material to all geometry
            scene.rootNode.enumerateChildNodes { node, _ in
                if let geometry = node.geometry {
                    let tacticalMaterial = SCNMaterial()
                    tacticalMaterial.diffuse.contents = UIColor(red: 0.1, green: 0.4, blue: 0.15, alpha: 1.0)
                    tacticalMaterial.emission.contents = UIColor(red: 0.0, green: 0.15, blue: 0.05, alpha: 1.0)
                    tacticalMaterial.isDoubleSided = true
                    geometry.materials = [tacticalMaterial]
                }
            }

            // Add grid floor
            let gridGeometry = SCNFloor()
            gridGeometry.reflectivity = 0
            let gridMaterial = SCNMaterial()
            gridMaterial.diffuse.contents = UIColor(red: 0.0, green: 0.2, blue: 0.1, alpha: 0.3)
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
                wireMaterial.diffuse.contents = UIColor(red: 0.0, green: 1.0, blue: 0.4, alpha: 1.0)
                wireMaterial.isDoubleSided = true
                geometry.materials = [wireMaterial]

            case .solid:
                let solidMaterial = SCNMaterial()
                solidMaterial.diffuse.contents = UIColor(red: 0.1, green: 0.4, blue: 0.15, alpha: 1.0)
                solidMaterial.emission.contents = UIColor(red: 0.0, green: 0.15, blue: 0.05, alpha: 1.0)
                solidMaterial.isDoubleSided = true
                geometry.materials = [solidMaterial]

            case .topDown:
                let solidMaterial = SCNMaterial()
                solidMaterial.diffuse.contents = UIColor(red: 0.1, green: 0.4, blue: 0.15, alpha: 1.0)
                solidMaterial.isDoubleSided = true
                geometry.materials = [solidMaterial]
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
            guard let measurementManager = measurementManager,
                  measurementManager.isActive,
                  let scnView = scnView else { return }

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
                    let closingLine = createLine(
                        from: measurementManager.currentPoints.last!,
                        to: measurementManager.currentPoints.first!,
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
                        let closingLine = createLine(
                            from: annotation.points.last!.simd,
                            to: annotation.points.first!.simd,
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
