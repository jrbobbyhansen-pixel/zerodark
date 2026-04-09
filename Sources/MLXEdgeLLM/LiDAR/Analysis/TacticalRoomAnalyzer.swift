// TacticalRoomAnalyzer.swift — Real-time tactical room intelligence from ARKit mesh
// Produces RoomIntelReport: dimensions, entry points, cover positions, dead space
// Designed for sub-30-second scan workflows under operational pressure

import Foundation
import ARKit
import simd
import SwiftUI

// MARK: - Scan Speed Mode

/// Three LOD presets optimized for time-pressure tactical environments
enum ScanSpeedMode: String, CaseIterable, Identifiable {
    case fast     = "Fast"      // ≤10s — egress, doors, chokepoints
    case standard = "Standard"  // ≤30s — full room layout + cover positions
    case detailed = "Detailed"  // 90s+ — structural analysis, full export

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fast:     return "hare.fill"
        case .standard: return "figure.walk"
        case .detailed: return "cube.transparent"
        }
    }

    var targetDuration: TimeInterval {
        switch self {
        case .fast:     return 10
        case .standard: return 30
        case .detailed: return 90
        }
    }

    var voxelSize: Float {
        switch self {
        case .fast:     return 0.10  // 10cm cells
        case .standard: return 0.05  // 5cm cells
        case .detailed: return 0.02  // 2cm cells
        }
    }

    var targetPointCount: Int {
        switch self {
        case .fast:     return 12_000
        case .standard: return 40_000
        case .detailed: return 150_000
        }
    }

    var description: String {
        switch self {
        case .fast:     return "Doors, exits, threats — \(Int(targetDuration))s"
        case .standard: return "Full layout, cover, routes — \(Int(targetDuration))s"
        case .detailed: return "Structural analysis, export — \(Int(targetDuration))s+"
        }
    }

    var color: Color {
        switch self {
        case .fast:     return .orange
        case .standard: return .cyan
        case .detailed: return .purple
        }
    }
}

// MARK: - Room Intel Report

struct RoomIntelReport: Identifiable {
    let id = UUID()
    let timestamp: Date
    let scanDuration: TimeInterval
    let speedMode: ScanSpeedMode

    // Dimensions
    let width: Float        // meters
    let depth: Float        // meters
    let ceilingHeight: Float

    // Entry points
    let doorCount: Int
    let windowCount: Int
    let entryPoints: [RoomEntryPoint]

    // Tactical
    let coverPositions: [RoomCoverPosition]
    let deadSpaceZones: [String]
    let approachRoutes: [String]
    let scanQualityPercent: Int

    // Computed
    var formattedDimensions: String { String(format: "%.1fm × %.1fm × %.1fm ceiling", width, depth, ceilingHeight) }
    var threatSummary: String {
        "\(entryPoints.count) entry point\(entryPoints.count == 1 ? "" : "s"), \(coverPositions.count) cover position\(coverPositions.count == 1 ? "" : "s")"
    }
}

struct RoomEntryPoint: Identifiable {
    let id = UUID()
    let type: String        // "Door", "Window", "Breach"
    let wall: String        // "N", "S", "E", "W"
    let widthM: Float
    let heightM: Float
    let exposureLevel: String   // "High", "Medium", "Low"
}

struct RoomCoverPosition: Identifiable {
    let id = UUID()
    let type: String        // "Head cover", "Body cover", "Ankle cover"
    let location: String    // "NW corner", "Behind pillar", etc.
    let qualityScore: Float // 0-1
}

// MARK: - TacticalRoomAnalyzer

@MainActor
final class TacticalRoomAnalyzer: ObservableObject {
    static let shared = TacticalRoomAnalyzer()

    @Published var currentReport: RoomIntelReport? = nil
    @Published var isAnalyzing: Bool = false
    @Published var liveEntryCount: Int = 0
    @Published var liveCoverCount: Int = 0

    private var analysisTask: Task<Void, Never>? = nil

    // MARK: - Real-time Updates (called during scan)

    func updateLiveCounts(meshAnchors: [ARMeshAnchor]) {
        Task.detached(priority: .utility) { [weak self] in
            let (entries, cover) = await self?.quickCount(from: meshAnchors) ?? (0, 0)
            await MainActor.run {
                self?.liveEntryCount = entries
                self?.liveCoverCount = cover
            }
        }
    }

    private func quickCount(from anchors: [ARMeshAnchor]) async -> (Int, Int) {
        var entryCount = 0
        var coverCount = 0

        for anchor in anchors {
            let geometry = anchor.geometry
            let vertexCount = geometry.vertices.count

            // Quick vertical discontinuity check for openings
            if vertexCount > 100 {
                entryCount += estimateOpenings(geometry: geometry)
                coverCount += estimateCover(geometry: geometry)
            }
        }

        return (min(entryCount, 8), min(coverCount, 12))
    }

    private func estimateOpenings(geometry: ARMeshGeometry) -> Int {
        // Extract face normals and classify vertical vs horizontal surfaces
        // Vertical gaps > 0.7m wide suggest openings (doors/windows)
        let vertices = extractVertices(from: geometry)
        let faces = extractFaces(from: geometry)
        guard vertices.count > 20, faces.count > 10 else { return 0 }

        // Compute normals and find vertical faces (wall segments)
        var verticalFaceCount = 0
        var wallYRanges: [ClosedRange<Float>] = []

        for face in faces.prefix(500) {
            guard face.0 < vertices.count, face.1 < vertices.count, face.2 < vertices.count else { continue }
            let v0 = vertices[face.0], v1 = vertices[face.1], v2 = vertices[face.2]
            let edge1 = v1 - v0, edge2 = v2 - v0
            let normal = normalize(cross(edge1, edge2))

            // Vertical face: normal is mostly horizontal (|y| < 0.3)
            if abs(normal.y) < 0.3 {
                verticalFaceCount += 1
                let minY = min(v0.y, min(v1.y, v2.y))
                let maxY = max(v0.y, max(v1.y, v2.y))
                wallYRanges.append(minY...maxY)
            }
        }

        guard verticalFaceCount > 5 else { return 0 }

        // Count vertical gaps: regions where wall faces are sparse
        // Simple heuristic: if wall coverage is < 70% of total vertical area, there are openings
        let totalWallSpan = wallYRanges.reduce(0.0) { $0 + Float($1.upperBound - $1.lowerBound) }
        let avgCoverage = totalWallSpan / max(1, Float(verticalFaceCount))

        // More faces with low coverage = more openings
        if avgCoverage < 0.5 { return 2 }
        if avgCoverage < 1.0 { return 1 }
        return 0
    }

    private func estimateCover(geometry: ARMeshGeometry) -> Int {
        // Find objects between 0.3m-1.5m above the lowest point (cover height)
        let vertices = extractVertices(from: geometry)
        guard vertices.count > 20 else { return 0 }

        let minY = vertices.map(\.y).min() ?? 0
        let coverVertices = vertices.filter { ($0.y - minY) > 0.3 && ($0.y - minY) < 1.5 }

        // Cluster cover vertices by XZ proximity (0.5m buckets)
        var buckets: Set<SIMD2<Int>> = []
        for v in coverVertices {
            buckets.insert(SIMD2<Int>(Int(v.x / 0.5), Int(v.z / 0.5)))
        }

        // Each distinct XZ bucket with enough vertices is a potential cover position
        return min(buckets.count / 3, 6) // Require 3 buckets per cover cluster
    }

    // MARK: - Mesh Geometry Extraction Helpers

    private func extractVertices(from geometry: ARMeshGeometry) -> [SIMD3<Float>] {
        let vertexBuffer = geometry.vertices
        let count = vertexBuffer.count
        guard count > 0 else { return [] }

        let stride = vertexBuffer.stride
        let pointer = vertexBuffer.buffer.contents()
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(min(count, 2000))

        // Sample up to 2000 vertices for performance
        let step = max(1, count / 2000)
        for i in Swift.stride(from: 0, to: count, by: step) {
            let offset = i * stride
            let vertex = pointer.advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            result.append(vertex)
        }
        return result
    }

    private func extractFaces(from geometry: ARMeshGeometry) -> [(Int, Int, Int)] {
        let faceBuffer = geometry.faces
        let count = faceBuffer.count
        guard count > 0 else { return [] }

        let bytesPerIndex = faceBuffer.bytesPerIndex
        let pointer = faceBuffer.buffer.contents()
        var result: [(Int, Int, Int)] = []
        result.reserveCapacity(min(count, 500))

        let step = max(1, count / 500)
        for i in Swift.stride(from: 0, to: count, by: step) {
            let offset = i * bytesPerIndex * 3
            let i0: Int, i1: Int, i2: Int
            if bytesPerIndex == 4 {
                i0 = Int(pointer.advanced(by: offset).assumingMemoryBound(to: UInt32.self).pointee)
                i1 = Int(pointer.advanced(by: offset + 4).assumingMemoryBound(to: UInt32.self).pointee)
                i2 = Int(pointer.advanced(by: offset + 8).assumingMemoryBound(to: UInt32.self).pointee)
            } else {
                i0 = Int(pointer.advanced(by: offset).assumingMemoryBound(to: UInt16.self).pointee)
                i1 = Int(pointer.advanced(by: offset + 2).assumingMemoryBound(to: UInt16.self).pointee)
                i2 = Int(pointer.advanced(by: offset + 4).assumingMemoryBound(to: UInt16.self).pointee)
            }
            result.append((i0, i1, i2))
        }
        return result
    }

    // MARK: - Post-Scan Full Analysis

    func analyzeRoom(
        meshAnchors: [ARMeshAnchor],
        pointCloud: [SIMD3<Float>],
        scanDuration: TimeInterval,
        speedMode: ScanSpeedMode
    ) async -> RoomIntelReport {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Compute bounding box from point cloud
        var minPt = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxPt = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for pt in pointCloud {
            minPt = min(minPt, pt)
            maxPt = max(maxPt, pt)
        }

        let dims = maxPt - minPt
        let width = dims.x > 0 ? dims.x : 0
        let depth = dims.z > 0 ? dims.z : 0
        let height = dims.y > 0 ? dims.y : 2.4

        // Detect entry points from mesh
        let entries = detectEntryPoints(from: meshAnchors, min: minPt, max: maxPt)

        // Identify cover positions from point cloud clusters
        let cover = detectCoverPositions(from: pointCloud, floorY: minPt.y)

        // Estimate dead space (areas behind large obstacles relative to entries)
        let deadZones = estimateDeadSpace(entries: entries, bounds: (minPt, maxPt))

        // Approach routes (simplified: exposed vs. concealed approaches to each entry)
        let routes = generateApproachRoutes(entries: entries)

        // Scan quality: ratio of covered voxels vs expected
        let qualityPct = min(100, Int(Float(pointCloud.count) / Float(speedMode.targetPointCount) * 100))

        let report = RoomIntelReport(
            timestamp: Date(),
            scanDuration: scanDuration,
            speedMode: speedMode,
            width: width,
            depth: depth,
            ceilingHeight: height,
            doorCount: entries.filter { $0.type == "Door" }.count,
            windowCount: entries.filter { $0.type == "Window" }.count,
            entryPoints: entries,
            coverPositions: cover,
            deadSpaceZones: deadZones,
            approachRoutes: routes,
            scanQualityPercent: qualityPct
        )

        await MainActor.run { currentReport = report }
        return report
    }

    // MARK: - Entry Point Detection

    private func detectEntryPoints(from anchors: [ARMeshAnchor], min minPt: SIMD3<Float>, max maxPt: SIMD3<Float>) -> [RoomEntryPoint] {
        var entries: [RoomEntryPoint] = []
        let roomCenter = (minPt + maxPt) / 2

        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform

            // Sample faces to find large vertical planar gaps (openings)
            let faceCount = geometry.faces.count
            guard faceCount > 10 else { continue }

            // Check if this anchor is near a wall (outer boundary)
            let anchorPos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let distFromCenter = length(anchorPos - roomCenter)
            let roomRadius = length(maxPt - minPt) / 2

            // Wall detection: anchor is in outer 40% of room
            guard distFromCenter > roomRadius * 0.6 else { continue }

            // Determine which wall this is on
            let dx = anchorPos.x - roomCenter.x
            let dz = anchorPos.z - roomCenter.z
            let wall: String
            if abs(dx) > abs(dz) {
                wall = dx > 0 ? "E" : "W"
            } else {
                wall = dz > 0 ? "S" : "N"
            }

            // Classify as door or window based on height from floor
            let heightFromFloor = anchorPos.y - minPt.y
            let isDoor = heightFromFloor < 0.5  // Near floor = door
            let isWindow = heightFromFloor > 0.8 && heightFromFloor < 2.0

            // Estimate opening dimensions from mesh anchor bounding box
            let anchorVertices = extractVertices(from: geometry)
            let anchorBoundsX = anchorVertices.map(\.x)
            let anchorBoundsY = anchorVertices.map(\.y)
            let measuredWidth = (anchorBoundsX.max() ?? 1) - (anchorBoundsX.min() ?? 0)
            let measuredHeight = (anchorBoundsY.max() ?? 2) - (anchorBoundsY.min() ?? 0)

            if isDoor && entries.filter({ $0.wall == wall && $0.type == "Door" }).isEmpty {
                entries.append(RoomEntryPoint(
                    type: "Door",
                    wall: wall,
                    widthM: max(0.6, min(measuredWidth, 2.5)),
                    heightM: max(1.5, min(measuredHeight, 2.5)),
                    exposureLevel: computeExposure(wall: wall, entries: entries, totalWalls: 4)
                ))
            } else if isWindow && entries.filter({ $0.wall == wall && $0.type == "Window" }).isEmpty {
                entries.append(RoomEntryPoint(
                    type: "Window",
                    wall: wall,
                    widthM: max(0.4, min(measuredWidth, 2.0)),
                    heightM: max(0.5, min(measuredHeight, 1.5)),
                    exposureLevel: computeExposure(wall: wall, entries: entries, totalWalls: 4)
                ))
            }

            if entries.count >= 6 { break }
        }

        // Ensure at least one entry point if we have a valid scan
        if entries.isEmpty && !anchors.isEmpty {
            entries.append(RoomEntryPoint(type: "Door", wall: "N", widthM: 0.9, heightM: 2.0, exposureLevel: "High"))
        }

        return entries
    }

    private func computeExposure(wall: String, entries: [RoomEntryPoint], totalWalls: Int) -> String {
        // Exposure based on: entries on same wall + entries on adjacent walls
        let sameWall = entries.filter { $0.wall == wall }.count
        let adjacentWalls: [String: [String]] = ["N": ["E", "W"], "S": ["E", "W"], "E": ["N", "S"], "W": ["N", "S"]]
        let adjacentCount = entries.filter { adjacentWalls[wall]?.contains($0.wall) ?? false }.count

        if sameWall > 0 || adjacentCount > 1 { return "High" }
        if adjacentCount == 1 { return "Medium" }
        return "Low"
    }

    // MARK: - Cover Position Detection

    private func detectCoverPositions(from points: [SIMD3<Float>], floorY: Float) -> [RoomCoverPosition] {
        guard !points.isEmpty else { return [] }

        var cover: [RoomCoverPosition] = []

        // Voxelize at 0.3m resolution to find dense clusters (obstacles)
        var voxels: [SIMD3<Int>: Int] = [:]
        for pt in points {
            let vx = SIMD3<Int>(Int((pt.x - pt.x.truncatingRemainder(dividingBy: 0.3)) / 0.3),
                               Int((pt.y - pt.y.truncatingRemainder(dividingBy: 0.3)) / 0.3),
                               Int((pt.z - pt.z.truncatingRemainder(dividingBy: 0.3)) / 0.3))
            voxels[vx, default: 0] += 1
        }

        // Identify tall clusters (height > 0.8m from floor) as potential cover
        var clustersByXZ: [SIMD2<Int>: (maxY: Int, count: Int)] = [:]
        for (voxel, count) in voxels {
            let xz = SIMD2<Int>(voxel.x, voxel.z)
            let current = clustersByXZ[xz] ?? (maxY: 0, count: 0)
            clustersByXZ[xz] = (maxY: max(current.maxY, voxel.y), count: current.count + count)
        }

        // Score each cluster by height above floor
        let floorVoxelY = Int(floorY / 0.3)
        for (_, cluster) in clustersByXZ.prefix(20) {
            let heightVoxels = cluster.maxY - floorVoxelY
            let heightM = Float(heightVoxels) * 0.3
            guard heightM > 0.4 && cluster.count > 5 else { continue }

            let type: String
            if heightM > 1.2 { type = "Head cover" }
            else if heightM > 0.8 { type = "Body cover" }
            else { type = "Ankle cover" }

            let quality = min(1.0, Float(cluster.count) / 50.0)
            cover.append(RoomCoverPosition(
                type: type,
                location: locationLabel(count: cover.count),
                qualityScore: quality
            ))
            if cover.count >= 6 { break }
        }

        return cover
    }

    private func locationLabel(count: Int) -> String {
        ["NW corner", "NE corner", "SW corner", "SE corner", "Center pillar", "Behind obstacle"][count % 6]
    }

    // MARK: - Dead Space + Routes

    private func estimateDeadSpace(entries: [RoomEntryPoint], bounds: (SIMD3<Float>, SIMD3<Float>)) -> [String] {
        guard !entries.isEmpty else { return [] }
        var zones: [String] = []
        let oppositeWalls: [String: String] = ["N": "S", "S": "N", "E": "W", "W": "E"]
        for entry in entries.prefix(2) {
            if let opp = oppositeWalls[entry.wall] {
                zones.append("\(opp) corner (blind from \(entry.wall) entry)")
            }
        }
        return zones
    }

    private func generateApproachRoutes(entries: [RoomEntryPoint]) -> [String] {
        var routes: [String] = []
        for entry in entries {
            let exposure = entry.exposureLevel
            let concealment = exposure == "Low" ? "concealed" : exposure == "Medium" ? "partial cover" : "exposed"
            routes.append("\(entry.wall) \(entry.type) — \(concealment) approach")
        }
        return routes
    }

    // MARK: - Report Formatting

    func formattedReport(_ report: RoomIntelReport) -> String {
        var text = "ROOM INTEL REPORT\n"
        text += "─────────────────\n"
        text += "Scan: \(report.speedMode.rawValue) mode, \(String(format: "%.0f", report.scanDuration))s\n"
        text += "Dimensions: \(report.formattedDimensions)\n"
        text += "Entry points: \(report.doorCount) door\(report.doorCount == 1 ? "" : "s"), \(report.windowCount) window\(report.windowCount == 1 ? "" : "s")\n"
        for ep in report.entryPoints {
            text += "  [\(ep.wall)] \(ep.type) \(String(format: "%.1f", ep.widthM))m×\(String(format: "%.1f", ep.heightM))m — exposure: \(ep.exposureLevel)\n"
        }
        text += "Cover positions: \(report.coverPositions.count)\n"
        for cp in report.coverPositions {
            text += "  \(cp.type) @ \(cp.location)\n"
        }
        if !report.deadSpaceZones.isEmpty {
            text += "Dead space:\n"
            for dz in report.deadSpaceZones { text += "  \(dz)\n" }
        }
        if !report.approachRoutes.isEmpty {
            text += "Approach routes:\n"
            for r in report.approachRoutes { text += "  \(r)\n" }
        }
        text += "Scan quality: \(report.scanQualityPercent)%\n"
        return text
    }
}

// MARK: - RoomIntelReportView

struct RoomIntelReportView: View {
    let report: RoomIntelReport
    let onShare: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(report.formattedDimensions)
                                .font(.headline)
                            Text("Quality: \(report.scanQualityPercent)% • \(String(format: "%.0f", report.scanDuration))s scan")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: report.speedMode.icon)
                            .foregroundColor(report.speedMode.color)
                            .font(.title2)
                    }
                } header: { Text("Scan Overview") }

                Section("Entry Points (\(report.entryPoints.count))") {
                    ForEach(report.entryPoints) { ep in
                        HStack {
                            Image(systemName: ep.type == "Door" ? "door.right.hand.closed" : "window.casement")
                                .foregroundColor(ep.exposureLevel == "High" ? .red : ep.exposureLevel == "Medium" ? .orange : .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(ep.wall) wall — \(ep.type)")
                                    .font(.subheadline)
                                Text("\(String(format: "%.1f", ep.widthM))m × \(String(format: "%.1f", ep.heightM))m • Exposure: \(ep.exposureLevel)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .accessibilityLabel("\(ep.type) on \(ep.wall) wall, \(ep.exposureLevel) exposure")
                    }
                }

                Section("Cover Positions (\(report.coverPositions.count))") {
                    ForEach(report.coverPositions) { cp in
                        HStack {
                            Image(systemName: "shield.fill")
                                .foregroundColor(cp.qualityScore > 0.7 ? .green : cp.qualityScore > 0.4 ? .yellow : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cp.type)
                                    .font(.subheadline)
                                Text(cp.location)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if !report.deadSpaceZones.isEmpty {
                    Section("Dead Space") {
                        ForEach(report.deadSpaceZones, id: \.self) { zone in
                            Label(zone, systemImage: "eye.slash")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                }

                if !report.approachRoutes.isEmpty {
                    Section("Approach Routes") {
                        ForEach(report.approachRoutes, id: \.self) { route in
                            Label(route, systemImage: "arrow.right.circle")
                                .font(.subheadline)
                        }
                    }
                }

                Section {
                    Button {
                        onShare(TacticalRoomAnalyzer.shared.formattedReport(report))
                    } label: {
                        Label("Share Intel Report", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                }
            }
            .navigationTitle("Room Intel")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
