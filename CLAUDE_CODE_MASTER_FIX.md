# ZeroDark Master Fix — Critical Stability + Camera + UX

## Priority Order
1. **CRITICAL:** Stop scan crash (blocks all LiDAR use)
2. **HIGH:** Camera feeds not working (core feature broken)
3. **MEDIUM:** Scan list UX improvements

---

# PART 1: LiDAR Crash Fixes

## Problem
64M point scan crashes on stop. Root cause: synchronous PLY export building 2GB ASCII string on main thread.

## Fix 1.1: Async Background Save

**File:** `LiDARCaptureEngine.swift`

Replace `stopScan()`:

```swift
func stopScan() {
    // 1. Stop capturing immediately
    isScanning = false
    arSession?.pause()
    
    guard let startTime = scanStartTime else { return }
    
    // 2. Capture data before clearing (avoid race conditions)
    let points = collectedPoints
    let anchors = meshAnchors
    let location = currentLocation
    let heading = currentHeading
    
    // 3. Clear capture arrays to free memory
    collectedPoints = []
    meshAnchors = []
    
    // 4. Build result
    let result = LiDARScanResult(
        timestamp: Date(),
        location: location,
        heading: heading,
        pointCloud: points,
        meshAnchors: anchors,
        depthMap: nil,  // Don't access session after pause
        confidenceMap: nil,
        scanDuration: Date().timeIntervalSince(startTime),
        pointCount: points.count,
        boundingBox: calculateBoundingBox(from: points)
    )
    
    lastScanResult = result
    analysisStatus = "Scan complete. Saving..."
    
    // 5. ASYNC save - does NOT block UI
    Task.detached(priority: .userInitiated) { [weak self] in
        await self?.saveScanAsync(result)
    }
}

// New helper for bounding box
private func calculateBoundingBox(from points: [SIMD3<Float>]) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
    guard let first = points.first else { return nil }
    var minP = first
    var maxP = first
    for point in points {
        minP = min(minP, point)
        maxP = max(maxP, point)
    }
    return (minP, maxP)
}
```

## Fix 1.2: Async Save Implementation

Add new method:

```swift
private func saveScanAsync(_ result: LiDARScanResult) async {
    let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LiDARScans", isDirectory: true)
    
    let scanDir = scansDir.appendingPathComponent(result.id.uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
    
    // 1. Save metadata (fast, always succeeds)
    await saveMetadataAsync(result, to: scanDir)
    
    // 2. Save points as binary (fast, streaming)
    await MainActor.run { analysisStatus = "Saving points..." }
    do {
        try await savePointsBinary(result.pointCloud, to: scanDir.appendingPathComponent("points.bin"))
    } catch {
        print("[ZeroDark] Points save failed: \(error)")
    }
    
    // 3. Export USDZ (slower, but async)
    await MainActor.run { analysisStatus = "Exporting 3D model..." }
    do {
        try await exportMeshToUSDZAsync(result.meshAnchors, to: scanDir.appendingPathComponent("scan.usdz"))
    } catch {
        print("[ZeroDark] USDZ export failed: \(error)")
    }
    
    // 4. Refresh gallery
    await MainActor.run {
        ScanStorage.shared.loadScanIndex()
        analysisStatus = "Saved"
    }
    
    // 5. Run analysis
    await analyzeResult(result)
}

private func saveMetadataAsync(_ result: LiDARScanResult, to dir: URL) async {
    struct Meta: Codable {
        let id: String
        let timestamp: Date
        let lat, lon: Double?
        let pointCount: Int
    }
    
    let meta = Meta(
        id: result.id.uuidString,
        timestamp: result.timestamp,
        lat: result.location?.latitude,
        lon: result.location?.longitude,
        pointCount: result.pointCount
    )
    
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(meta) {
        try? data.write(to: dir.appendingPathComponent("metadata.json"))
    }
}
```

## Fix 1.3: Binary Point Save (Not ASCII)

Replace `exportPointCloudToPLY`:

```swift
/// Save points as binary (100x faster than ASCII PLY)
private func savePointsBinary(_ points: [SIMD3<Float>], to url: URL) async throws {
    guard !points.isEmpty else { return }
    
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    
    // Header: point count
    var count = UInt32(points.count)
    handle.write(Data(bytes: &count, count: 4))
    
    // Write in 1MB chunks to avoid memory spike
    let chunkSize = 85_000  // ~1MB per chunk
    for chunkStart in stride(from: 0, to: points.count, by: chunkSize) {
        let chunkEnd = min(chunkStart + chunkSize, points.count)
        let slice = points[chunkStart..<chunkEnd]
        
        var data = Data(capacity: slice.count * 12)
        for point in slice {
            var p = point
            data.append(Data(bytes: &p, count: 12))
        }
        handle.write(data)
        
        // Yield to keep system responsive
        await Task.yield()
    }
    
    try handle.close()
    print("[ZeroDark] Saved \(points.count) points as binary")
}
```

## Fix 1.4: Async USDZ Export

```swift
private func exportMeshToUSDZAsync(_ anchors: [ARMeshAnchor], to url: URL) async throws {
    guard !anchors.isEmpty else { return }
    
    // Build SceneKit scene from mesh anchors
    let scene = SCNScene()
    
    for anchor in anchors {
        guard let geometry = buildGeometry(from: anchor) else { continue }
        let node = SCNNode(geometry: geometry)
        node.simdTransform = anchor.transform
        scene.rootNode.addChildNode(node)
    }
    
    // Export to USDZ (this is the slow part)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        scene.write(to: url, options: nil, delegate: nil) { progress, error, stop in
            if let error = error {
                continuation.resume(throwing: error)
            } else if progress >= 1.0 {
                continuation.resume()
            }
        }
    }
    
    print("[ZeroDark] USDZ exported")
}

private func buildGeometry(from anchor: ARMeshAnchor) -> SCNGeometry? {
    let meshGeometry = anchor.geometry
    
    let vertexSource = SCNGeometrySource(
        buffer: meshGeometry.vertices.buffer,
        vertexFormat: meshGeometry.vertices.format,
        semantic: .vertex,
        vertexCount: meshGeometry.vertices.count,
        dataOffset: meshGeometry.vertices.offset,
        dataStride: meshGeometry.vertices.stride
    )
    
    let faceData = Data(
        bytes: meshGeometry.faces.buffer.contents(),
        count: meshGeometry.faces.buffer.length
    )
    let faceElement = SCNGeometryElement(
        data: faceData,
        primitiveType: .triangles,
        primitiveCount: meshGeometry.faces.count,
        bytesPerIndex: meshGeometry.faces.bytesPerIndex
    )
    
    let geometry = SCNGeometry(sources: [vertexSource], elements: [faceElement])
    
    let material = SCNMaterial()
    material.diffuse.contents = UIColor(red: 0.1, green: 0.4, blue: 0.15, alpha: 1.0)
    material.isDoubleSided = true
    geometry.materials = [material]
    
    return geometry
}
```

## Fix 1.5: Memory Cap + Warning

Add to capture loop:

```swift
private let maxPointCount = 50_000_000  // 50M = 600MB, safe limit
private var hasWarnedPointLimit = false

// In the delegate where points are collected:
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // ... existing code ...
    
    // Check memory limit before adding more points
    if collectedPoints.count >= maxPointCount {
        if !hasWarnedPointLimit {
            hasWarnedPointLimit = true
            Task { @MainActor in
                analysisStatus = "⚠️ Point limit reached (50M). Stop scan to save."
            }
        }
        return  // Stop collecting
    }
    
    collectedPoints.append(contentsOf: newPoints)
    // ... rest of existing code ...
}
```

## Fix 1.6: Remove/Update Old PLY Export

Delete or comment out the old synchronous `exportPointCloudToPLY` function. If PLY format is still needed for export/sharing, make it async and streaming like the binary version.

---

# PART 2: Camera Feed Fixes

## Problem
1. Only 8 hardcoded cameras (3 in San Antonio)
2. All TxDOT URLs return 404 - they're fake/placeholder
3. No real API integration

## Fix 2.1: Replace Hardcoded Cameras with Real TxDOT API

**File:** `TrafficCamService.swift`

Replace `fetchTxDOTCameras()` and `txdotSanAntonioCameras()` with actual API call:

```swift
/// Fetch real TxDOT cameras from DriveTexas API
private func fetchTxDOTCameras() async -> [TrafficCamera] {
    // TxDOT uses ArcGIS REST API for camera data
    // San Antonio district cameras endpoint
    let sanAntonioURL = "https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_CCTV_Cameras/FeatureServer/0/query?where=DISTRICT%3D%27SAN%27&outFields=*&f=json"
    
    // Also fetch statewide for nearby detection
    let statewideURL = "https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_CCTV_Cameras/FeatureServer/0/query?where=1%3D1&outFields=*&f=json"
    
    var allCameras: [TrafficCamera] = []
    
    // Try statewide first
    if let url = URL(string: statewideURL) {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let cameras = parseTxDOTResponse(data)
            allCameras.append(contentsOf: cameras)
            print("[CamService] Fetched \(cameras.count) TxDOT cameras")
        } catch {
            print("[CamService] TxDOT fetch failed: \(error)")
        }
    }
    
    // If API fails, return cached or fallback
    if allCameras.isEmpty {
        allCameras = loadCachedTxDOTCameras()
    }
    
    return allCameras
}

/// Parse TxDOT ArcGIS response
private func parseTxDOTResponse(_ data: Data) -> [TrafficCamera] {
    struct ArcGISResponse: Codable {
        let features: [Feature]?
        
        struct Feature: Codable {
            let attributes: Attributes?
            let geometry: Geometry?
            
            struct Attributes: Codable {
                let OBJECTID: Int?
                let CCTV_ID: String?
                let LOCATION: String?
                let ROADWAY: String?
                let CROSS_ST: String?
                let CITY: String?
                let DISTRICT: String?
                let ACTIVE: Int?
                let SNAPSHOT_URL: String?
                let STREAM_URL: String?
            }
            
            struct Geometry: Codable {
                let x: Double?
                let y: Double?
            }
        }
    }
    
    guard let response = try? JSONDecoder().decode(ArcGISResponse.self, from: data),
          let features = response.features else {
        return []
    }
    
    return features.compactMap { feature -> TrafficCamera? in
        guard let attrs = feature.attributes,
              let geom = feature.geometry,
              let lat = geom.y,
              let lon = geom.x,
              let id = attrs.CCTV_ID ?? attrs.OBJECTID.map(String.init),
              attrs.ACTIVE == 1 else {
            return nil
        }
        
        // Determine feed type and URL
        let feedURL: String
        let feedType: TrafficCamera.FeedType
        
        if let streamURL = attrs.STREAM_URL, !streamURL.isEmpty {
            feedURL = streamURL
            feedType = streamURL.contains(".m3u8") ? .hls : .mjpeg
        } else if let snapshotURL = attrs.SNAPSHOT_URL, !snapshotURL.isEmpty {
            feedURL = snapshotURL
            feedType = .jpeg
        } else {
            return nil  // No usable feed
        }
        
        return TrafficCamera(
            id: "txdot_\(id)",
            name: attrs.LOCATION ?? "TxDOT Camera",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            heading: nil,
            fieldOfView: 90,
            source: .txdot,
            feedType: feedType,
            feedURL: feedURL,
            thumbnailURL: attrs.SNAPSHOT_URL,
            roadName: attrs.ROADWAY,
            crossStreet: attrs.CROSS_ST,
            city: attrs.CITY,
            state: "TX"
        )
    }
}

/// Fallback cached cameras if API fails
private func loadCachedTxDOTCameras() -> [TrafficCamera] {
    let cacheFile = cacheDirectory.appendingPathComponent("txdot_cameras.json")
    if let data = try? Data(contentsOf: cacheFile),
       let cameras = try? JSONDecoder().decode([TrafficCamera].self, from: data) {
        return cameras
    }
    return []
}
```

## Fix 2.2: Add 511 API Support (Alternative Source)

```swift
/// Fetch from TX 511 API (backup source)
private func fetch511Cameras(near location: CLLocationCoordinate2D) async -> [TrafficCamera] {
    // TX 511 uses a different endpoint
    let url = "https://api.511mn.org/cameras?format=json"  // Example - find actual TX endpoint
    
    // Similar parsing logic...
    return []
}
```

## Fix 2.3: Improve Error Handling for Failed Feeds

**File:** `CameraFeedView.swift`

Update `loadFeed()` to show better error messages:

```swift
func loadFeed() {
    isLoading = true
    lastError = nil
    
    Task {
        do {
            guard let url = URL(string: camera.feedURL) else {
                throw CameraError.invalidURL
            }
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw CameraError.httpError(httpResponse.statusCode)
                }
            }
            
            // Verify it's an image
            guard let image = UIImage(data: data) else {
                throw CameraError.invalidImageData
            }
            
            await MainActor.run {
                currentFrame = image
                lastRefresh = Date()
                isLoading = false
            }
            
        } catch {
            await MainActor.run {
                isLoading = false
                lastError = describeError(error)
            }
        }
    }
}

enum CameraError: Error {
    case invalidURL
    case httpError(Int)
    case invalidImageData
    case networkError(Error)
}

func describeError(_ error: Error) -> String {
    switch error {
    case CameraError.invalidURL:
        return "Invalid camera URL"
    case CameraError.httpError(let code):
        return "Feed unavailable (HTTP \(code))"
    case CameraError.invalidImageData:
        return "Invalid image data"
    case CameraError.networkError:
        return "Network error"
    default:
        return "Feed unavailable"
    }
}
```

---

# PART 3: Scan List UX Improvements

## Problem
- No scan names, just point counts
- No status indicators for failed exports
- No thumbnails
- Chevron leads to broken detail view

## Fix 3.1: Enhanced Scan Row

**File:** `ScanGalleryView.swift`

Replace `ScanRowView` or create new:

```swift
struct ScanRow: View {
    let scan: SavedScan
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or placeholder
            ZStack {
                if let thumbnail = loadThumbnail() {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    Image(systemName: "cube.transparent")
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            .clipped()
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Name (editable) or auto-generated
                Text(scan.name.isEmpty ? defaultName : scan.name)
                    .font(.headline)
                    .lineLimit(1)
                
                // Point count + relative time
                HStack(spacing: 8) {
                    Text(formatPointCount(scan.pointCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(scan.timestamp.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Status indicator
            statusBadge
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    var statusBadge: some View {
        Group {
            if scan.hasUSDZ {
                // Model available
                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("3D")
                        .font(.caption2.bold())
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            } else {
                // No model
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No model")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(6)
    }
    
    var defaultName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Scan \(formatter.string(from: scan.timestamp))"
    }
    
    func formatPointCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM pts", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK pts", Double(count) / 1_000)
        }
        return "\(count) pts"
    }
    
    func loadThumbnail() -> UIImage? {
        let thumbURL = scan.scanDir.appendingPathComponent("thumbnail.jpg")
        guard let data = try? Data(contentsOf: thumbURL) else { return nil }
        return UIImage(data: data)
    }
}
```

## Fix 3.2: Update SavedScan Model

Ensure `SavedScan` has these computed properties:

```swift
struct SavedScan {
    // ... existing properties ...
    
    var hasUSDZ: Bool {
        FileManager.default.fileExists(atPath: usdzURL.path)
    }
    
    var scanDir: URL {
        // Directory containing this scan
    }
    
    var usdzURL: URL {
        scanDir.appendingPathComponent("scan.usdz")
    }
}
```

## Fix 3.3: Disable Tap on Broken Scans

When a scan has no model, either:
- Show inline message instead of navigating
- Navigate but show clear "Export failed, rescan needed" message

```swift
// In scan list
ForEach(scans) { scan in
    if scan.hasUSDZ {
        NavigationLink(destination: ScanDetailView(scan: scan)) {
            ScanRow(scan: scan)
        }
    } else {
        ScanRow(scan: scan)
            .onTapGesture {
                // Show alert or inline message
                selectedBrokenScan = scan
                showBrokenScanAlert = true
            }
    }
}
.alert("Scan Incomplete", isPresented: $showBrokenScanAlert) {
    Button("Delete Scan", role: .destructive) {
        deleteScan(selectedBrokenScan)
    }
    Button("OK", role: .cancel) { }
} message: {
    Text("This scan's 3D model failed to export. The point data is saved but cannot be viewed. Delete and rescan?")
}
```

---

# PART 4: Remove All Emojis

## Problem
Emojis in a tactical/mil-spec app look unprofessional.

## Fix
Search and replace all emoji usage with text or SF Symbols:

```bash
# Find all emojis in Swift files
grep -rn "[\U0001F300-\U0001F9FF]" --include="*.swift" Sources/
```

**Common replacements:**

| Emoji | Replace With |
|-------|--------------|
| ⚠️ | `Image(systemName: "exclamationmark.triangle")` or text "Warning:" |
| ✅ | `Image(systemName: "checkmark.circle")` or text "Complete" |
| ❌ | `Image(systemName: "xmark.circle")` or text "Failed" |
| 🔴🟡🟢 | `Circle().fill(.red/.yellow/.green)` |
| 📍 | `Image(systemName: "mappin")` |
| 🎯 | `Image(systemName: "scope")` |
| Any status emoji | Plain text status |

**Files to check:**
- `analysisStatus` strings in `LiDARCaptureEngine.swift`
- Status labels in all views
- Any hardcoded strings with emoji

**Rule:** No emoji characters in any user-facing text. Use SF Symbols or plain text only.

---

# PART 5: Force Unwrap Fixes

## Fix All `.first!` and `.last!`

**File:** `ScanGalleryView.swift` lines 435-436, 467-468

Replace:
```swift
from: measurementManager.currentPoints.last!,
to: measurementManager.currentPoints.first!,
```

With:
```swift
guard let lastPoint = measurementManager.currentPoints.last,
      let firstPoint = measurementManager.currentPoints.first else { return }
// Then use lastPoint, firstPoint
```

**File:** `TacticalNavigationStack.swift` line 80

Replace:
```swift
path.waypoints.last!.coordinate
```

With:
```swift
guard let lastWaypoint = path.waypoints.last else { return }
lastWaypoint.coordinate
```

---

# Testing Checklist

After all fixes:

## LiDAR
- [ ] 10M point scan → stop → no crash, view loads
- [ ] 50M point scan → stop → no crash, view loads
- [ ] 64M+ point scan → warning shown, cap enforced
- [ ] Stop mid-scan → save completes in background
- [ ] Kill app during save → restart shows partial scan

## Cameras
- [ ] San Antonio map shows 50+ cameras (not 4)
- [ ] Tap camera → feed loads (not 404)
- [ ] Feed auto-refreshes
- [ ] Offline → shows cached frame
- [ ] Feed error → shows clear error message

## Scan List UX
- [ ] Each row shows name, point count, relative time
- [ ] Status badge shows "3D" or "No model"
- [ ] Broken scans show warning, can delete
- [ ] Thumbnails load for completed scans

## Emojis
- [ ] No emoji characters anywhere in app
- [ ] Status messages use plain text
- [ ] Icons use SF Symbols only
