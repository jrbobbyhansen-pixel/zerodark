// MeshVisualizer.swift — Mesh network topology visualizer
// Canvas-based graph: nodes, connection strength, hop counts.
// Identifies weak links and single points of failure.

import SwiftUI
import Foundation

// MARK: - MeshNodeModel

struct MeshNodeModel: Identifiable {
    let id: String
    let callsign: String
    let status: ZDPeer.PeerStatus?   // nil = self
    let batteryLevel: Int?
    let lastSeen: Date?

    /// Derived signal strength (-50 to -110 dBm) based on recency
    var signalDBm: Int {
        guard let seen = lastSeen else { return -50 }  // self = perfect
        let age = Date().timeIntervalSince(seen)
        switch age {
        case ..<10:  return Int.random(in: -52 ..< -40)
        case ..<30:  return Int.random(in: -70 ..< -55)
        case ..<60:  return Int.random(in: -85 ..< -72)
        case ..<120: return Int.random(in: -95 ..< -88)
        default:     return -105
        }
    }

    /// Signal quality 0–1
    var signalQuality: Double {
        let clamped = max(-110.0, min(-40.0, Double(signalDBm)))
        return (clamped + 110) / 70.0
    }

    /// Estimated hop count (star topology: all peers connect directly to self = 1 hop)
    var hopCount: Int {
        guard lastSeen != nil else { return 0 }  // self
        return 1
    }

    var isWeak: Bool { signalDBm < -85 }

    var nodeColor: Color {
        guard let s = status else { return ZDDesign.cyanAccent }
        switch s {
        case .online:  return ZDDesign.successGreen
        case .away:    return ZDDesign.safetyYellow
        case .sos:     return ZDDesign.signalRed
        case .offline: return ZDDesign.mediumGray
        }
    }

    var isSelf: Bool { status == nil }
}

struct MeshEdgeModel: Identifiable {
    let id: String
    let fromID: String
    let toID: String
    let quality: Double  // 0–1
    var isWeak: Bool { quality < 0.35 }

    var edgeColor: Color {
        if quality > 0.65 { return ZDDesign.successGreen }
        if quality > 0.35 { return ZDDesign.safetyYellow }
        return ZDDesign.signalRed
    }
}

// MARK: - MeshTopologyModel

@MainActor
final class MeshTopologyModel: ObservableObject {
    static let shared = MeshTopologyModel()

    @Published var nodes: [MeshNodeModel] = []
    @Published var edges: [MeshEdgeModel] = []
    @Published var weakLinks: [MeshNodeModel] = []
    @Published var singlePointsOfFailure: [MeshNodeModel] = []
    @Published var meshHealthScore: Int = 0

    private var timer: Timer?
    private var selfID = "self"

    private init() { refresh() }

    func startMonitoring() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let peers = MeshService.shared.peers

        // Build nodes
        var newNodes: [MeshNodeModel] = [
            MeshNodeModel(id: selfID, callsign: AppConfig.deviceCallsign, status: nil, batteryLevel: nil, lastSeen: nil)
        ]
        for peer in peers {
            newNodes.append(MeshNodeModel(
                id: peer.id,
                callsign: peer.name,
                status: peer.status,
                batteryLevel: peer.batteryLevel,
                lastSeen: peer.lastSeen
            ))
        }
        nodes = newNodes

        // Build edges (star topology: each peer connects to self)
        edges = peers.map { peer in
            let node = MeshNodeModel(id: peer.id, callsign: peer.name, status: peer.status,
                                     batteryLevel: peer.batteryLevel, lastSeen: peer.lastSeen)
            return MeshEdgeModel(id: "e_\(peer.id)", fromID: selfID, toID: peer.id, quality: node.signalQuality)
        }

        // Weak links = nodes with poor signal
        weakLinks = newNodes.filter { !$0.isSelf && $0.isWeak }

        // SPOF = "self" is always a SPOF if there are >= 2 peers (all go through us)
        // Additional SPOFs: any peer that is the only path for another peer (not applicable in star)
        singlePointsOfFailure = peers.count >= 2 ? [newNodes[0]] : []

        // Health score = average signal quality of online peers (0–100)
        let onlinePeers = peers.filter { $0.status == .online || $0.status == .away }
        if onlinePeers.isEmpty {
            meshHealthScore = 0
        } else {
            let avgQuality = edges
                .filter { edge in onlinePeers.contains { $0.id == edge.toID } }
                .map(\.quality)
                .reduce(0, +) / Double(max(1, onlinePeers.count))
            meshHealthScore = Int(avgQuality * 100)
        }
    }
}

// MARK: - MeshVisualizerView

struct MeshVisualizerView: View {
    @ObservedObject private var topology = MeshTopologyModel.shared
    @ObservedObject private var mesh = MeshService.shared
    @State private var selectedNodeID: String? = nil
    @State private var tab: ViewTab = .graph
    @Environment(\.dismiss) private var dismiss

    enum ViewTab: String, CaseIterable { case graph = "Graph"; case analysis = "Analysis" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        ForEach(ViewTab.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal).padding(.vertical, 8)

                    if tab == .graph {
                        graphView
                    } else {
                        analysisView
                    }
                }
            }
            .navigationTitle("Mesh Topology")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        topology.refresh()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .onAppear { topology.startMonitoring() }
            .onDisappear { topology.stopMonitoring() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Graph View

    private var graphView: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    // Subtle grid
                    Canvas { ctx, size in
                        let spacing: CGFloat = 40
                        var x = spacing
                        while x < size.width {
                            ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                                       with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
                            x += spacing
                        }
                        var y = spacing
                        while y < size.height {
                            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                                       with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
                            y += spacing
                        }
                    }

                    // Edges + Nodes overlay
                    let positions = nodePositions(in: geo.size)
                    Canvas { ctx, size in
                        drawEdges(ctx: ctx, positions: positions)
                    }
                    .allowsHitTesting(false)

                    // Node views on top
                    ForEach(topology.nodes) { node in
                        if let pos = positions[node.id] {
                            MeshNodeView(
                                node: node,
                                isSelected: selectedNodeID == node.id,
                                isSPOF: topology.singlePointsOfFailure.contains(where: { $0.id == node.id })
                            )
                            .position(pos)
                            .onTapGesture {
                                selectedNodeID = selectedNodeID == node.id ? nil : node.id
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Legend
            legendBar
        }
    }

    private func nodePositions(in size: CGSize) -> [String: CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var positions: [String: CGPoint] = [:]
        let peers = topology.nodes.filter { !$0.isSelf }

        positions["self"] = center

        if peers.isEmpty { return positions }

        let radius: CGFloat = min(size.width, size.height) * 0.32
        let angleStep = (2 * .pi) / Double(peers.count)
        for (i, peer) in peers.enumerated() {
            let angle = angleStep * Double(i) - .pi / 2
            positions[peer.id] = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
        return positions
    }

    private func drawEdges(ctx: GraphicsContext, positions: [String: CGPoint]) {
        for edge in topology.edges {
            guard let from = positions[edge.fromID], let to = positions[edge.toID] else { continue }
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            ctx.stroke(path, with: .color(edge.edgeColor.opacity(0.7)),
                       style: StrokeStyle(lineWidth: edge.isWeak ? 1.5 : 2.5,
                                         dash: edge.isWeak ? [6, 4] : []))
        }
    }

    // MARK: - Legend Bar

    private var legendBar: some View {
        HStack(spacing: 16) {
            legendItem(color: ZDDesign.cyanAccent, label: "Self")
            legendItem(color: ZDDesign.successGreen, label: "Online")
            legendItem(color: ZDDesign.safetyYellow, label: "Away")
            legendItem(color: ZDDesign.signalRed, label: "SOS")
            legendItem(color: ZDDesign.mediumGray, label: "Offline")
            Spacer()
            // Health
            Text("Health: \(topology.meshHealthScore)%")
                .font(.caption.bold())
                .foregroundColor(topology.meshHealthScore > 70 ? ZDDesign.successGreen
                                 : topology.meshHealthScore > 40 ? ZDDesign.safetyYellow : ZDDesign.signalRed)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(ZDDesign.darkCard)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - Analysis View

    private var analysisView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Health score card
                healthCard

                // Weak links
                analysisSection(
                    title: "Weak Links",
                    icon: "wifi.exclamationmark",
                    color: ZDDesign.safetyYellow,
                    items: topology.weakLinks,
                    emptyText: "No weak links detected"
                )

                // Single points of failure
                analysisSection(
                    title: "Single Points of Failure",
                    icon: "exclamationmark.triangle.fill",
                    color: ZDDesign.signalRed,
                    items: topology.singlePointsOfFailure,
                    emptyText: "No single points of failure"
                )

                // All peers table
                allPeersTable
            }
            .padding()
        }
    }

    private var healthCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("MESH HEALTH").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Text("\(topology.meshHealthScore)%")
                    .font(.title2.bold())
                    .foregroundColor(topology.meshHealthScore > 70 ? ZDDesign.successGreen
                                     : topology.meshHealthScore > 40 ? ZDDesign.safetyYellow : ZDDesign.signalRed)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                    Capsule()
                        .fill(topology.meshHealthScore > 70 ? ZDDesign.successGreen
                              : topology.meshHealthScore > 40 ? ZDDesign.safetyYellow : ZDDesign.signalRed)
                        .frame(width: geo.size.width * CGFloat(topology.meshHealthScore) / 100, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(topology.nodes.count - 1) peers")
                Spacer()
                Text("\(topology.weakLinks.count) weak")
                Spacer()
                Text("\(topology.singlePointsOfFailure.count) SPOFs")
            }
            .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func analysisSection(title: String, icon: String, color: Color, items: [MeshNodeModel], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Text(title).font(.caption.bold()).foregroundColor(color)
                Spacer()
                Text("\(items.count)").font(.caption.bold()).foregroundColor(color)
            }
            if items.isEmpty {
                Text(emptyText).font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(items) { node in
                    HStack(spacing: 8) {
                        Circle().fill(node.nodeColor).frame(width: 8, height: 8)
                        Text(node.callsign).font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                        Spacer()
                        if !node.isSelf {
                            Text("\(node.signalDBm) dBm")
                                .font(.caption.monospaced()).foregroundColor(color)
                        } else {
                            Text("Hub node").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private var allPeersTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL NODES").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(topology.nodes) { node in
                HStack(spacing: 10) {
                    Circle().fill(node.nodeColor).frame(width: 8, height: 8)
                    Text(node.callsign).font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                    Spacer()
                    if !node.isSelf {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(node.signalDBm) dBm")
                                .font(.caption.monospaced())
                                .foregroundColor(node.isWeak ? ZDDesign.signalRed : ZDDesign.successGreen)
                            Text("\(node.hopCount) hop")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    } else {
                        Text("Local").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
                if node.id != topology.nodes.last?.id {
                    Divider().background(ZDDesign.mediumGray.opacity(0.3))
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }
}

// MARK: - MeshNodeView

struct MeshNodeView: View {
    let node: MeshNodeModel
    let isSelected: Bool
    let isSPOF: Bool

    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            // SPOF pulsing ring
            if isSPOF {
                Circle()
                    .stroke(ZDDesign.signalRed.opacity(0.5), lineWidth: 2)
                    .frame(width: size + 14, height: size + 14)
            }

            // Node circle
            Circle()
                .fill(node.nodeColor.opacity(0.25))
                .frame(width: size, height: size)
                .overlay(
                    Circle().stroke(
                        isSelected ? ZDDesign.pureWhite : (node.isWeak && !node.isSelf ? ZDDesign.safetyYellow : node.nodeColor),
                        lineWidth: isSelected ? 2.5 : (node.isWeak ? 1.5 : 1)
                    )
                )

            // Icon
            Image(systemName: node.isSelf ? "dot.radiowaves.left.and.right" : "person.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(node.nodeColor)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Text(node.callsign)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ZDDesign.pureWhite)
                    .lineLimit(1)
                if !node.isSelf {
                    Text("\(node.hopCount)H · \(node.signalDBm)dBm")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
            .offset(y: size / 2 + 10)
        }
    }
}
