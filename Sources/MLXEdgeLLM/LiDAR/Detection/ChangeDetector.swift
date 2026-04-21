// ChangeDetector.swift — Scan diff / voxel delta change detection.
//
// Compares two completed LiDAR scans at the voxel level. Each scan ships with
// a `voxel_map.bin` sidecar written by StreamingVoxelMap.snapshotToDisk — 20
// bytes per voxel:
//     [Int32 x][Int32 y][Int32 z][UInt32 hitCount][UInt16 flags][UInt16 pad]
//
// The diff produces three sets keyed by voxel coordinate:
//   - added    (present in newer, absent in older)
//   - removed  (present in older,  absent in newer)
//   - common   (present in both, possibly with changed hitCount / flags)
//
// Aggregate metrics give the user a first-glance summary (counts + bounding
// box of change region). 3D visualization of the diff can be layered on top
// of this same data in a follow-up.

import Foundation
import SwiftUI
import simd

// MARK: - VoxelRecord

/// Single voxel entry as stored in voxel_map.bin.
public struct VoxelRecord: Hashable {
    public let x: Int32
    public let y: Int32
    public let z: Int32
    public let hitCount: UInt32
    public let flags: UInt16

    /// Packed key used as the hash bucket for diff operations.
    public struct Key: Hashable {
        public let x: Int32
        public let y: Int32
        public let z: Int32
    }
    public var key: Key { Key(x: x, y: y, z: z) }

    public func worldCentre(voxelSize: Float) -> SIMD3<Float> {
        SIMD3<Float>(
            Float(x) * voxelSize + voxelSize * 0.5,
            Float(y) * voxelSize + voxelSize * 0.5,
            Float(z) * voxelSize + voxelSize * 0.5
        )
    }
}

// MARK: - ScanDiffResult

public struct ScanDiffResult {
    public let addedKeys: Set<VoxelRecord.Key>
    public let removedKeys: Set<VoxelRecord.Key>
    public let commonKeys: Set<VoxelRecord.Key>
    public let addedRecords: [VoxelRecord]
    public let removedRecords: [VoxelRecord]
    public let voxelSize: Float
    public let olderScanId: UUID
    public let newerScanId: UUID

    public var addedCount: Int   { addedKeys.count }
    public var removedCount: Int { removedKeys.count }
    public var commonCount: Int  { commonKeys.count }

    /// Fraction of the newer scan that is new. 1.0 = everything is new.
    public var noveltyRatio: Double {
        let total = addedCount + commonCount
        return total == 0 ? 0 : Double(addedCount) / Double(total)
    }

    /// Bounding box of the union of added + removed voxels, in voxel-cell space.
    public var changeBoundsMin: SIMD3<Int32>? { bounds.min }
    public var changeBoundsMax: SIMD3<Int32>? { bounds.max }

    private var bounds: (min: SIMD3<Int32>?, max: SIMD3<Int32>?) {
        var minV: SIMD3<Int32>? = nil
        var maxV: SIMD3<Int32>? = nil
        for k in addedKeys.union(removedKeys) {
            let v = SIMD3<Int32>(k.x, k.y, k.z)
            if let m = minV { minV = SIMD3(min(m.x, v.x), min(m.y, v.y), min(m.z, v.z)) } else { minV = v }
            if let m = maxV { maxV = SIMD3(max(m.x, v.x), max(m.y, v.y), max(m.z, v.z)) } else { maxV = v }
        }
        return (minV, maxV)
    }

    /// Worldspace diagonal length of the change bounding box, meters.
    public func changeDiagonalMeters() -> Float {
        guard let lo = changeBoundsMin, let hi = changeBoundsMax else { return 0 }
        let diag = SIMD3<Float>(Float(hi.x - lo.x), Float(hi.y - lo.y), Float(hi.z - lo.z)) * voxelSize
        return simd_length(diag)
    }
}

// MARK: - VoxelDiffEngine

public enum VoxelDiffEngine {

    /// Read a voxel_map.bin file into a dictionary keyed by VoxelRecord.Key.
    public static func read(_ url: URL) throws -> [VoxelRecord.Key: VoxelRecord] {
        let data = try Data(contentsOf: url)
        // 20 bytes per voxel. Truncated files are tolerated by ignoring the tail.
        let count = data.count / 20
        var out: [VoxelRecord.Key: VoxelRecord] = [:]
        out.reserveCapacity(count)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!
            for i in 0..<count {
                let p = base.advanced(by: i * 20)
                let x  = p.load(fromByteOffset: 0,  as: Int32.self)
                let y  = p.load(fromByteOffset: 4,  as: Int32.self)
                let z  = p.load(fromByteOffset: 8,  as: Int32.self)
                let hc = p.load(fromByteOffset: 12, as: UInt32.self)
                let fl = p.load(fromByteOffset: 16, as: UInt16.self)
                let rec = VoxelRecord(x: x, y: y, z: z, hitCount: hc, flags: fl)
                out[rec.key] = rec
            }
        }
        return out
    }

    /// Diff two scans by their saved voxel_map.bin files.
    /// - Parameters:
    ///   - older: the earlier scan
    ///   - newer: the later  scan
    ///   - voxelSize: must match the voxelSize VoxelStreamMap was configured
    ///     with when the scans were captured (default 0.08 m).
    public static func diff(
        older: SavedScan,
        newer: SavedScan,
        voxelSize: Float = 0.08
    ) throws -> ScanDiffResult {
        let oldURL = older.scanDir.appendingPathComponent("voxel_map.bin")
        let newURL = newer.scanDir.appendingPathComponent("voxel_map.bin")
        let oldMap = try read(oldURL)
        let newMap = try read(newURL)

        let oldKeys = Set(oldMap.keys)
        let newKeys = Set(newMap.keys)
        let added    = newKeys.subtracting(oldKeys)
        let removed  = oldKeys.subtracting(newKeys)
        let common   = newKeys.intersection(oldKeys)

        let addedRecords   = added.compactMap { newMap[$0] }
        let removedRecords = removed.compactMap { oldMap[$0] }

        return ScanDiffResult(
            addedKeys: added,
            removedKeys: removed,
            commonKeys: common,
            addedRecords: addedRecords,
            removedRecords: removedRecords,
            voxelSize: voxelSize,
            olderScanId: older.id,
            newerScanId: newer.id
        )
    }
}

// MARK: - ScanDiffViewModel

@MainActor
public final class ScanDiffViewModel: ObservableObject {
    @Published public var olderScan: SavedScan?
    @Published public var newerScan: SavedScan?
    @Published public var result: ScanDiffResult?
    @Published public var isRunning: Bool = false
    @Published public var errorMessage: String?

    public init() {}

    public func runDiff() {
        guard let older = olderScan, let newer = newerScan else { return }
        errorMessage = nil
        isRunning = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard self != nil else { return }
            do {
                let diff = try VoxelDiffEngine.diff(older: older, newer: newer)
                await MainActor.run {
                    self?.result = diff
                    self?.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Diff failed: \(error.localizedDescription)"
                    self?.isRunning = false
                }
            }
        }
    }
}

// MARK: - ChangeDetectionView

/// Scan-to-scan change detection UI. Pick an older and newer scan, run the diff,
/// see added / removed voxel counts and the change region's bounding box size.
/// Reachable from TacticalQueryParser's .terrainComparison route.
public struct ChangeDetectionView: View {
    @StateObject private var vm = ScanDiffViewModel()
    @ObservedObject private var storage = ScanStorage.shared
    @State private var showingOlderPicker = false
    @State private var showingNewerPicker = false

    public init() {}

    public var body: some View {
        List {
            Section("Scans") {
                scanRow(title: "Older", scan: vm.olderScan) { showingOlderPicker = true }
                scanRow(title: "Newer", scan: vm.newerScan) { showingNewerPicker = true }
            }

            Section {
                Button {
                    vm.runDiff()
                } label: {
                    HStack {
                        if vm.isRunning { ProgressView().tint(.white) }
                        Text(vm.isRunning ? "Computing…" : "Run Diff")
                            .font(.headline)
                    }
                }
                .disabled(vm.olderScan == nil || vm.newerScan == nil || vm.isRunning)
            }

            if let msg = vm.errorMessage {
                Section("Error") {
                    Text(msg).foregroundColor(.red).font(.caption)
                }
            }

            if let r = vm.result {
                resultSection(r)
            }
        }
        .navigationTitle("Scan Diff")
        .sheet(isPresented: $showingOlderPicker) {
            scanPicker { vm.olderScan = $0 }
        }
        .sheet(isPresented: $showingNewerPicker) {
            scanPicker { vm.newerScan = $0 }
        }
    }

    private func scanRow(title: String, scan: SavedScan?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).bold()
                Spacer()
                if let scan {
                    VStack(alignment: .trailing) {
                        Text(scan.name.isEmpty
                             ? scan.timestamp.formatted(date: .abbreviated, time: .shortened)
                             : scan.name)
                        Text("\(scan.pointCount) pts").font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Text("Choose…").foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ r: ScanDiffResult) -> some View {
        Section("Summary") {
            stat("Added voxels",   value: r.addedCount)
            stat("Removed voxels", value: r.removedCount)
            stat("Unchanged",      value: r.commonCount)
            stat("Novelty",        value: String(format: "%.1f%%", r.noveltyRatio * 100))
            if r.changeDiagonalMeters() > 0 {
                stat("Change region",
                     value: String(format: "%.1f m diagonal", r.changeDiagonalMeters()))
            }
        }
    }

    private func stat(_ title: String, value: Any) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").monospacedDigit().foregroundColor(.secondary)
        }
    }

    private func scanPicker(onPick: @escaping (SavedScan) -> Void) -> some View {
        NavigationStack {
            List(storage.savedScans) { scan in
                Button {
                    onPick(scan)
                } label: {
                    VStack(alignment: .leading) {
                        Text(scan.name.isEmpty
                             ? scan.timestamp.formatted(date: .abbreviated, time: .shortened)
                             : scan.name)
                        Text("\(scan.pointCount) pts").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Choose Scan")
        }
    }
}
