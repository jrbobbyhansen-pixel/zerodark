// CaveMapper.swift — Indoor/underground SLAM mapper using ARKit LiDAR.
// GPS-denied position tracking via ARFrame.camera.transform.
// Generates 2D floor plan from ARMeshGeometry. User-marks hazards & exits.

import Foundation
import SwiftUI
import ARKit
import RealityKit
import CoreLocation

// MARK: - CaveMapTypes

typealias ARTransform = simd_float4x4

enum CaveHazardType: String, CaseIterable {
    case fire       = "Fire"
    case gas        = "Gas"
    case water      = "Water"
    case collapse   = "Collapse"
    case unknown    = "Unknown"

    var icon: String {
        switch self {
        case .fire:     return "flame.fill"
        case .gas:      return "cloud.fill"
        case .water:    return "drop.fill"
        case .collapse: return "exclamationmark.triangle.fill"
        case .unknown:  return "questionmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .fire:     return ZDDesign.signalRed
        case .gas:      return .orange
        case .water:    return ZDDesign.cyanAccent
        case .collapse: return ZDDesign.safetyYellow
        case .unknown:  return .secondary
        }
    }
}

enum CaveExitType: String, CaseIterable {
    case door       = "Door"
    case staircase  = "Staircase"
    case crawlway   = "Crawlway"
    case tunnel     = "Tunnel"

    var icon: String {
        switch self {
        case .door:       return "door.left.hand.open"
        case .staircase:  return "stairs"
        case .crawlway:   return "arrow.right.circle"
        case .tunnel:     return "arrowshape.forward.fill"
        }
    }
}

struct CaveHazard: Identifiable {
    let id = UUID()
    var worldPos: SIMD3<Float>
    var type: CaveHazardType
    var note: String = ""
}

struct CaveExit: Identifiable {
    let id = UUID()
    var worldPos: SIMD3<Float>
    var type: CaveExitType
    var note: String = ""
}

struct FloorPlanCell {
    enum State: UInt8 { case unknown = 0; case open = 1; case wall = 2 }
    var state: State = .unknown
}

// MARK: - FloorPlanMap

final class FloorPlanMap {
    let cellSize: Float = 0.15      // 15 cm per cell
    let gridSize: Int   = 512       // 512 × 512 = ~76.8 m span
    private(set) var cells: [[FloorPlanCell]]
    private(set) var origin: SIMD2<Float>   // world XZ at grid (0,0)

    init(centred worldPos: SIMD3<Float>) {
        let half = Float(gridSize) * 0.15 / 2
        origin = SIMD2<Float>(worldPos.x - half, worldPos.z - half)
        cells = Array(repeating: Array(repeating: FloorPlanCell(), count: gridSize), count: gridSize)
    }

    func worldToCell(_ world: SIMD3<Float>) -> (Int, Int)? {
        let gx = Int((world.x - origin.x) / cellSize)
        let gz = Int((world.z - origin.y) / cellSize)
        guard gx >= 0, gz >= 0, gx < gridSize, gz < gridSize else { return nil }
        return (gx, gz)
    }

    func markOpen(at world: SIMD3<Float>) {
        if let (gx, gz) = worldToCell(world), cells[gz][gx].state != .wall {
            cells[gz][gx].state = .open
        }
    }

    func markWall(at world: SIMD3<Float>) {
        if let (gx, gz) = worldToCell(world) {
            cells[gz][gx].state = .wall
        }
    }
}

// MARK: - CaveMapper

@MainActor
final class CaveMapper: NSObject, ObservableObject {
    static let shared = CaveMapper()

    @Published var isSessionRunning = false
    @Published var currentTransform: simd_float4x4 = matrix_identity_float4x4
    @Published var hazards: [CaveHazard] = []
    @Published var exits: [CaveExit] = []
    @Published var trackPoints: [SIMD3<Float>] = []
    @Published var floorPlan: FloorPlanMap? = nil
    @Published var floorPlanImage: UIImage? = nil
    @Published var frameCount: Int = 0

    var arSession: ARSession = ARSession()
    private var meshUpdateCount = 0

    private override init() {
        super.init()
        arSession.delegate = self
    }

    // MARK: Session Control

    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .none
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
        floorPlan = nil
        trackPoints = []
        hazards = []
        exits = []
    }

    func stopSession() {
        arSession.pause()
        isSessionRunning = false
    }

    // MARK: Annotations

    func addHazard(type: CaveHazardType) {
        hazards.append(CaveHazard(worldPos: currentPosition, type: type))
    }

    func addExit(type: CaveExitType) {
        exits.append(CaveExit(worldPos: currentPosition, type: type))
    }

    var currentPosition: SIMD3<Float> {
        SIMD3<Float>(currentTransform.columns.3.x,
                     currentTransform.columns.3.y,
                     currentTransform.columns.3.z)
    }

    // MARK: Floor Plan Rendering

    func renderFloorPlan() {
        guard let plan = floorPlan else { return }
        let size = CGFloat(min(plan.gridSize, 512))
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Background
        ctx.setFillColor(UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let scale = size / CGFloat(plan.gridSize)

        // Cells
        for gz in 0..<plan.gridSize {
            for gx in 0..<plan.gridSize {
                let state = plan.cells[gz][gx].state
                guard state != .unknown else { continue }
                let rect = CGRect(x: CGFloat(gx)*scale, y: CGFloat(gz)*scale,
                                  width: max(1, scale), height: max(1, scale))
                ctx.setFillColor(state == .open
                    ? UIColor(white: 0.85, alpha: 1).cgColor
                    : UIColor(white: 0.18, alpha: 1).cgColor)
                ctx.fill(rect)
            }
        }

        // Track path
        if trackPoints.count >= 2 {
            ctx.setStrokeColor(UIColor.cyan.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(2)
            ctx.beginPath()
            for (i, pt) in trackPoints.enumerated() {
                guard let (gx, gz) = plan.worldToCell(pt) else { continue }
                let x = CGFloat(gx) * scale + scale/2
                let y = CGFloat(gz) * scale + scale/2
                i == 0 ? ctx.move(to: CGPoint(x: x, y: y)) : ctx.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.strokePath()
        }

        // Hazard dots
        for h in hazards {
            guard let (gx, gz) = plan.worldToCell(h.worldPos) else { continue }
            ctx.setFillColor(UIColor.red.cgColor)
            ctx.fillEllipse(in: CGRect(x: CGFloat(gx)*scale-4, y: CGFloat(gz)*scale-4, width: 9, height: 9))
        }

        // Exit dots
        for e in exits {
            guard let (gx, gz) = plan.worldToCell(e.worldPos) else { continue }
            ctx.setFillColor(UIColor.green.cgColor)
            ctx.fillEllipse(in: CGRect(x: CGFloat(gx)*scale-4, y: CGFloat(gz)*scale-4, width: 9, height: 9))
        }

        floorPlanImage = UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - ARSessionDelegate

extension CaveMapper: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentTransform = transform
            self.frameCount += 1

            let pos = self.currentPosition
            if self.trackPoints.last.map({ simd_distance(pos, $0) > 0.5 }) ?? true {
                self.trackPoints.append(pos)
                if self.floorPlan == nil {
                    self.floorPlan = FloorPlanMap(centred: pos)
                }
                self.floorPlan?.markOpen(at: pos)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        processMeshAnchors(anchors)
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        processMeshAnchors(anchors)
    }

    nonisolated private func processMeshAnchors(_ anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self, let plan = self.floorPlan else { return }
            self.meshUpdateCount += 1
            guard self.meshUpdateCount % 10 == 0 else { return }

            for anchor in meshAnchors {
                let geo = anchor.geometry
                let transform = anchor.transform
                let verts = geo.vertices
                let stride = verts.stride
                let count = verts.count
                verts.buffer.contents().withMemoryRebound(
                    to: Float.self,
                    capacity: count * stride / MemoryLayout<Float>.size
                ) { buf in
                    for i in 0..<count {
                        let base = i * stride / MemoryLayout<Float>.size
                        let local = SIMD4<Float>(buf[base], buf[base+1], buf[base+2], 1)
                        let world = transform * local
                        let wPos = SIMD3<Float>(world.x, world.y, world.z)
                        if world.y > 0.3 && world.y < 2.5 {
                            plan.markWall(at: wPos)
                        } else if world.y <= 0.3 && world.y > -0.5 {
                            plan.markOpen(at: wPos)
                        }
                    }
                }
            }
            if self.meshUpdateCount % 30 == 0 { self.renderFloorPlan() }
        }
    }
}

// MARK: - ARViewRepresentable

struct CaveARView: UIViewRepresentable {
    @ObservedObject var mapper: CaveMapper

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = mapper.arSession
        arView.debugOptions = []
        arView.renderOptions = [.disablePersonOcclusion, .disableGroundingShadows]
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - CaveMapperView

struct CaveMapperView: View {
    @ObservedObject private var mapper = CaveMapper.shared
    @Environment(\.dismiss) private var dismiss
    @State private var viewMode: ViewMode = .ar

    enum ViewMode: String { case ar = "AR Live"; case map = "Floor Plan" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("View", selection: $viewMode) {
                        Text("AR Live").tag(ViewMode.ar)
                        Text("Floor Plan").tag(ViewMode.map)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    if viewMode == .ar { arView } else { floorPlanView }
                }
            }
            .navigationTitle("Cave Mapper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { mapper.stopSession(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if mapper.isSessionRunning {
                        Button { mapper.stopSession() } label: {
                            Image(systemName: "stop.circle.fill").foregroundColor(ZDDesign.signalRed)
                        }
                    } else {
                        Button { mapper.startSession() } label: {
                            Image(systemName: "play.circle.fill").foregroundColor(ZDDesign.successGreen)
                        }
                    }
                }
            }
            .onAppear { mapper.startSession() }
            .onDisappear { mapper.stopSession() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: AR View

    private var arView: some View {
        ZStack(alignment: .bottom) {
            CaveARView(mapper: mapper)
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 0) {
                positionHUD
                Spacer()
                annotationBar
            }
        }
    }

    private var positionHUD: some View {
        HStack(spacing: 16) {
            Label("\(mapper.trackPoints.count) pts", systemImage: "location.fill")
                .font(.caption2).foregroundColor(ZDDesign.cyanAccent)
            Label("\(mapper.hazards.count)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundColor(.orange)
            Label("\(mapper.exits.count)", systemImage: "door.left.hand.open")
                .font(.caption2).foregroundColor(ZDDesign.successGreen)
            Spacer()
            if mapper.isSessionRunning {
                Circle().fill(ZDDesign.successGreen).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var annotationBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(CaveHazardType.allCases, id: \.rawValue) { t in
                    Button(t.rawValue) { mapper.addHazard(type: t) }
                }
            } label: {
                Label("Hazard", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold()).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(ZDDesign.signalRed.opacity(0.85)).cornerRadius(8)
            }
            Menu {
                ForEach(CaveExitType.allCases, id: \.rawValue) { t in
                    Button(t.rawValue) { mapper.addExit(type: t) }
                }
            } label: {
                Label("Exit", systemImage: "door.left.hand.open")
                    .font(.caption.bold()).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(ZDDesign.successGreen.opacity(0.85)).cornerRadius(8)
            }
            Button { mapper.renderFloorPlan() } label: {
                Label("Render", systemImage: "map.fill")
                    .font(.caption.bold()).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(ZDDesign.cyanAccent.opacity(0.85)).cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    // MARK: Floor Plan View

    private var floorPlanView: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let img = mapper.floorPlanImage {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .border(ZDDesign.mediumGray.opacity(0.3), width: 1)
                        .padding(.horizontal)
                    legendView
                    summaryView
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "map").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("Floor plan not yet generated.").font(.caption).foregroundColor(.secondary)
                        if mapper.trackPoints.count > 5 {
                            Button("Render Now") { mapper.renderFloorPlan() }
                                .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                        } else {
                            Text("Move through the space to collect data.")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(60)
                }
            }
            .padding(.top)
        }
    }

    private var legendView: some View {
        HStack(spacing: 14) {
            legendDot(Color(white: 0.85), "Open")
            legendDot(Color(white: 0.18), "Wall")
            legendDot(.cyan, "Path")
            legendDot(.red, "Hazard")
            legendDot(.green, "Exit")
        }
        .padding(.horizontal)
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private var summaryView: some View {
        HStack(spacing: 20) {
            statItem("\(mapper.trackPoints.count)", "Track pts", ZDDesign.cyanAccent)
            statItem("\(mapper.hazards.count)", "Hazards", ZDDesign.signalRed)
            statItem("\(mapper.exits.count)", "Exits", ZDDesign.successGreen)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func statItem(_ val: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(val).font(.title2.bold()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
