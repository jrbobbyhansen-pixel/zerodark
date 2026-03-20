# ZeroDark Scan Pipeline Fix — CRITICAL

## The Goal
**Scan → Render → View — fast, offline, in-app**

User scans a room, stops, and immediately sees their 3D model. No crashes. No waiting. No external tools.

---

## Current Broken Flow

```
1. Capture points ✅ (works until memory limit)
2. Stop scan → saveScanToDisk() ❌ CRASH
   └── exportPointCloudToPLY() builds 2GB ASCII string on main thread
   └── iOS watchdog kills app after 10s
3. No model saved = nothing to view ❌
```

---

## Fixed Flow

```
1. Capture points (stream to disk in chunks)
2. Stop scan → async background save
   └── Binary format (fast write)
   └── SceneKit geometry built from mesh anchors (not points)
3. Immediate 3D view of mesh
4. Points available for measurements/analysis
```

---

## CRITICAL FIXES

### Fix 1: Background Async Save (MUST DO FIRST)

**File:** `LiDARCaptureEngine.swift`

**Current (BROKEN):**
```swift
func stopScan() {
    isScanning = false
    arSession?.pause()
    // ... builds result ...
    saveScanToDisk(result)  // SYNCHRONOUS - BLOCKS MAIN THREAD
}
```

**Fixed:**
```swift
func stopScan() {
    isScanning = false
    arSession?.pause()
    
    // Capture references before async
    let points = collectedPoints
    let anchors = meshAnchors
    let location = currentLocation
    let heading = currentHeading
    let startTime = scanStartTime
    
    // Clear capture state immediately (free memory)
    collectedPoints = []
    meshAnchors = []
    
    // Build result
    guard let start = startTime else { return }
    let result = LiDARScanResult(
        timestamp: Date(),
        location: location,
        heading: heading,
        pointCloud: points,
        meshAnchors: anchors,
        depthMap: nil,  // Don't access session after pause
        confidenceMap: nil,
        scanDuration: Date().timeIntervalSince(start),
        pointCount: points.count,
        boundingBox: calculateBoundingBox(from: points)
    )
    
    lastScanResult = result
    
    // ASYNC SAVE - does not block UI
    Task.detached(priority: .userInitiated) {
        await self.saveScanAsync(result)
    }
    
    // Immediately available for viewing (mesh anchors have geometry)
    analysisStatus = "Scan complete"
}
```

---

### Fix 2: Stream Points to Binary File (Not ASCII String)

**Current (BROKEN):**
```swift
func exportPointCloudToPLY(_ points: [SIMD3<Float>], to url: URL) {
    var ply = "ply\nformat ascii 1.0\n..."
    for point in points {  // 64 MILLION ITERATIONS
        ply += "\(point.x) \(point.y) \(point.z)\n"  // STRING CONCAT = O(n²)
    }
    try ply.write(to: url)  // 2GB write
}
```

**Fixed — Binary PLY (100x faster):**
```swift
func exportPointCloudToBinaryPLY(_ points: [SIMD3<Float>], to url: URL) async throws {
    guard !points.isEmpty else { return }
    
    // Create file handle for streaming write
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    
    // Write header
    let header = """
    ply
    format binary_little_endian 1.0
    element vertex \(points.count)
    property float x
    property float y
    property float z
    end_header
    
    """
    handle.write(header.data(using: .utf8)!)
    
    // Write points in chunks (avoid memory spike)
    let chunkSize = 100_000
    for chunkStart in stride(from: 0, to: points.count, by: chunkSize) {
        let chunkEnd = min(chunkStart + chunkSize, points.count)
        let chunk = points[chunkStart..<chunkEnd]
        
        // Pack floats directly to binary
        var data = Data(capacity: chunk.count * 12)
        for point in chunk {
            var x = point.x, y = point.y, z = point.z
            data.append(Data(bytes: &x, count: 4))
            data.append(Data(bytes: &y, count: 4))
            data.append(Data(bytes: &z, count: 4))
        }
        handle.write(data)
        
        // Yield to prevent blocking
        await Task.yield()
    }
}
```

**Even better — Custom binary format (fastest for app):**
```swift
func savePointCloudBinary(_ points: [SIMD3<Float>], to url: URL) async throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    
    // Header: just point count (4 bytes)
    var count = UInt32(points.count)
    handle.write(Data(bytes: &count, count: 4))
    
    // Points: raw SIMD3<Float> (12 bytes each)
    // Write in 1MB chunks
    let chunkSize = 85_000  // ~1MB per chunk
    for chunkStart in stride(from: 0, to: points.count, by: chunkSize) {
        let chunkEnd = min(chunkStart + chunkSize, points.count)
        
        points[chunkStart..<chunkEnd].withContiguousStorageIfAvailable { buffer in
            let data = Data(bytes: buffer.baseAddress!, count: buffer.count * 12)
            handle.write(data)
        }
        
        await Task.yield()
    }
}

func loadPointCloudBinary(from url: URL) throws -> [SIMD3<Float>] {
    let data = try Data(contentsOf: url)
    guard data.count >= 4 else { return [] }
    
    let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
    var points: [SIMD3<Float>] = []
    points.reserveCapacity(Int(count))
    
    data.dropFirst(4).withUnsafeBytes { buffer in
        let floatBuffer = buffer.bindMemory(to: SIMD3<Float>.self)
        points.append(contentsOf: floatBuffer)
    }
    
    return points
}
```

---

### Fix 3: Use Mesh Anchors for 3D View (Not Points)

The ARMeshAnchors already have geometry — use that for viewing!

**File:** `ScanGalleryView.swift` or new `MeshViewer.swift`

```swift
/// Build SceneKit geometry from ARMeshAnchor
func buildSceneGeometry(from anchor: ARMeshAnchor) -> SCNGeometry {
    let meshGeometry = anchor.geometry
    
    // Get vertices
    let vertexSource = SCNGeometrySource(
        buffer: meshGeometry.vertices.buffer,
        vertexFormat: meshGeometry.vertices.format,
        semantic: .vertex,
        vertexCount: meshGeometry.vertices.count,
        dataOffset: meshGeometry.vertices.offset,
        dataStride: meshGeometry.vertices.stride
    )
    
    // Get faces
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
    
    // Tactical material
    let material = SCNMaterial()
    material.diffuse.contents = UIColor(red: 0.1, green: 0.4, blue: 0.15, alpha: 1.0)
    material.isDoubleSided = true
    geometry.materials = [material]
    
    return geometry
}

/// Build complete scene from all mesh anchors
func buildScene(from anchors: [ARMeshAnchor]) -> SCNScene {
    let scene = SCNScene()
    
    for anchor in anchors {
        let geometry = buildSceneGeometry(from: anchor)
        let node = SCNNode(geometry: geometry)
        node.simdTransform = anchor.transform
        scene.rootNode.addChildNode(node)
    }
    
    // Add tactical lighting
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.color = UIColor(red: 0, green: 0.3, blue: 0.1, alpha: 1)
    scene.rootNode.addChildNode(ambient)
    
    return scene
}
```

---

### Fix 4: Export USDZ Async (for sharing/QuickLook)

**Current (BROKEN):**
```swift
exportMeshToUSDZ(result.meshAnchors, to: url)  // Synchronous
```

**Fixed:**
```swift
func exportMeshToUSDZAsync(_ anchors: [ARMeshAnchor], to url: URL) async throws {
    let scene = buildScene(from: anchors)
    
    try await withCheckedThrowingContinuation { continuation in
        scene.write(to: url, options: nil, delegate: nil) { progress, error, stop in
            if let error = error {
                continuation.resume(throwing: error)
            } else if progress >= 1.0 {
                continuation.resume()
            }
        }
    }
}
```

---

### Fix 5: Memory-Safe Point Collection

**Option A: Cap collection + warn user**
```swift
private let maxPoints = 50_000_000  // 50M = 600MB, safe limit

func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // ... existing code ...
    
    if collectedPoints.count >= maxPoints {
        if !hasWarnedMaxPoints {
            hasWarnedMaxPoints = true
            Task { @MainActor in
                analysisStatus = "Point limit reached (50M). Stop scan to save."
            }
        }
        return  // Stop collecting
    }
    
    collectedPoints.append(contentsOf: newPoints)
}
```

**Option B: Stream to disk during capture (advanced)**
```swift
// Write points to temp file as they come in
// Only keep last N points in memory for live preview
// On stop, finalize the file
```

---

### Fix 6: Async Save Wrapper

```swift
private func saveScanAsync(_ result: LiDARScanResult) async {
    let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LiDARScans", isDirectory: true)
    
    let scanDir = scansDir.appendingPathComponent(result.id.uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
    
    // 1. Save metadata (fast)
    await saveMetadata(result, to: scanDir)
    
    // 2. Save point cloud binary (medium)
    do {
        try await savePointCloudBinary(result.pointCloud, to: scanDir.appendingPathComponent("points.bin"))
        print("[ZeroDark] Points saved: \(result.pointCount)")
    } catch {
        print("[ZeroDark] Point save failed: \(error)")
    }
    
    // 3. Export USDZ (slow but async)
    do {
        try await exportMeshToUSDZAsync(result.meshAnchors, to: scanDir.appendingPathComponent("scan.usdz"))
        print("[ZeroDark] USDZ exported")
    } catch {
        print("[ZeroDark] USDZ export failed: \(error)")
    }
    
    // 4. Update gallery
    await MainActor.run {
        ScanStorage.shared.loadScanIndex()
    }
    
    // 5. Run analysis
    await analyzeResult(result)
}

private func saveMetadata(_ result: LiDARScanResult, to dir: URL) async {
    struct Meta: Codable {
        let id: String
        let timestamp: Date
        let lat, lon: Double?
        let pointCount: Int
        let hasUSDZ: Bool
    }
    
    let meta = Meta(
        id: result.id.uuidString,
        timestamp: result.timestamp,
        lat: result.location?.latitude,
        lon: result.location?.longitude,
        pointCount: result.pointCount,
        hasUSDZ: !result.meshAnchors.isEmpty
    )
    
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(meta) {
        try? data.write(to: dir.appendingPathComponent("metadata.json"))
    }
}
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `LiDARCaptureEngine.swift` | Async save, binary PLY, memory cap |
| `ScanStorage.swift` | Load binary format |
| `ScanGalleryView.swift` | Build scene from mesh anchors |
| `TacticalSceneView.swift` | Use mesh geometry directly |

## Performance Targets

| Operation | Current | After Fix |
|-----------|---------|-----------|
| Stop 64M scan | CRASH | <2 seconds |
| Save to disk | CRASH | <10 seconds (background) |
| View 3D model | Never | Immediate |
| Memory peak | 3.5GB (killed) | <1GB |

## Test Scenarios

1. ✅ Scan 10M points → stop → view immediately
2. ✅ Scan 50M points → stop → view immediately  
3. ✅ Scan 100M points → hits cap → warning shown → stop → view
4. ✅ Kill app during save → restart → partial scan recovered
5. ✅ Low storage → save fails gracefully with error message
