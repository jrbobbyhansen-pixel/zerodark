# ZeroDark LiDAR Persistence & Library Spec
**Version:** 1.0  
**Date:** 2026-03-20  
**Target:** Fully offline scan storage, retrieval, and management

---

## Overview

Two modules that work together to enable the core ZeroDark value prop: **scan once, analyze forever**.

| Module | Purpose | Deliverable |
|--------|---------|-------------|
| **1. Scan Persistence** | Save/load/delete scans with full metadata | `ScanStore.swift` |
| **2. Scan Library** | Browse, search, manage saved scans | `ScanGalleryView.swift` (enhanced) |

---

## Module 1: Scan Persistence (`ScanStore.swift`)

### Storage Structure

```
Documents/
└── LiDARScans/
    └── 2026-03-20T06-45-00Z/          # ISO8601 timestamp (colons replaced)
        ├── metadata.json               # Scan metadata + analysis summary
        ├── points.ply                  # Point cloud (ASCII PLY)
        ├── scan.usdz                   # Mesh for 3D viewer
        └── thumbnail.jpg               # 256x256 preview image
```

### Metadata Schema (`metadata.json`)

```swift
struct ScanMetadata: Codable {
    let id: UUID
    let timestamp: Date
    let name: String                    // User-editable, defaults to location or "Scan 1"
    let notes: String                   // User-editable notes
    
    // Location
    let latitude: Double?
    let longitude: Double?
    let heading: Double?
    let mgrs: String?                   // Pre-computed MGRS string
    
    // Scan stats
    let pointCount: Int
    let scanDuration: TimeInterval
    let boundingBoxMin: [Float]         // [x, y, z]
    let boundingBoxMax: [Float]         // [x, y, z]
    
    // Analysis summary (computed once, stored)
    let riskScore: Float?
    let surfaceCount: Int?
    let entryPointCount: Int?
    let coverPositionCount: Int?
    let observationPostCount: Int?
    
    // File references
    let hasPLY: Bool
    let hasUSDZ: Bool
    let hasThumbnail: Bool
    
    // User-added annotations count
    let annotationCount: Int
}
```

### ScanStore API

```swift
@MainActor
final class ScanStore: ObservableObject {
    static let shared = ScanStore()
    
    @Published var scans: [ScanMetadata] = []
    @Published var isLoading = false
    
    private let scansDirectory: URL
    
    // MARK: - CRUD Operations
    
    /// Load all scan metadata from disk (call on app launch)
    func loadAllScans() async
    
    /// Save a new scan result to disk
    /// - Returns: The saved metadata with assigned directory
    func save(_ result: LiDARScanResult, name: String?) async throws -> ScanMetadata
    
    /// Load full scan result from disk (for viewing/analysis)
    func load(id: UUID) async throws -> LiDARScanResult
    
    /// Load just the point cloud (for measurement tools)
    func loadPointCloud(id: UUID) async throws -> [SIMD3<Float>]
    
    /// Update metadata (name, notes)
    func update(id: UUID, name: String?, notes: String?) async throws
    
    /// Delete scan and all associated files
    func delete(id: UUID) async throws
    
    /// Delete multiple scans
    func delete(ids: Set<UUID>) async throws
    
    // MARK: - Thumbnails
    
    /// Generate thumbnail from current AR view
    func generateThumbnail(from arView: ARView) -> UIImage?
    
    /// Load thumbnail for scan
    func thumbnail(for id: UUID) -> UIImage?
    
    // MARK: - Export
    
    /// Get file URL for sharing (PLY or USDZ)
    func exportURL(for id: UUID, format: ExportFormat) -> URL?
    
    enum ExportFormat {
        case ply
        case usdz
    }
    
    // MARK: - Queries
    
    /// Scans sorted by date (newest first)
    var sortedByDate: [ScanMetadata] { get }
    
    /// Scans sorted by name
    var sortedByName: [ScanMetadata] { get }
    
    /// Scans filtered by risk level
    func scans(riskLevel: RiskLevel) -> [ScanMetadata]
    
    /// Search by name or notes
    func search(query: String) -> [ScanMetadata]
    
    /// Total storage used by all scans
    var totalStorageBytes: Int64 { get }
}
```

### Thumbnail Generation

Capture thumbnail at scan completion:

```swift
extension LiDARCaptureEngine {
    func captureSnapshot() -> UIImage? {
        guard let arView = arView else { return nil }
        
        // Render current AR view to image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        return renderer.image { context in
            arView.drawHierarchy(in: CGRect(x: 0, y: 0, width: 256, height: 256), afterScreenUpdates: true)
        }
    }
}
```

### Integration with Existing Code

Update `LiDARCaptureEngine.stopScan()`:

```swift
func stopScan() {
    isScanning = false
    arSession?.pause()
    
    guard let startTime = scanStartTime else { return }
    
    // Capture thumbnail BEFORE pausing AR session
    let thumbnail = captureSnapshot()
    
    // ... existing result compilation ...
    
    // Save through ScanStore instead of direct saveToDisk
    Task {
        do {
            let metadata = try await ScanStore.shared.save(result, name: nil)
            if let thumbnail = thumbnail {
                ScanStore.shared.saveThumbnail(thumbnail, for: metadata.id)
            }
        } catch {
            print("[ZeroDark] Failed to save scan: \(error)")
        }
        
        await analyzeResult(result)
    }
}
```

---

## Module 2: Scan Library (`ScanGalleryView.swift`)

### UI Layout

```
┌─────────────────────────────────────────────────────┐
│  LiDAR Scans                          [Grid] [List] │
├─────────────────────────────────────────────────────┤
│  🔍 Search scans...                                 │
├─────────────────────────────────────────────────────┤
│  Sort: [Date ▼] [Name] [Risk]                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐             │
│  │ 📸      │  │ 📸      │  │ 📸      │             │
│  │         │  │         │  │         │             │
│  ├─────────┤  ├─────────┤  ├─────────┤             │
│  │Ranch N  │  │Barn     │  │Trail 1  │             │
│  │LOW RISK │  │ELEVATED │  │LOW RISK │             │
│  │2h ago   │  │Yesterday│  │Mar 15   │             │
│  └─────────┘  └─────────┘  └─────────┘             │
│                                                     │
│  Storage: 156 MB (12 scans)                         │
└─────────────────────────────────────────────────────┘
```

### View Implementation

```swift
struct ScanGalleryView: View {
    @StateObject private var store = ScanStore.shared
    @State private var searchText = ""
    @State private var sortMode: SortMode = .date
    @State private var viewMode: ViewMode = .grid
    @State private var selectedScan: ScanMetadata?
    @State private var showingDeleteConfirm = false
    @State private var scansToDelete: Set<UUID> = []
    @State private var isEditMode = false
    
    enum SortMode: String, CaseIterable {
        case date = "Date"
        case name = "Name"
        case risk = "Risk"
    }
    
    enum ViewMode {
        case grid
        case list
    }
    
    var filteredScans: [ScanMetadata] {
        var scans = store.scans
        
        // Search filter
        if !searchText.isEmpty {
            scans = scans.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort
        switch sortMode {
        case .date:
            scans.sort { $0.timestamp > $1.timestamp }
        case .name:
            scans.sort { $0.name < $1.name }
        case .risk:
            scans.sort { ($0.riskScore ?? 0) > ($1.riskScore ?? 0) }
        }
        
        return scans
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Sort controls
                sortControls
                
                // Content
                if store.isLoading {
                    ProgressView("Loading scans...")
                } else if filteredScans.isEmpty {
                    emptyState
                } else {
                    switch viewMode {
                    case .grid:
                        gridView
                    case .list:
                        listView
                    }
                }
                
                // Storage footer
                storageFooter
            }
            .navigationTitle("LiDAR Scans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditMode ? "Done" : "Edit") {
                        isEditMode.toggle()
                        if !isEditMode {
                            scansToDelete.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    viewModeToggle
                }
            }
            .sheet(item: $selectedScan) { scan in
                ScanDetailView(scan: scan)
            }
            .confirmationDialog(
                "Delete \(scansToDelete.count) scan(s)?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await store.delete(ids: scansToDelete)
                        scansToDelete.removeAll()
                        isEditMode = false
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await store.loadAllScans()
        }
    }
    
    // MARK: - Subviews
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search scans...", text: $searchText)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding()
    }
    
    private var sortControls: some View {
        HStack {
            Text("Sort:")
                .foregroundColor(.secondary)
            ForEach(SortMode.allCases, id: \.self) { mode in
                Button {
                    sortMode = mode
                } label: {
                    Text(mode.rawValue)
                        .fontWeight(sortMode == mode ? .bold : .regular)
                }
                .buttonStyle(.bordered)
                .tint(sortMode == mode ? ZDDesign.cyanAccent : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(filteredScans, id: \.id) { scan in
                    ScanGridCell(
                        scan: scan,
                        isSelected: scansToDelete.contains(scan.id),
                        isEditMode: isEditMode
                    )
                    .onTapGesture {
                        if isEditMode {
                            if scansToDelete.contains(scan.id) {
                                scansToDelete.remove(scan.id)
                            } else {
                                scansToDelete.insert(scan.id)
                            }
                        } else {
                            selectedScan = scan
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var listView: some View {
        List(filteredScans, id: \.id) { scan in
            ScanListRow(scan: scan)
                .onTapGesture {
                    selectedScan = scan
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            try? await store.delete(id: scan.id)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No scans yet")
                .font(.headline)
            Text("Tap QUICK SCAN to capture your first LiDAR scan")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var storageFooter: some View {
        HStack {
            Text("Storage: \(ByteCountFormatter.string(fromByteCount: store.totalStorageBytes, countStyle: .file))")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("(\(filteredScans.count) scans)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if isEditMode && !scansToDelete.isEmpty {
                Button("Delete \(scansToDelete.count)") {
                    showingDeleteConfirm = true
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.95))
    }
    
    private var viewModeToggle: some View {
        Button {
            viewMode = viewMode == .grid ? .list : .grid
        } label: {
            Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
        }
    }
}

// MARK: - Grid Cell

struct ScanGridCell: View {
    let scan: ScanMetadata
    let isSelected: Bool
    let isEditMode: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                if let thumbnail = ScanStore.shared.thumbnail(for: scan.id) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 80)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 100, height: 80)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "cube.fill")
                                .foregroundColor(.secondary)
                        )
                }
                
                if isEditMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? ZDDesign.cyanAccent : .secondary)
                        .padding(4)
                }
            }
            
            // Name
            Text(scan.name)
                .font(.caption.bold())
                .lineLimit(1)
            
            // Risk badge
            if let risk = scan.riskScore {
                Text(riskLabel(risk))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(riskColor(risk).opacity(0.2))
                    .foregroundColor(riskColor(risk))
                    .cornerRadius(4)
            }
            
            // Date
            Text(scan.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? ZDDesign.cyanAccent : Color.clear, lineWidth: 2)
        )
    }
    
    private func riskLabel(_ score: Float) -> String {
        score < 0.3 ? "LOW" : score < 0.7 ? "ELEVATED" : "HIGH"
    }
    
    private func riskColor(_ score: Float) -> Color {
        score < 0.3 ? .green : score < 0.7 ? .yellow : .red
    }
}

// MARK: - List Row

struct ScanListRow: View {
    let scan: ScanMetadata
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnail = ScanStore.shared.thumbnail(for: scan.id) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .overlay(
                        Image(systemName: "cube.fill")
                            .foregroundColor(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.name)
                    .font(.headline)
                
                HStack {
                    Text("\(scan.pointCount.formatted()) pts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let surfaces = scan.surfaceCount {
                        Text("• \(surfaces) surfaces")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(scan.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Risk indicator
            if let risk = scan.riskScore {
                Circle()
                    .fill(riskColor(risk))
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func riskColor(_ score: Float) -> Color {
        score < 0.3 ? .green : score < 0.7 ? .yellow : .red
    }
}
```

### Scan Detail View (for rename/notes/delete)

```swift
struct ScanDetailView: View {
    let scan: ScanMetadata
    @Environment(\.dismiss) var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var showingViewer = false
    @State private var showingDeleteConfirm = false
    
    init(scan: ScanMetadata) {
        self.scan = scan
        _name = State(initialValue: scan.name)
        _notes = State(initialValue: scan.notes)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    
                    if let mgrs = scan.mgrs {
                        HStack {
                            Text("Location")
                            Spacer()
                            Text(mgrs)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Points")
                        Spacer()
                        Text(scan.pointCount.formatted())
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(Duration.seconds(scan.scanDuration).formatted())
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                Section("Analysis Summary") {
                    if let surfaces = scan.surfaceCount {
                        Label("\(surfaces) surfaces", systemImage: "square.3.layers.3d")
                    }
                    if let entries = scan.entryPointCount {
                        Label("\(entries) entry points", systemImage: "door.right.hand.open")
                    }
                    if let cover = scan.coverPositionCount {
                        Label("\(cover) cover positions", systemImage: "shield.fill")
                    }
                    if let ops = scan.observationPostCount {
                        Label("\(ops) observation posts", systemImage: "binoculars.fill")
                    }
                }
                
                Section {
                    Button {
                        showingViewer = true
                    } label: {
                        Label("View 3D Model", systemImage: "cube")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Scan", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Scan Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            try? await ScanStore.shared.update(
                                id: scan.id,
                                name: name,
                                notes: notes
                            )
                            dismiss()
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingViewer) {
                Scan3DViewer(scanId: scan.id)
            }
            .confirmationDialog(
                "Delete this scan?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await ScanStore.shared.delete(id: scan.id)
                        dismiss()
                    }
                }
            }
        }
    }
}
```

---

## Implementation Checklist

### Module 1: Scan Persistence
- [ ] Create `ScanStore.swift` with published scans array
- [ ] Implement `loadAllScans()` — scan Documents/LiDARScans/ for metadata.json files
- [ ] Implement `save()` — move from `LiDARCaptureEngine.saveScanToDisk()`
- [ ] Implement `load()` — load PLY back into `[SIMD3<Float>]`
- [ ] Implement `update()` — rewrite metadata.json
- [ ] Implement `delete()` — remove directory
- [ ] Add thumbnail capture before AR session pauses
- [ ] Add thumbnail caching (NSCache)
- [ ] Calculate total storage bytes

### Module 2: Scan Library
- [ ] Enhance `ScanGalleryView` with grid/list modes
- [ ] Add search functionality
- [ ] Add sort by date/name/risk
- [ ] Add multi-select delete in edit mode
- [ ] Add swipe-to-delete in list mode
- [ ] Create `ScanGridCell` component
- [ ] Create `ScanListRow` component
- [ ] Create `ScanDetailView` for rename/notes
- [ ] Add storage footer
- [ ] Wire to existing `LiDARTabView` sheet presentation

---

## File Locations

```
Sources/MLXEdgeLLM/
├── SpatialIntelligence/
│   └── LiDAR/
│       ├── LiDARCaptureEngine.swift  # Updated: use ScanStore
│       └── ScanStore.swift           # NEW: persistence layer
└── App/
    ├── LiDARTabView.swift            # Updated: sheet presentation
    └── ScanGalleryView.swift         # Enhanced: full library UI
```

---

## Testing

1. **Save scan** → Verify files created in Documents/LiDARScans/
2. **Kill app, relaunch** → Scans persist and reload
3. **Rename scan** → Name updates in library and metadata.json
4. **Delete scan** → Directory removed, library updates
5. **Search** → Filters by name and notes
6. **Sort** → Date/Name/Risk all work correctly
7. **Thumbnail** → Shows in grid, handles missing gracefully

---

## Next Modules (Future Specs)

- **Module 3: Measurement Tools** — tap-to-measure, area calculation
- **Module 4: Tactical Annotations** — mark cover, routes, hazards
- **Module 5: View Modes** — plan view, profile cuts
- **Module 6: Change Detection** — diff two scans
- **Module 7: Relocation** — terrain matching for navigation
