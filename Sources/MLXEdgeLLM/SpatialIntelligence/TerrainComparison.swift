// TerrainComparison.swift — Compare two LiDAR point cloud scans to detect changes
// Voxel-grid diffing: detects added, removed, and displaced material.
// Useful for monitoring, damage assessment, or intrusion detection.
// No internet required. Reads points.bin from ScanStorage scan directories.

import Foundation
import SwiftUI

// MARK: - ChangeType

enum ChangeType {
    case added      // present in scan B, not in A
    case removed    // present in scan A, not in B
    case unchanged
}

// MARK: - VoxelChange

struct VoxelChange: Identifiable {
    let id = UUID()
    let voxelIndex: SIMD3<Int32>
    let center: SIMD3<Float>
    let type: ChangeType
}

// MARK: - ComparisonResult

struct ComparisonResult {
    let scanA: SavedScan
    let scanB: SavedScan
    let added: Int
    let removed: Int
    let unchanged: Int
    let totalVoxels: Int
    let changes: [VoxelChange]
    let changePercent: Double
    let elapsedSeconds: Double

    var summary: String {
        String(format: "%.1f%% changed — +%d removed %d voxels (%.3f m grid)",
               changePercent, added, removed, voxelSize)
    }
    let voxelSize: Float
}

// MARK: - TerrainComparisonEngine

enum TerrainComparisonEngine {

    /// Load raw SIMD3<Float> points from a scan's points.bin file.
    static func loadPoints(from scan: SavedScan) -> [SIMD3<Float>] {
        let url = scan.scanDir.appendingPathComponent("points.bin")
        guard let data = try? Data(contentsOf: url), data.count >= 4 else { return [] }
        var count: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &count) { data.copyBytes(to: $0, from: 0..<4) }
        let expected = Int(count) * 12 + 4
        guard data.count >= expected else { return [] }
        return (0..<Int(count)).map { i in
            let offset = 4 + i * 12
            var p = SIMD3<Float>.zero
            _ = withUnsafeMutableBytes(of: &p) { data.copyBytes(to: $0, from: offset..<(offset + 12)) }
            return p
        }
    }

    /// Voxelize a point cloud into a set of occupied voxel indices.
    static func voxelize(_ points: [SIMD3<Float>], voxelSize: Float) -> Set<SIMD3<Int32>> {
        var grid = Set<SIMD3<Int32>>(minimumCapacity: points.count)
        for p in points {
            grid.insert(SIMD3<Int32>(Int32(floor(p.x / voxelSize)),
                                     Int32(floor(p.y / voxelSize)),
                                     Int32(floor(p.z / voxelSize))))
        }
        return grid
    }

    /// Compare two scans. Returns nil if either has no point data.
    static func compare(scanA: SavedScan, scanB: SavedScan,
                        voxelSize: Float = 0.05) -> ComparisonResult? {
        let start = Date()
        let ptsA = loadPoints(from: scanA)
        let ptsB = loadPoints(from: scanB)
        guard !ptsA.isEmpty, !ptsB.isEmpty else { return nil }

        let gridA = voxelize(ptsA, voxelSize: voxelSize)
        let gridB = voxelize(ptsB, voxelSize: voxelSize)

        let addedVoxels   = gridB.subtracting(gridA)
        let removedVoxels = gridA.subtracting(gridB)
        let unchanged     = gridA.intersection(gridB).count
        let total         = gridA.union(gridB).count

        var changes: [VoxelChange] = []
        // Limit change list to 2000 entries for display performance
        let limit = 2000
        var count = 0
        for v in addedVoxels.prefix(limit / 2) {
            changes.append(VoxelChange(voxelIndex: v,
                                       center: SIMD3<Float>(Float(v.x) + 0.5, Float(v.y) + 0.5, Float(v.z) + 0.5) * voxelSize,
                                       type: .added))
            count += 1
        }
        for v in removedVoxels.prefix(limit / 2) {
            changes.append(VoxelChange(voxelIndex: v,
                                       center: SIMD3<Float>(Float(v.x) + 0.5, Float(v.y) + 0.5, Float(v.z) + 0.5) * voxelSize,
                                       type: .removed))
        }

        let changePercent = total > 0
            ? Double(addedVoxels.count + removedVoxels.count) / Double(total) * 100
            : 0.0

        return ComparisonResult(
            scanA: scanA,
            scanB: scanB,
            added: addedVoxels.count,
            removed: removedVoxels.count,
            unchanged: unchanged,
            totalVoxels: total,
            changes: changes,
            changePercent: changePercent,
            elapsedSeconds: Date().timeIntervalSince(start),
            voxelSize: voxelSize
        )
    }
}

// MARK: - TerrainComparisonManager

@MainActor
final class TerrainComparisonManager: ObservableObject {
    static let shared = TerrainComparisonManager()

    @Published var result: ComparisonResult? = nil
    @Published var isComparing = false
    @Published var errorMessage: String? = nil
    @Published var voxelSize: Float = 0.05   // 5 cm default

    private init() {}

    func compare(scanA: SavedScan, scanB: SavedScan) {
        isComparing = true
        errorMessage = nil
        result = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let voxSize = await self.voxelSize
            let r = TerrainComparisonEngine.compare(scanA: scanA, scanB: scanB, voxelSize: voxSize)
            await MainActor.run {
                self.result = r
                self.isComparing = false
                if r == nil { self.errorMessage = "One or both scans have no point cloud data." }
            }
        }
    }
}

// MARK: - TerrainComparisonView

struct TerrainComparisonView: View {
    @ObservedObject private var mgr = TerrainComparisonManager.shared
    @ObservedObject private var storage = ScanStorage.shared
    @State private var selectedA: SavedScan? = nil
    @State private var selectedB: SavedScan? = nil
    @State private var pickingA = false
    @State private var pickingB = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        scanSelectorCard
                        if mgr.isComparing { comparingCard }
                        if let err = mgr.errorMessage { errorCard(err) }
                        if let r = mgr.result { resultCard(r) }
                    }
                    .padding()
                }
            }
            .navigationTitle("Terrain Comparison")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $pickingA) { scanPicker(label: "Scan A") { selectedA = $0 } }
            .sheet(isPresented: $pickingB) { scanPicker(label: "Scan B") { selectedB = $0 } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Scan Selector

    private var scanSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SELECT SCANS").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 12) {
                scanButton(label: "Scan A (before)", scan: selectedA) { pickingA = true }
                scanButton(label: "Scan B (after)",  scan: selectedB) { pickingB = true }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voxel Size").font(.caption).foregroundColor(.secondary)
                    Text(String(format: "%.3f m", mgr.voxelSize)).font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                }
                Spacer()
                Stepper("", value: $mgr.voxelSize, in: 0.01...0.5, step: 0.01)
                    .labelsHidden()
            }
            Button {
                if let a = selectedA, let b = selectedB {
                    mgr.compare(scanA: a, scanB: b)
                }
            } label: {
                Label("Compare", systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.headline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selectedA != nil && selectedB != nil ? ZDDesign.cyanAccent : ZDDesign.mediumGray)
                    .cornerRadius(10)
            }
            .disabled(selectedA == nil || selectedB == nil || mgr.isComparing)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func scanButton(label: String, scan: SavedScan?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "cube.fill")
                    .font(.title2)
                    .foregroundColor(scan != nil ? ZDDesign.cyanAccent : ZDDesign.mediumGray)
                Text(scan.map { $0.name.isEmpty ? scanTimestamp($0) : $0.name } ?? label)
                    .font(.caption2)
                    .foregroundColor(scan != nil ? ZDDesign.pureWhite : ZDDesign.mediumGray)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(ZDDesign.darkBackground)
            .cornerRadius(8)
        }
    }

    // MARK: - Comparing Indicator

    private var comparingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent)
            Text("Voxelizing and comparing…").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Error Card

    private func errorCard(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(ZDDesign.signalRed)
            Text(msg).font(.subheadline).foregroundColor(.secondary)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Result Card

    private func resultCard(_ r: ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMPARISON RESULT").font(.caption.bold()).foregroundColor(.secondary)

            // Change pie
            changePie(r)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statPill(v: "\(r.added)",   l: "Added",     c: ZDDesign.successGreen)
                statPill(v: "\(r.removed)", l: "Removed",   c: ZDDesign.signalRed)
                statPill(v: String(format: "%.1f%%", r.changePercent), l: "Changed", c: .orange)
                statPill(v: "\(r.unchanged)", l: "Stable",  c: ZDDesign.cyanAccent)
                statPill(v: "\(r.totalVoxels)", l: "Voxels", c: ZDDesign.mediumGray)
                statPill(v: String(format: "%.2fs", r.elapsedSeconds), l: "Time",   c: ZDDesign.mediumGray)
            }

            // Change list (first 30)
            if !r.changes.isEmpty {
                Text("TOP CHANGES").font(.caption.bold()).foregroundColor(.secondary)
                ForEach(r.changes.prefix(30)) { c in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(c.type == .added ? ZDDesign.successGreen : ZDDesign.signalRed)
                            .frame(width: 8, height: 8)
                        Text(c.type == .added ? "Added" : "Removed")
                            .font(.caption.bold())
                            .foregroundColor(c.type == .added ? ZDDesign.successGreen : ZDDesign.signalRed)
                        Spacer()
                        Text(String(format: "(%.2f, %.2f, %.2f)", c.center.x, c.center.y, c.center.z))
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                if r.changes.count > 30 {
                    Text("…and \(r.changes.count - 30) more").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func changePie(_ r: ComparisonResult) -> some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard r.totalVoxels > 0 else { return }
                let added    = Double(r.added)    / Double(r.totalVoxels)
                let removed  = Double(r.removed)  / Double(r.totalVoxels)
                let stable   = Double(r.unchanged) / Double(r.totalVoxels)
                let center   = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius   = min(size.width, size.height) / 2 - 4
                func sector(from: Double, to: Double, color: Color) {
                    var path = Path()
                    path.move(to: center)
                    path.addArc(center: center, radius: radius,
                                startAngle: .radians(from * .pi * 2 - .pi / 2),
                                endAngle: .radians(to * .pi * 2 - .pi / 2),
                                clockwise: false)
                    path.closeSubpath()
                    ctx.fill(path, with: .color(color))
                }
                sector(from: 0,                  to: stable,          color: ZDDesign.cyanAccent.opacity(0.6))
                sector(from: stable,             to: stable + added,  color: ZDDesign.successGreen)
                sector(from: stable + added,     to: 1.0,             color: ZDDesign.signalRed)
            }
        }
        .frame(height: 100)
    }

    private func statPill(v: String, l: String, c: Color) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.caption.bold()).foregroundColor(c)
            Text(l).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(c.opacity(0.08)).cornerRadius(8)
    }

    // MARK: - Scan Picker Sheet

    private func scanPicker(label: String, onSelect: @escaping (SavedScan) -> Void) -> some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List(storage.savedScans) { scan in
                    Button {
                        onSelect(scan)
                        pickingA = false
                        pickingB = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scan.name.isEmpty ? scanTimestamp(scan) : scan.name)
                                .font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text("\(scan.pointCount.formatted()) points")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(label)
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func scanTimestamp(_ scan: SavedScan) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: scan.timestamp)
    }
}
