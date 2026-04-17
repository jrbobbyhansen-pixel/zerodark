// MeshExporter.swift — Export LiDAR point cloud scans to OBJ or PLY format
// Reads points.bin from a SavedScan directory, applies resolution and bounds filtering,
// writes ASCII PLY or OBJ point file, surfaces via share sheet.
// No internet required.

import Foundation
import SwiftUI

// MARK: - PointCloudFormat

enum PointCloudFormat: String, CaseIterable, Identifiable {
    case ply = "PLY"
    case obj = "OBJ"
    var id: String { rawValue }
    var ext: String { rawValue.lowercased() }
    var icon: String {
        switch self {
        case .ply: return "doc.fill"
        case .obj: return "cube.fill"
        }
    }
}

// MARK: - PointCloudExportConfig

struct PointCloudExportConfig {
    var format: PointCloudFormat = .ply
    /// Voxel size for downsampling. 0 = no downsampling.
    var voxelDownsample: Float = 0.02
    /// Clip to bounding cube half-extent in meters (0 = no clip).
    var boundsHalfExtent: Float = 0
}

// MARK: - PointCloudExporterEngine

enum PointCloudExporterEngine {

    // MARK: Load

    static func loadPoints(from scan: SavedScan) -> [SIMD3<Float>] {
        let url = scan.scanDir.appendingPathComponent("points.bin")
        guard let data = try? Data(contentsOf: url), data.count >= 4 else { return [] }
        var count: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &count) { data.copyBytes(to: $0, from: 0..<4) }
        let n = Int(count)
        let expected = n * 12 + 4
        guard data.count >= expected else { return [] }
        return (0..<n).map { i in
            let off = 4 + i * 12
            var p = SIMD3<Float>.zero
            _ = withUnsafeMutableBytes(of: &p) { data.copyBytes(to: $0, from: off..<(off + 12)) }
            return p
        }
    }

    // MARK: Downsample

    static func voxelDownsample(_ points: [SIMD3<Float>], size: Float) -> [SIMD3<Float>] {
        guard size > 0, !points.isEmpty else { return points }
        var grid = [SIMD3<Int32>: SIMD3<Float>]()
        grid.reserveCapacity(points.count)
        for p in points {
            let key = SIMD3<Int32>(Int32(floor(p.x / size)),
                                   Int32(floor(p.y / size)),
                                   Int32(floor(p.z / size)))
            if grid[key] == nil { grid[key] = p }
        }
        return Array(grid.values)
    }

    // MARK: Clip

    static func clip(_ points: [SIMD3<Float>], halfExtent: Float) -> [SIMD3<Float>] {
        guard halfExtent > 0 else { return points }
        return points.filter {
            abs($0.x) <= halfExtent && abs($0.y) <= halfExtent && abs($0.z) <= halfExtent
        }
    }

    // MARK: PLY Export

    static func writePLY(_ points: [SIMD3<Float>], to url: URL) throws {
        var text = """
ply
format ascii 1.0
element vertex \(points.count)
property float x
property float y
property float z
end_header\n
"""
        for p in points {
            text += String(format: "%.6f %.6f %.6f\n", p.x, p.y, p.z)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: OBJ Export

    static func writeOBJ(_ points: [SIMD3<Float>], to url: URL) throws {
        var text = "# ZeroDark LiDAR Point Cloud Export\n"
        for p in points {
            text += String(format: "v %.6f %.6f %.6f\n", p.x, p.y, p.z)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Export Entry Point

    static func export(scan: SavedScan, config: PointCloudExportConfig) throws -> URL {
        var points = loadPoints(from: scan)
        guard !points.isEmpty else { throw ExportError.noPointData }
        points = voxelDownsample(points, size: config.voxelDownsample)
        points = clip(points, halfExtent: config.boundsHalfExtent)
        guard !points.isEmpty else { throw ExportError.noPointData }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ts = Int(Date().timeIntervalSince1970)
        let url = docs.appendingPathComponent("zerodark-export-\(ts).\(config.format.ext)")

        switch config.format {
        case .ply: try writePLY(points, to: url)
        case .obj: try writeOBJ(points, to: url)
        }
        return url
    }

    enum ExportError: LocalizedError {
        case noPointData
        var errorDescription: String? {
            "No point cloud data found for this scan."
        }
    }
}

// MARK: - PointCloudExporterManager

@MainActor
final class PointCloudExporterManager: ObservableObject {
    static let shared = PointCloudExporterManager()

    @Published var isExporting = false
    @Published var exportedURL: URL? = nil
    @Published var errorMessage: String? = nil
    @Published var config = PointCloudExportConfig()

    private init() {}

    func export(scan: SavedScan) {
        isExporting = true
        exportedURL = nil
        errorMessage = nil
        let cfg = config
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let url = try PointCloudExporterEngine.export(scan: scan, config: cfg)
                await MainActor.run {
                    self?.isExporting = false
                    self?.exportedURL = url
                }
            } catch {
                await MainActor.run {
                    self?.isExporting = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - PointCloudExporterView

struct PointCloudExporterView: View {
    @ObservedObject private var mgr = PointCloudExporterManager.shared
    @ObservedObject private var storage = ScanStorage.shared
    @State private var selectedScan: SavedScan? = nil
    @State private var pickingScan = false
    @State private var showShare = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        scanCard
                        configCard
                        exportButton
                        if mgr.isExporting { exportingCard }
                        if let err = mgr.errorMessage { errorCard(err) }
                    }
                    .padding()
                }
            }
            .navigationTitle("Mesh Exporter")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $pickingScan) { scanPickerSheet }
            .sheet(isPresented: $showShare) {
                if let url = mgr.exportedURL { ShareSheet(items: [url]) }
            }
            .onChange(of: mgr.exportedURL) { _, url in
                if url != nil { showShare = true }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Scan Card

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCE SCAN").font(.caption.bold()).foregroundColor(.secondary)
            Button { pickingScan = true } label: {
                HStack {
                    Image(systemName: "cube.fill")
                        .foregroundColor(selectedScan != nil ? ZDDesign.cyanAccent : ZDDesign.mediumGray)
                    VStack(alignment: .leading, spacing: 2) {
                        if let s = selectedScan {
                            Text(s.name.isEmpty ? scanLabel(s) : s.name)
                                .font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text("\(s.pointCount.formatted()) points")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("Tap to select scan").font(.subheadline).foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(ZDDesign.mediumGray)
                }
                .padding()
                .background(ZDDesign.darkBackground)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Config Card

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXPORT OPTIONS").font(.caption.bold()).foregroundColor(.secondary)

            HStack {
                Text("Format").font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Picker("", selection: $mgr.config.format) {
                    ForEach(PointCloudFormat.allCases) { f in
                        Label(f.rawValue, systemImage: f.icon).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voxel Downsample").font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                    Text(mgr.config.voxelDownsample == 0
                         ? "No downsampling"
                         : String(format: "%.3f m grid", mgr.config.voxelDownsample))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Stepper("", value: $mgr.config.voxelDownsample, in: 0.0...0.5, step: 0.01)
                    .labelsHidden()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bounds Clip").font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                    Text(mgr.config.boundsHalfExtent == 0
                         ? "No clipping"
                         : String(format: "±%.1f m cube", mgr.config.boundsHalfExtent))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Stepper("", value: $mgr.config.boundsHalfExtent, in: 0.0...50.0, step: 0.5)
                    .labelsHidden()
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Export Button

    private var exportButton: some View {
        Button {
            if let s = selectedScan { mgr.export(scan: s) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.headline.bold())
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedScan != nil ? ZDDesign.cyanAccent : ZDDesign.mediumGray)
                .cornerRadius(12)
        }
        .disabled(selectedScan == nil || mgr.isExporting)
    }

    private var exportingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent)
            Text("Exporting…").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func errorCard(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(ZDDesign.signalRed)
            Text(msg).font(.subheadline).foregroundColor(.secondary)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Scan Picker Sheet

    private var scanPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List(storage.savedScans) { scan in
                    Button {
                        selectedScan = scan
                        pickingScan = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scan.name.isEmpty ? scanLabel(scan) : scan.name)
                                .font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text("\(scan.pointCount.formatted()) pts · \(scan.mode)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func scanLabel(_ s: SavedScan) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: s.timestamp)
    }
}
