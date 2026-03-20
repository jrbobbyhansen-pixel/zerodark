// Terrain3DView.swift — 3D Terrain Visualization with Tactical Overlays

import SwiftUI
import SceneKit
import MapKit

struct Terrain3DView: View {
    let region: MKCoordinateRegion
    let waypoints: [TacticalWaypoint]
    @Environment(\.dismiss) var dismiss
    @State private var scene: SCNScene?
    @State private var exaggeration: Float = 1.5
    @State private var noData = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let scene = scene {
                    SceneView(
                        scene: scene,
                        options: [.allowsCameraControl, .autoenablesDefaultLighting]
                    )
                    .ignoresSafeArea()
                } else if noData {
                    noDataView
                } else {
                    ProgressView("Generating terrain…")
                        .foregroundColor(.white)
                }

                // Controls overlay
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text("Exaggeration")
                            .font(.caption)
                            .foregroundColor(.white)
                        Slider(value: $exaggeration, in: 1.0...5.0)
                            .frame(width: 150)
                        Text(String(format: "%.1fx", exaggeration))
                            .font(.caption)
                            .foregroundColor(.white)
                            .frame(width: 40)
                    }
                    .padding()
                    .background(ZDDesign.darkCard.opacity(0.8))
                    .cornerRadius(8)
                    .padding()
                }
            }
            .navigationTitle("3D Terrain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { buildScene() }
            .onChange(of: exaggeration) { buildScene() }
        }
    }

    @ViewBuilder
    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mountain.2")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No SRTM data for this area")
                .foregroundColor(.secondary)
            Text("Copy .hgt files to ZeroDark/SRTM/ in Files app")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private func buildScene() {
        scene = nil
        noData = false

        Task {
            // Generate elevation grid on background thread
            let grid = await Task(priority: .userInitiated) {
                TerrainMeshGenerator.elevationGrid(for: region, resolution: 150)
            }.value

            // Check if we have data
            let allZero = grid.allSatisfy { row in row.allSatisfy { $0 == 0 } }
            if allZero {
                await MainActor.run {
                    self.noData = true
                }
                return
            }

            // Build geometry
            let geometry = TerrainMeshGenerator.buildGeometry(grid: grid, exaggeration: exaggeration)

            // Create scene on main thread
            await MainActor.run {
                let newScene = SCNScene()
                let terrainNode = SCNNode(geometry: geometry)
                newScene.rootNode.addChildNode(terrainNode)

                // Add camera
                let cameraNode = SCNNode()
                cameraNode.camera = SCNCamera()
                cameraNode.position = SCNVector3(0, 60, 90)
                cameraNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
                newScene.rootNode.addChildNode(cameraNode)

                // Add ambient light
                let ambientLight = SCNNode()
                ambientLight.light = SCNLight()
                ambientLight.light?.type = .ambient
                ambientLight.light?.intensity = 500
                newScene.rootNode.addChildNode(ambientLight)

                // Add directional light (sun)
                let sunLight = SCNNode()
                sunLight.light = SCNLight()
                sunLight.light?.type = .directional
                sunLight.light?.intensity = 1000
                sunLight.position = SCNVector3(50, 100, 50)
                sunLight.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
                newScene.rootNode.addChildNode(sunLight)

                // Add waypoint pins
                addWaypointPins(to: newScene, grid: grid)

                self.scene = newScene
            }
        }
    }

    private func addWaypointPins(to scene: SCNScene, grid: [[Double]]) {
        let engine = TerrainEngine.shared

        // Find elevation range for Y scaling
        let allElevations = grid.flatMap { $0 }
        let minElev = Float(allElevations.min() ?? 0)
        let maxElev = Float(allElevations.max() ?? 1000)
        let elevRange = max(maxElev - minElev, 1.0)

        for waypoint in waypoints {
            // Get terrain elevation at waypoint
            let terrainElev = engine.elevationAt(coordinate: waypoint.coordinate) ?? 0

            // Calculate offset from region center
            let latOffset = waypoint.coordinate.latitude - region.center.latitude
            let lonOffset = waypoint.coordinate.longitude - region.center.longitude

            // Convert to scene coordinates
            let x = Float(lonOffset / region.span.longitudeDelta * 100.0)
            let z = Float(-latOffset / region.span.latitudeDelta * 100.0)  // negative because map is inverted
            let y = (Float(terrainElev) - minElev) / elevRange * 10.0 * exaggeration + 2.0  // +2 to sit above terrain

            // Create cone pin
            let cone = SCNCone(topRadius: 0, bottomRadius: 0.4, height: 1.5)
            cone.firstMaterial?.diffuse.contents = UIColor.systemOrange

            let pinNode = SCNNode(geometry: cone)
            pinNode.position = SCNVector3(x, y, z)
            scene.rootNode.addChildNode(pinNode)

            // Add label text above pin
            let textGeometry = SCNText(string: waypoint.displayLabel, extrusionDepth: 0.1)
            textGeometry.font = UIFont.systemFont(ofSize: 2, weight: .semibold)
            textGeometry.firstMaterial?.diffuse.contents = UIColor.white

            let textNode = SCNNode(geometry: textGeometry)
            textNode.position = SCNVector3(x, y + 2.0, z)
            textNode.scale = SCNVector3(0.1, 0.1, 0.1)
            scene.rootNode.addChildNode(textNode)
        }
    }
}

#Preview {
    let mockRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30.267, longitude: -97.743),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    Terrain3DView(region: mockRegion, waypoints: [])
}
