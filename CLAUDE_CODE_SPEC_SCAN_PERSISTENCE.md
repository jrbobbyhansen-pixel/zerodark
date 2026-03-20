# ZeroDark Scan Persistence & Library — Claude Code Implementation Spec

## Overview
Implement offline scan persistence and a library UI for saved LiDAR scans. All data stays on device. No cloud, no network.

## Current State
- `LiDARCaptureEngine.swift` already captures point clouds and mesh anchors
- `saveScanToDisk()` exists but is basic — saves to Documents/LiDARScans/{timestamp}/
- Current format: metadata.json + points.ply + scan.usdz
- `ScanGalleryView` exists but is a stub — needs full implementation
- `LiDARScanResult` struct holds scan data in memory

## Files to Modify/Create

### 1. Create: `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/ScanStorage.swift`

```swift
// ScanStorage.swift — Persistent scan storage manager

import Foundation
import UIKit
import CoreLocation

/// Represents a saved scan on disk
struct SavedScan: Identifiable, Codable {
    let id: UUID
    var name: String
    var notes: String
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let pointCount: Int
    let riskScore: Float?
    let scanMode: String
    
    // Computed paths (not stored)
    var directoryURL: URL {
        ScanStorage.scansDirectory.appendingPathComponent(id.uuidString)
    }
    var thumbnailURL: URL {
        directoryURL.appendingPathComponent("thumbnail.jpg")
    }
    var pointCloudURL: URL {
        directoryURL.appendingPathComponent("points.ply")
    }
    var meshURL: URL {
        directoryURL.appendingPathComponent("scan.usdz")
    }
    var metadataURL: URL {
        directoryURL.appendingPathComponent("metadata.json")
    }
}

@MainActor
final class ScanStorage: ObservableObject {
    static let shared = ScanStorage()
    
    static var scansDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiDARScans", isDirectory: true)
    }
    
    @Published var savedScans: [SavedScan] = []
    
    private init() {
        createDirectoryIfNeeded()
        loadScanIndex()
    }
    
    // MARK: - Directory Management
    
    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: Self.scansDirectory,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Save Scan
    
    func save(_ result: LiDARScanResult, name: String? = nil) -> SavedScan {
        let scanDir = Self.scansDirectory.appendingPathComponent(result.id.uuidString)
        try? FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
        
        // Create SavedScan record
        let scan = SavedScan(
            id: result.id,
            name: name ?? defaultName(for: result),
            notes: "",
            timestamp: result.timestamp,
            latitude: result.location?.latitude,
            longitude: result.location?.longitude,
            pointCount: result.pointCount,
            riskScore: result.tacticalAnalysis?.riskScore,
            scanMode: "tactical"  // or pull from config
        )
        
        // Save metadata
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(scan) {
            try? data.write(to: scan.metadataURL)
        }
        
        // Save point cloud as binary (faster than PLY for loading)
        savePointCloudBinary(result.pointCloud, to: scanDir.appendingPathComponent("points.bin"))
        
        // Also save PLY for interop
        savePointCloudPLY(result.pointCloud, to: scan.pointCloudURL)
        
        // Generate and save thumbnail
        if let thumbnail = generateThumbnail(from: result) {
            if let jpegData = thumbnail.jpegData(compressionQuality: 0.7) {
                try? jpegData.write(to: scan.thumbnailURL)
            }
        }
        
        // Update index
        savedScans.insert(scan, at: 0)
        saveIndex()
        
        return scan
    }
    
    // MARK: - Load Scan
    
    func loadPointCloud(for scan: SavedScan) -> [SIMD3<Float>]? {
        let binURL = scan.directoryURL.appendingPathComponent("points.bin")
        if FileManager.default.fileExists(atPath: binURL.path) {
            return loadPointCloudBinary(from: binURL)
        }
        // Fallback to PLY
        return loadPointCloudPLY(from: scan.pointCloudURL)
    }
    
    // MARK: - Delete Scan
    
    func delete(_ scan: SavedScan) {
        try? FileManager.default.removeItem(at: scan.directoryURL)
        savedScans.removeAll { $0.id == scan.id }
        saveIndex()
    }
    
    // MARK: - Update Scan
    
    func update(_ scan: SavedScan, name: String? = nil, notes: String? = nil) {
        guard let index = savedScans.firstIndex(where: { $0.id == scan.id }) else { return }
        
        if let name = name {
            savedScans[index].name = name
        }
        if let notes = notes {
            savedScans[index].notes = notes
        }
        
        // Re-save metadata
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(savedScans[index]) {
            try? data.write(to: savedScans[index].metadataURL)
        }
        
        saveIndex()
    }
    
    // MARK: - Index Management
    
    private func loadScanIndex() {
        // Scan directory for existing scans
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: Self.scansDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        savedScans = contents.compactMap { url -> SavedScan? in
            let metadataURL = url.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let scan = try? decoder.decode(SavedScan.self, from: data) else {
                return nil
            }
            return scan
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func saveIndex() {
        // Index is reconstructed from individual metadata files on load
        // This ensures consistency even if app crashes mid-save
    }
    
    // MARK: - Binary Point Cloud
    
    private func savePointCloudBinary(_ points: [SIMD3<Float>], to url: URL) {
        var data = Data()
        
        // Header: point count (UInt32)
        var count = UInt32(points.count)
        data.append(Data(bytes: &count, count: 4))
        
        // Points: packed SIMD3<Float> (12 bytes each)
        for point in points {
            var p = point
            data.append(Data(bytes: &p, count: 12))
        }
        
        try? data.write(to: url)
    }
    
    private func loadPointCloudBinary(from url: URL) -> [SIMD3<Float>]? {
        guard let data = try? Data(contentsOf: url), data.count >= 4 else { return nil }
        
        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(Int(count))
        
        let pointData = data.dropFirst(4)
        pointData.withUnsafeBytes { buffer in
            let floatBuffer = buffer.bindMemory(to: SIMD3<Float>.self)
            points.append(contentsOf: floatBuffer)
        }
        
        return points
    }
    
    private func savePointCloudPLY(_ points: [SIMD3<Float>], to url: URL) {
        var ply = """
        ply
        format ascii 1.0
        element vertex \(points.count)
        property float x
        property float y
        property float z
        end_header
        
        """
        for point in points {
            ply += "\(point.x) \(point.y) \(point.z)\n"
        }
        try? ply.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func loadPointCloudPLY(from url: URL) -> [SIMD3<Float>]? {
        guard let content = try? String(contentsOf: url) else { return nil }
        var points: [SIMD3<Float>] = []
        var inHeader = true
        
        for line in content.split(separator: "\n") {
            if inHeader {
                if line == "end_header" { inHeader = false }
                continue
            }
            let parts = line.split(separator: " ")
            if parts.count >= 3,
               let x = Float(parts[0]),
               let y = Float(parts[1]),
               let z = Float(parts[2]) {
                points.append(SIMD3(x, y, z))
            }
        }
        return points
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateThumbnail(from result: LiDARScanResult) -> UIImage? {
        // Render point cloud to image using Metal or SceneKit
        // For now, create a simple placeholder with point count
        let size = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        // Dark background
        UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1).setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        
        // Draw simplified point representation
        UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.6).setFill()
        for _ in 0..<min(500, result.pointCount) {
            let x = CGFloat.random(in: 20...180)
            let y = CGFloat.random(in: 20...180)
            UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 2, height: 2)).fill()
        }
        
        // Point count label
        let label = "\(result.pointCount.formatted())"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        (label as NSString).draw(at: CGPoint(x: 10, y: 175), withAttributes: attrs)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - Helpers
    
    private func defaultName(for result: LiDARScanResult) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Scan \(formatter.string(from: result.timestamp))"
    }
}
```

### 2. Create: `Sources/MLXEdgeLLM/App/ScanGalleryView.swift`

Replace the existing stub with a full implementation:

```swift
// ScanGalleryView.swift — Scan Library with Grid/List View

import SwiftUI

struct ScanGalleryView: View {
    @StateObject private var storage = ScanStorage.shared
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .dateDesc
    @State private var selectedScan: SavedScan?
    @State private var showingDeleteConfirm = false
    @State private var scanToDelete: SavedScan?
    @State private var editingScan: SavedScan?
    @State private var editName = ""
    @State private var editNotes = ""
    @Environment(\.dismiss) var dismiss
    
    enum ViewMode {
        case grid, list
    }
    
    enum SortOrder {
        case dateDesc, dateAsc, nameAsc, pointsDesc
    }
    
    var sortedScans: [SavedScan] {
        switch sortOrder {
        case .dateDesc:
            return storage.savedScans.sorted { $0.timestamp > $1.timestamp }
        case .dateAsc:
            return storage.savedScans.sorted { $0.timestamp < $1.timestamp }
        case .nameAsc:
            return storage.savedScans.sorted { $0.name < $1.name }
        case .pointsDesc:
            return storage.savedScans.sorted { $0.pointCount > $1.pointCount }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if storage.savedScans.isEmpty {
                    emptyState
                } else {
                    scanContent
                }
            }
            .navigationTitle("Scan Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("View", selection: $viewMode) {
                            Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                            Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                        }
                        Divider()
                        Picker("Sort", selection: $sortOrder) {
                            Text("Newest First").tag(SortOrder.dateDesc)
                            Text("Oldest First").tag(SortOrder.dateAsc)
                            Text("Name").tag(SortOrder.nameAsc)
                            Text("Points").tag(SortOrder.pointsDesc)
                        }
                    } label: {
                        Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                    }
                }
            }
            .sheet(item: $selectedScan) { scan in
                ScanDetailView(scan: scan)
            }
            .sheet(item: $editingScan) { scan in
                editSheet(for: scan)
            }
            .confirmationDialog(
                "Delete Scan?",
                isPresented: $showingDeleteConfirm,
                presenting: scanToDelete
            ) { scan in
                Button("Delete", role: .destructive) {
                    storage.delete(scan)
                }
            } message: { scan in
                Text("This will permanently delete \"\(scan.name)\" and all associated data.")
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "viewfinder.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Saved Scans")
                .font(.headline)
            Text("Completed scans will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var scanContent: some View {
        if viewMode == .grid {
            gridView
        } else {
            listView
        }
    }
    
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(sortedScans) { scan in
                    ScanGridCell(scan: scan)
                        .onTapGesture {
                            selectedScan = scan
                        }
                        .contextMenu {
                            contextMenuItems(for: scan)
                        }
                }
            }
            .padding()
        }
    }
    
    private var listView: some View {
        List {
            ForEach(sortedScans) { scan in
                ScanListRow(scan: scan)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedScan = scan
                    }
                    .contextMenu {
                        contextMenuItems(for: scan)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            storage.delete(scan)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingScan = scan
                            editName = scan.name
                            editNotes = scan.notes
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }
        }
        .listStyle(.plain)
    }
    
    @ViewBuilder
    private func contextMenuItems(for scan: SavedScan) -> some View {
        Button {
            selectedScan = scan
        } label: {
            Label("View", systemImage: "eye")
        }
        
        Button {
            editingScan = scan
            editName = scan.name
            editNotes = scan.notes
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        
        Divider()
        
        Button(role: .destructive) {
            scanToDelete = scan
            showingDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    private func editSheet(for scan: SavedScan) -> some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Scan name", text: $editName)
                }
                Section("Notes") {
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingScan = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        storage.update(scan, name: editName, notes: editNotes)
                        editingScan = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Grid Cell

struct ScanGridCell: View {
    let scan: SavedScan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let image = loadThumbnail() {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                    Image(systemName: "cube.fill")
                        .font(.largeTitle)
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .frame(height: 120)
            .cornerRadius(8)
            .clipped()
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                
                HStack {
                    Text("\(scan.pointCount.formatted()) pts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let risk = scan.riskScore {
                        riskBadge(risk)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
    
    private func loadThumbnail() -> UIImage? {
        guard let data = try? Data(contentsOf: scan.thumbnailURL) else { return nil }
        return UIImage(data: data)
    }
    
    private func riskBadge(_ risk: Float) -> some View {
        Text(risk < 0.3 ? "LOW" : risk < 0.7 ? "MED" : "HIGH")
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(risk < 0.3 ? Color.green : risk < 0.7 ? Color.yellow : Color.red)
            .cornerRadius(4)
    }
}

// MARK: - List Row

struct ScanListRow: View {
    let scan: SavedScan
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let image = loadThumbnail() {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.5)
                    Image(systemName: "cube.fill")
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            .clipped()
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.name)
                    .font(.headline)
                
                Text("\(scan.pointCount.formatted()) points")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(scan.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Risk indicator
            if let risk = scan.riskScore {
                VStack {
                    Image(systemName: risk < 0.3 ? "checkmark.shield" : risk < 0.7 ? "exclamationmark.triangle" : "xmark.shield")
                        .foregroundColor(risk < 0.3 ? .green : risk < 0.7 ? .yellow : .red)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func loadThumbnail() -> UIImage? {
        guard let data = try? Data(contentsOf: scan.thumbnailURL) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Detail View (Placeholder for Module 3+)

struct ScanDetailView: View {
    let scan: SavedScan
    @StateObject private var storage = ScanStorage.shared
    @State private var pointCloud: [SIMD3<Float>]?
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading scan...")
                } else if let points = pointCloud {
                    // 3D viewer will go here (Module 3+)
                    VStack {
                        Text("\(points.count.formatted()) points loaded")
                            .font(.headline)
                        Text("3D viewer coming in Module 3")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Failed to load scan")
                        .foregroundColor(.red)
                }
            }
            .navigationTitle(scan.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                Task {
                    pointCloud = storage.loadPointCloud(for: scan)
                    isLoading = false
                }
            }
        }
    }
}
```

### 3. Modify: `LiDARCaptureEngine.swift`

Update `saveScanToDisk` to use the new `ScanStorage`:

```swift
// Replace the existing saveScanToDisk method with:

private func saveScanToDisk(_ result: LiDARScanResult) {
    Task { @MainActor in
        let _ = ScanStorage.shared.save(result)
        print("[ZeroDark] Scan saved via ScanStorage")
    }
}
```

### 4. Modify: `LiDARTabView.swift`

The sheet already presents `ScanGalleryView()` — just ensure it's imported correctly.

## Build Verification

After implementing:
1. Build should succeed with no errors
2. Scan library should show existing scans from Documents/LiDARScans/
3. New scans should appear in library immediately after stopping
4. Swipe to delete should work
5. Tap to view should show point count (3D viewer is placeholder for now)

## File Structure After Implementation

```
Sources/MLXEdgeLLM/
├── App/
│   ├── LiDARTabView.swift (modified)
│   └── ScanGalleryView.swift (replaced)
└── SpatialIntelligence/
    └── LiDAR/
        ├── LiDARCaptureEngine.swift (modified)
        └── ScanStorage.swift (new)
```

## Notes
- Binary format for fast loading (12 bytes per point vs ~30 for ASCII PLY)
- PLY also saved for interop with external tools (MeshLab, CloudCompare)
- Thumbnail generation is basic — can enhance with Metal point rendering later
- ScanDetailView is a placeholder — will be expanded in Module 3 (Measurement Tools)
