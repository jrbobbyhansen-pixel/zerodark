# ZeroDark Module 3: Measurement Tools — Claude Code Implementation Spec

## Overview
Add measurement capabilities to the scan viewer: distance between points, polygon area, and height measurements. All measurements persist as annotations with the scan.

## Current State
- `ScanStorage.swift` handles scan persistence with metadata.json
- `ScanGalleryView.swift` has `Scan3DView` and `TacticalSceneView` for 3D rendering
- `TacticalSceneView` uses SceneKit with tactical green materials
- Point clouds stored as PLY, meshes as USDZ
- View modes: Solid, Wireframe, Plan (top-down)

## Data Model

### 1. Create: `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/MeasurementTypes.swift`

```swift
// MeasurementTypes.swift — Measurement data models

import Foundation
import simd
import SceneKit

// MARK: - Measurement Types

enum MeasurementType: String, Codable, CaseIterable {
    case distance = "Distance"
    case area = "Area"
    case height = "Height"
    
    var icon: String {
        switch self {
        case .distance: return "ruler"
        case .area: return "square.dashed"
        case .height: return "arrow.up.and.down"
        }
    }
}

enum MeasurementUnit: String, Codable, CaseIterable {
    case metric = "Metric"
    case imperial = "Imperial"
}

// MARK: - Measurement Annotation

struct MeasurementAnnotation: Identifiable, Codable {
    let id: UUID
    let type: MeasurementType
    let points: [CodableSIMD3]  // 2 points for distance/height, 3+ for area
    let timestamp: Date
    var label: String?
    
    // Computed measurement value (meters or sq meters)
    var rawValue: Float {
        switch type {
        case .distance:
            guard points.count >= 2 else { return 0 }
            return simd_distance(points[0].simd, points[1].simd)
            
        case .height:
            guard points.count >= 2 else { return 0 }
            return abs(points[1].simd.y - points[0].simd.y)
            
        case .area:
            guard points.count >= 3 else { return 0 }
            return calculatePolygonArea(points.map { $0.simd })
        }
    }
    
    // Formatted display string
    func displayValue(unit: MeasurementUnit) -> String {
        switch type {
        case .distance, .height:
            if unit == .metric {
                return String(format: "%.2f m", rawValue)
            } else {
                let feet = rawValue * 3.28084
                return String(format: "%.2f ft", feet)
            }
            
        case .area:
            if unit == .metric {
                return String(format: "%.2f m²", rawValue)
            } else {
                let sqft = rawValue * 10.7639
                return String(format: "%.2f ft²", sqft)
            }
        }
    }
    
    // Calculate polygon area using Shoelace formula (projected to XZ plane)
    private func calculatePolygonArea(_ verts: [SIMD3<Float>]) -> Float {
        guard verts.count >= 3 else { return 0 }
        
        var area: Float = 0
        let n = verts.count
        
        for i in 0..<n {
            let j = (i + 1) % n
            // Using X and Z coordinates (horizontal plane)
            area += verts[i].x * verts[j].z
            area -= verts[j].x * verts[i].z
        }
        
        return abs(area) / 2.0
    }
}

// MARK: - Codable SIMD3 wrapper

struct CodableSIMD3: Codable {
    let x: Float
    let y: Float
    let z: Float
    
    var simd: SIMD3<Float> {
        SIMD3(x, y, z)
    }
    
    init(_ simd: SIMD3<Float>) {
        self.x = simd.x
        self.y = simd.y
        self.z = simd.z
    }
    
    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - Scan Annotations Container

struct ScanAnnotations: Codable {
    var measurements: [MeasurementAnnotation]
    var lastModified: Date
    
    init() {
        self.measurements = []
        self.lastModified = Date()
    }
}
```

### 2. Create: `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/MeasurementManager.swift`

```swift
// MeasurementManager.swift — Measurement state and persistence

import Foundation
import SwiftUI
import SceneKit

@MainActor
final class MeasurementManager: ObservableObject {
    // Current measurement state
    @Published var isActive = false
    @Published var currentType: MeasurementType = .distance
    @Published var currentPoints: [SIMD3<Float>] = []
    @Published var unit: MeasurementUnit = .imperial  // Default for US
    
    // Completed measurements for current scan
    @Published var annotations: ScanAnnotations = ScanAnnotations()
    
    // Visual feedback
    @Published var lastTapPosition: SIMD3<Float>?
    
    // Reference to current scan
    private var currentScanDir: URL?
    
    // MARK: - Load/Save
    
    func loadAnnotations(for scanDir: URL) {
        currentScanDir = scanDir
        let annotationsURL = scanDir.appendingPathComponent("annotations.json")
        
        if let data = try? Data(contentsOf: annotationsURL),
           let loaded = try? JSONDecoder().decode(ScanAnnotations.self, from: data) {
            annotations = loaded
        } else {
            annotations = ScanAnnotations()
        }
    }
    
    func saveAnnotations() {
        guard let scanDir = currentScanDir else { return }
        let annotationsURL = scanDir.appendingPathComponent("annotations.json")
        
        annotations.lastModified = Date()
        
        if let data = try? JSONEncoder().encode(annotations) {
            try? data.write(to: annotationsURL)
        }
    }
    
    // MARK: - Measurement Actions
    
    func startMeasurement(type: MeasurementType) {
        isActive = true
        currentType = type
        currentPoints = []
        lastTapPosition = nil
    }
    
    func cancelMeasurement() {
        isActive = false
        currentPoints = []
        lastTapPosition = nil
    }
    
    func addPoint(_ point: SIMD3<Float>) {
        currentPoints.append(point)
        lastTapPosition = point
        
        // Auto-complete based on type
        switch currentType {
        case .distance, .height:
            if currentPoints.count >= 2 {
                completeMeasurement()
            }
            
        case .area:
            // Area needs explicit completion (3+ points)
            break
        }
    }
    
    func completeMeasurement(label: String? = nil) {
        guard canComplete else { return }
        
        let annotation = MeasurementAnnotation(
            id: UUID(),
            type: currentType,
            points: currentPoints.map { CodableSIMD3($0) },
            timestamp: Date(),
            label: label
        )
        
        annotations.measurements.append(annotation)
        saveAnnotations()
        
        // Reset for next measurement
        currentPoints = []
        lastTapPosition = nil
        // Keep isActive true for consecutive measurements
    }
    
    func deleteMeasurement(_ annotation: MeasurementAnnotation) {
        annotations.measurements.removeAll { $0.id == annotation.id }
        saveAnnotations()
    }
    
    func deleteAllMeasurements() {
        annotations.measurements.removeAll()
        saveAnnotations()
    }
    
    // MARK: - Computed Properties
    
    var canComplete: Bool {
        switch currentType {
        case .distance, .height:
            return currentPoints.count >= 2
        case .area:
            return currentPoints.count >= 3
        }
    }
    
    var currentMeasurementValue: String? {
        guard currentPoints.count >= 2 else { return nil }
        
        let tempAnnotation = MeasurementAnnotation(
            id: UUID(),
            type: currentType,
            points: currentPoints.map { CodableSIMD3($0) },
            timestamp: Date()
        )
        
        return tempAnnotation.displayValue(unit: unit)
    }
    
    var pointsNeeded: Int {
        switch currentType {
        case .distance, .height: return 2
        case .area: return 3  // Minimum
        }
    }
    
    var instructionText: String {
        guard isActive else { return "Select measurement type" }
        
        let remaining = pointsNeeded - currentPoints.count
        
        switch currentType {
        case .distance:
            if currentPoints.isEmpty {
                return "Tap first point"
            } else {
                return "Tap second point"
            }
            
        case .height:
            if currentPoints.isEmpty {
                return "Tap bottom point"
            } else {
                return "Tap top point"
            }
            
        case .area:
            if currentPoints.count < 3 {
                return "Tap point \(currentPoints.count + 1) (min 3)"
            } else {
                return "Tap more points or Done"
            }
        }
    }
}
```

### 3. Create: `Sources/MLXEdgeLLM/App/MeasurementOverlayView.swift`

```swift
// MeasurementOverlayView.swift — Measurement UI overlay for scan viewer

import SwiftUI

struct MeasurementOverlayView: View {
    @ObservedObject var manager: MeasurementManager
    @State private var showMeasurementList = false
    
    var body: some View {
        VStack {
            // Top toolbar
            HStack {
                // Measurement type picker
                if manager.isActive {
                    Picker("Type", selection: $manager.currentType) {
                        ForEach(MeasurementType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 250)
                    .onChange(of: manager.currentType) { _ in
                        manager.currentPoints = []
                    }
                }
                
                Spacer()
                
                // Unit toggle
                Button {
                    manager.unit = manager.unit == .metric ? .imperial : .metric
                } label: {
                    Text(manager.unit == .metric ? "m" : "ft")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Spacer()
            
            // Live measurement display
            if manager.isActive {
                VStack(spacing: 8) {
                    // Instruction
                    Text(manager.instructionText)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                    
                    // Current value (if measuring)
                    if let value = manager.currentMeasurementValue {
                        Text(value)
                            .font(.title2.bold().monospacedDigit())
                            .foregroundColor(ZDDesign.cyanAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                    }
                    
                    // Point indicators
                    HStack(spacing: 4) {
                        ForEach(0..<max(manager.pointsNeeded, manager.currentPoints.count), id: \.self) { i in
                            Circle()
                                .fill(i < manager.currentPoints.count ? ZDDesign.cyanAccent : Color.gray.opacity(0.5))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            
            // Bottom toolbar
            HStack(spacing: 16) {
                // Measurements list button
                Button {
                    showMeasurementList = true
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        if !manager.annotations.measurements.isEmpty {
                            Text("\(manager.annotations.measurements.count)")
                                .font(.caption.bold())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                if manager.isActive {
                    // Cancel button
                    Button {
                        manager.cancelMeasurement()
                    } label: {
                        Text("Cancel")
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(8)
                    }
                    
                    // Done button (for area)
                    if manager.currentType == .area && manager.canComplete {
                        Button {
                            manager.completeMeasurement()
                        } label: {
                            Text("Done")
                                .foregroundColor(ZDDesign.cyanAccent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                } else {
                    // Start measurement button
                    Button {
                        manager.startMeasurement(type: .distance)
                    } label: {
                        HStack {
                            Image(systemName: "ruler")
                            Text("Measure")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(ZDDesign.cyanAccent)
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showMeasurementList) {
            MeasurementListView(manager: manager)
        }
    }
}

// MARK: - Measurement List

struct MeasurementListView: View {
    @ObservedObject var manager: MeasurementManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if manager.annotations.measurements.isEmpty {
                    VStack {
                        Image(systemName: "ruler")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No measurements")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(manager.annotations.measurements) { measurement in
                            MeasurementRow(measurement: measurement, unit: manager.unit)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                manager.deleteMeasurement(manager.annotations.measurements[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !manager.annotations.measurements.isEmpty {
                        Button("Clear All", role: .destructive) {
                            manager.deleteAllMeasurements()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct MeasurementRow: View {
    let measurement: MeasurementAnnotation
    let unit: MeasurementUnit
    
    var body: some View {
        HStack {
            Image(systemName: measurement.type.icon)
                .foregroundColor(ZDDesign.cyanAccent)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.label ?? measurement.type.rawValue)
                    .font(.headline)
                Text(measurement.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(measurement.displayValue(unit: unit))
                .font(.headline.monospacedDigit())
                .foregroundColor(ZDDesign.cyanAccent)
        }
        .padding(.vertical, 4)
    }
}
```

### 4. Modify: `Sources/MLXEdgeLLM/App/ScanGalleryView.swift`

Update `TacticalSceneView` to handle tap gestures for measurements:

```swift
// Replace the existing TacticalSceneView with this updated version:

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
            
            // Apply tactical green material
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
        }
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = context.coordinator.scene else { return }
        
        // Update view mode
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
                
            case .solid, .topDown:
                let solidMaterial = SCNMaterial()
                solidMaterial.diffuse.contents = UIColor(red: 0.1, green: 0.4, blue: 0.15, alpha: 1.0)
                solidMaterial.emission.contents = UIColor(red: 0.0, green: 0.15, blue: 0.05, alpha: 1.0)
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
        
        init(_ parent: TacticalSceneView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.measurementManager.isActive,
                  let scnView = scnView else { return }
            
            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: false
            ])
            
            // Find first hit on mesh geometry (not measurement markers)
            if let hit = hitResults.first(where: { 
                $0.node.name != "measurementPoint" && 
                $0.node.name != "measurementLine" &&
                $0.node.name != "measurementOverlay"
            }) {
                let worldPos = hit.worldCoordinates
                let point = SIMD3<Float>(Float(worldPos.x), Float(worldPos.y), Float(worldPos.z))
                
                Task { @MainActor in
                    parent.measurementManager.addPoint(point)
                    updateMeasurementVisualization()
                }
                
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
        }
        
        func updateMeasurementVisualization() {
            guard let measurementNode = measurementNode else { return }
            
            // Clear existing visualization
            measurementNode.childNodes.forEach { $0.removeFromParentNode() }
            
            // Draw current measurement points
            for point in parent.measurementManager.currentPoints {
                let marker = createPointMarker(at: point, color: .cyan)
                measurementNode.addChildNode(marker)
            }
            
            // Draw lines between current points
            if parent.measurementManager.currentPoints.count >= 2 {
                for i in 0..<(parent.measurementManager.currentPoints.count - 1) {
                    let line = createLine(
                        from: parent.measurementManager.currentPoints[i],
                        to: parent.measurementManager.currentPoints[i + 1],
                        color: .cyan
                    )
                    measurementNode.addChildNode(line)
                }
                
                // Close polygon for area
                if parent.measurementManager.currentType == .area && parent.measurementManager.currentPoints.count >= 3 {
                    let closingLine = createLine(
                        from: parent.measurementManager.currentPoints.last!,
                        to: parent.measurementManager.currentPoints.first!,
                        color: .cyan.withAlphaComponent(0.5)
                    )
                    measurementNode.addChildNode(closingLine)
                }
            }
            
            // Draw saved measurements
            for annotation in parent.measurementManager.annotations.measurements {
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
```

### 5. Update: `Scan3DView` to include measurement overlay

```swift
// Replace existing Scan3DView:

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
```

### 6. Update: `ScanDetailView` to pass scanDir

```swift
// In ScanDetailView, update the Scan3DView call:

if scan.hasUSDZ {
    Scan3DView(usdzURL: scan.usdzURL, scanDir: scan.scanDir)
        .frame(height: 300)
        .cornerRadius(8)
}
```

## File Structure After Implementation

```
Sources/MLXEdgeLLM/
├── App/
│   ├── ScanGalleryView.swift (modified — TacticalSceneView, Scan3DView updated)
│   └── MeasurementOverlayView.swift (new)
└── SpatialIntelligence/
    └── LiDAR/
        ├── MeasurementTypes.swift (new)
        ├── MeasurementManager.swift (new)
        └── ScanStorage.swift (unchanged)
```

## Build Verification

After implementing:
1. Build should succeed with no errors
2. Open a saved scan → tap "Measure" button
3. Select Distance → tap two points on mesh → measurement displays
4. Select Area → tap 3+ points → tap Done → area calculated
5. Select Height → tap bottom point → tap top point → height displayed
6. Measurements appear in list and persist across app restarts
7. Toggle m/ft units works
8. Clear All removes all measurements

## Visual Design Notes

- **Current measurement points**: Cyan spheres (0.05m radius)
- **Current measurement lines**: Cyan cylinders (0.01m radius)
- **Saved measurements**: Green (0.03m radius markers)
- **Live value display**: Large cyan text on dark background
- **Instruction text**: White on semi-transparent black pill

## Edge Cases Handled

- Tap misses mesh → no point added
- Cancel mid-measurement → clears current points
- Delete measurement → removes from list and 3D view
- Load scan with no annotations.json → creates empty container
- Area with <3 points → won't complete
