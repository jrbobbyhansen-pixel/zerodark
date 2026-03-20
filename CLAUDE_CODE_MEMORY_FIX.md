# ZeroDark Memory Fix — CRITICAL

## Problem
Two separate memory issues:
1. **Point accumulation during capture** — 50M cap = 600MB, iOS kills before stop
2. **Scan history retention** — `scanHistory: [LiDARScanResult]` retains ALL point clouds forever

## Problem 2 Details (the sneaky one)
```swift
@Published var scanHistory: [LiDARScanResult] = []
```
Each `LiDARScanResult` contains:
- `pointCloud: [SIMD3<Float>]` — full point array
- `meshAnchors: [ARMeshAnchor]` — full mesh data
- `depthMap: CVPixelBuffer?`
- `confidenceMap: CVPixelBuffer?`

Scan once = 100MB+ retained. Scan twice = 200MB+. Never freed.

## Fix for Problem 2: Lightweight Scan History

### Option A: Clear history after save
```swift
// In stopScan(), after saving:
lastScanResult = result  // Keep only the most recent
scanHistory = []  // Clear history
```

### Option B: Store metadata only (better)
Create lightweight struct:
```swift
struct ScanHistoryEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let pointCount: Int
    let boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    let scanDirURL: URL  // Path to saved scan on disk
    // NO pointCloud, NO meshAnchors, NO depthMap
}

@Published var scanHistory: [ScanHistoryEntry] = []  // Metadata only
@Published var currentScan: LiDARScanResult?  // Only current scan in memory
```

When user wants to view a past scan, load from disk.

---

## Problem 3: Terrain/Maps Path Mismatch (BUG)

**Files transferred via Finder appear at:** App container root (e.g., `ZeroDark/SRTM/`)
**TerrainEngine looks in:** `Documents/SRTM/`
**OfflineDataView looks in:** `Documents/Terrain/`

User drags files into ZeroDark folder → they land at container root → app can't find them.

### Fix: Look in BOTH locations

In `TerrainEngine.swift`, update `loadTile`:
```swift
private func loadTile(named name: String) -> TerrainTile? {
    if let cached = cachedTiles[name] { return cached }
    
    // Try multiple locations for the HGT file
    let possiblePaths = [
        // Documents/SRTM/ (original)
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SRTM/\(name).hgt"),
        // Documents/Terrain/ (OfflineDataView path)
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Terrain/\(name).hgt"),
        // App container root /SRTM/ (Finder drag location)
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("SRTM/\(name).hgt"),
        // App container root /Terrain/
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Terrain/\(name).hgt")
    ]
    
    for path in possiblePaths {
        if FileManager.default.fileExists(atPath: path.path),
           let data = try? Data(contentsOf: path),
           let tile = try? parseHGT(data: data, name: name) {
            cachedTiles[name] = tile
            return tile
        }
    }
    
    return nil
}
```

Also update `OfflineDataView` to scan both locations for display.

### Same fix needed for OfflineTileProvider.swift

Maps have same issue: looks in `Documents/OfflineMaps/` but files are at container root.

In `loadOfflineMaps()`:
```swift
private func loadOfflineMaps() {
    let fileManager = FileManager.default
    mbtilesReaders.removeAll()
    
    // Check multiple possible locations
    let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let containerRoot = documentsDir.deletingLastPathComponent()
    
    let possibleDirs = [
        documentsDir.appendingPathComponent("OfflineMaps"),
        documentsDir.appendingPathComponent("Maps"),
        containerRoot.appendingPathComponent("OfflineMaps"),
        containerRoot.appendingPathComponent("Maps")
    ]
    
    for mapsDir in possibleDirs {
        guard fileManager.fileExists(atPath: mapsDir.path) else { continue }
        
        let files = (try? fileManager.contentsOfDirectory(at: mapsDir, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let ext = file.pathExtension.lowercased()
            let name = file.deletingPathExtension().lastPathComponent
            
            if ext == "mbtiles", mbtilesReaders[name] == nil {
                if let reader = try? MBTilesReader(path: file.path) {
                    mbtilesReaders[name] = reader
                    print("[ZeroDark] Loaded mbtiles: \(name) from \(mapsDir.lastPathComponent)")
                }
            }
        }
    }
    
    print("[ZeroDark] Total offline maps loaded: \(mbtilesReaders.count)")
}
```

---

## Solution: Stream to Disk During Capture

### Changes to LiDARCaptureEngine.swift

#### 1. Lower the cap drastically
```swift
// OLD
private let maxPointCount = 50_000_000  // 600MB

// NEW
private let maxPointCount = 10_000_000  // 120MB - still 10M points, plenty for room
```

#### 2. Add streaming file handle
```swift
// Add properties
private var pointStreamURL: URL?
private var pointStreamHandle: FileHandle?
private var streamedPointCount: Int = 0
```

#### 3. Initialize stream on scan start
In `startScan()`, add:
```swift
// Create temp file for point streaming
let tempDir = FileManager.default.temporaryDirectory
pointStreamURL = tempDir.appendingPathComponent("scan_\(UUID().uuidString).points")
FileManager.default.createFile(atPath: pointStreamURL!.path, contents: nil)
pointStreamHandle = try? FileHandle(forWritingTo: pointStreamURL!)
streamedPointCount = 0

// Write header (point count placeholder - will update at end)
var placeholder: UInt32 = 0
pointStreamHandle?.write(Data(bytes: &placeholder, count: 4))
```

#### 4. Stream points to disk during capture
Replace the point accumulation in the ARSession delegate:
```swift
// OLD - accumulates in RAM forever
self.collectedPoints.append(contentsOf: newPoints)

// NEW - stream to disk, keep only recent in RAM for preview
self.streamPointsToDisk(newPoints)
```

Add streaming method:
```swift
private func streamPointsToDisk(_ points: [SIMD3<Float>]) {
    guard let handle = pointStreamHandle else { return }
    
    // Write points directly to file
    var data = Data(capacity: points.count * 12)
    for point in points {
        var p = point
        data.append(Data(bytes: &p, count: 12))
    }
    handle.write(data)
    streamedPointCount += points.count
    
    // Keep only last 100K points in RAM for live preview
    collectedPoints.append(contentsOf: points)
    if collectedPoints.count > 100_000 {
        collectedPoints.removeFirst(collectedPoints.count - 100_000)
    }
    
    // Update displayed count
    currentPointCount = streamedPointCount
}
```

#### 5. Finalize stream on stop
In `stopScan()`:
```swift
// Finalize point stream - update header with actual count
if let handle = pointStreamHandle, let url = pointStreamURL {
    // Seek to start and write actual count
    handle.seek(toFileOffset: 0)
    var count = UInt32(streamedPointCount)
    handle.write(Data(bytes: &count, count: 4))
    try? handle.close()
    
    // Move to final location
    let finalURL = scanDir.appendingPathComponent("points.bin")
    try? FileManager.default.moveItem(at: url, to: finalURL)
}
pointStreamHandle = nil
pointStreamURL = nil
```

#### 6. Don't pass points array to result
```swift
// OLD - copies 600MB array
let result = LiDARScanResult(
    pointCloud: collectedPoints,  // BIG COPY
    ...
)

// NEW - points are already on disk
let result = LiDARScanResult(
    pointCloud: [],  // Empty - points are streamed to disk
    pointCount: streamedPointCount,
    ...
)
```

#### 7. Update LiDARScanResult
Make `pointCloud` optional or accept empty array:
```swift
struct LiDARScanResult {
    // Points now live on disk, not in struct
    let pointCloudURL: URL?  // Path to points.bin
    let pointCount: Int
    // ... rest unchanged
}
```

### Memory Budget After Fix

| Item | Before | After |
|------|--------|-------|
| Point accumulation | 600MB (50M) | 1.2MB (100K preview) |
| Mesh anchors | ~200MB | ~200MB (unchanged) |
| Total RAM | ~1GB+ | ~250MB |

### Key Insight
The original design accumulated all points in RAM. The fix:
1. Streams points directly to disk during capture
2. Keeps only 100K most recent points for live preview
3. Never builds giant arrays
4. Points are already saved when scan stops

### Testing
1. Start scan → watch Memory in Xcode debugger
2. Should stay under 300MB even after 10+ minutes
3. Stop scan → should NOT spike memory
4. Gallery shows scan with correct point count
