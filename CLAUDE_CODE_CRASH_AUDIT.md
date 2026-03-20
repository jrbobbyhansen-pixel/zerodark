# ZeroDark Crash Point Audit — CRITICAL

## Context
App crashed after stopping a 64 million point LiDAR scan. User reports multiple crash points throughout the app.

## Objective
Find and fix ALL potential crash points, memory issues, threading violations, and stability problems.

---

## AUDIT CATEGORIES

### 1. Force Unwraps (`!`)
**Risk:** Instant crash if nil

```bash
grep -rn "!" --include="*.swift" Sources/MLXEdgeLLM/ | grep -v "//" | grep -v "!=" | grep -v "/*" | grep -v "TODO" | grep -v "MARK" | head -100
```

**Action:** Convert all `!` to:
- `guard let ... else { return }` 
- `if let`
- `??` with safe default
- `fatalError()` only in truly impossible cases with comment explaining why

---

### 2. Main Thread Violations
**Risk:** UI updates from background = crash

Search for:
```bash
grep -rn "DispatchQueue.main\|@MainActor\|MainActor.run" --include="*.swift" Sources/MLXEdgeLLM/
```

**Check these patterns:**
- [ ] All `@Published` property updates happen on main thread
- [ ] All UI state changes wrapped in `@MainActor` or `DispatchQueue.main`
- [ ] SceneKit/ARKit delegate callbacks dispatch to main before updating state
- [ ] Completion handlers that update UI are on main thread

**Common violations in LiDAR code:**
```swift
// BAD - ARSession delegate on background thread updating Published
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    self.pointCount = newCount  // CRASH if @Published
}

// GOOD
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let count = newCount
    Task { @MainActor in
        self.pointCount = count
    }
}
```

---

### 3. Memory Pressure (64M Points!)
**Risk:** Out of memory = instant kill by iOS

**Files to audit:**
- `LiDARCaptureEngine.swift` — point cloud accumulation
- `ScanStorage.swift` — saving large scans
- `ScanGalleryView.swift` — loading scans into memory
- `TacticalSceneView.swift` — SceneKit rendering

**Issues to find:**
- [ ] Arrays growing unbounded during capture
- [ ] No chunking for large point clouds
- [ ] Loading entire scan into memory at once
- [ ] SceneKit geometries not released
- [ ] ARMeshAnchors retained after scan stops
- [ ] Multiple copies of point data in memory

**Fixes needed:**
```swift
// BAD - grows forever
var allPoints: [SIMD3<Float>] = []
func addPoints(_ new: [SIMD3<Float>]) {
    allPoints.append(contentsOf: new)  // 64M * 12 bytes = 768MB!
}

// GOOD - streaming to disk
func addPoints(_ new: [SIMD3<Float>]) {
    writeChunkToDisk(new)
    pointCount += new.count
}
```

---

### 4. Stop Scan Race Conditions
**Risk:** Accessing deallocated resources

**The crash scenario:**
1. User presses Stop
2. ARSession stops, delegates fire final callbacks
3. Code tries to access session/anchors that are being torn down
4. CRASH

**Audit `LiDARCaptureEngine.stopScan()`:**
- [ ] Is there a flag checked before accessing session?
- [ ] Are delegate callbacks ignored after stop?
- [ ] Is there proper synchronization?
- [ ] Are resources released in correct order?

```swift
// BAD
func stopScan() {
    session.pause()
    processRemainingAnchors()  // Session might be gone!
}

// GOOD
func stopScan() {
    isCapturing = false  // Flag checked in delegates
    session.pause()
    
    // Give delegates time to finish
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.processRemainingAnchors()
    }
}
```

---

### 5. Async/Await Crashes
**Risk:** Task cancellation, actor isolation violations

Search for:
```bash
grep -rn "Task {" --include="*.swift" Sources/MLXEdgeLLM/
grep -rn "async let" --include="*.swift" Sources/MLXEdgeLLM/
grep -rn "await " --include="*.swift" Sources/MLXEdgeLLM/
```

**Issues to find:**
- [ ] Tasks not cancelled on view disappear
- [ ] `Task.checkCancellation()` not called in loops
- [ ] Actor isolation violations (accessing actor state from wrong context)
- [ ] Detached tasks accessing `self` after dealloc

---

### 6. Optional Chaining Depth
**Risk:** Silent nil propagation leading to unexpected state

```bash
grep -rn "\?\\." --include="*.swift" Sources/MLXEdgeLLM/ | grep "\?\.\S*\?\." 
```

Long chains like `a?.b?.c?.d` can silently fail. Ensure critical paths have explicit error handling.

---

### 7. Array/Collection Access
**Risk:** Index out of bounds

```bash
grep -rn "\[.*\]" --include="*.swift" Sources/MLXEdgeLLM/ | grep -v "\/\/" | head -50
```

**Check for:**
- [ ] `array[index]` without bounds check
- [ ] `array.first!` or `array.last!`
- [ ] `array.remove(at:)` without count check
- [ ] Dictionary subscript with `!`

```swift
// BAD
let point = points[index]  // Crash if index >= count

// GOOD
guard index < points.count else { return }
let point = points[index]
```

---

### 8. SceneKit/ARKit Specific Crashes

**SCNView issues:**
- [ ] Geometry created on background thread
- [ ] Materials accessed after scene dealloc
- [ ] Node hierarchy modified during render

**ARSession issues:**
- [ ] Configuration changes during active session
- [ ] Accessing frame data after session paused
- [ ] MeshAnchor geometry accessed after removal

**Audit files:**
- `TacticalSceneView.swift`
- `LiDARCaptureEngine.swift`
- `Scan3DView.swift`

---

### 9. File I/O Crashes
**Risk:** Disk full, permission denied, path issues

```bash
grep -rn "write\|FileManager\|Data(contentsOf" --include="*.swift" Sources/MLXEdgeLLM/
```

**Check for:**
- [ ] `try` without `catch` (will crash on error)
- [ ] No disk space check before large write
- [ ] Path construction with `!`
- [ ] Synchronous large file writes on main thread

```swift
// BAD
try data.write(to: url)  // Crashes on disk full

// GOOD
do {
    try data.write(to: url)
} catch {
    print("[Error] Failed to write: \(error)")
    // Handle gracefully
}
```

---

### 10. Codable Crashes
**Risk:** Malformed data = decode crash

```bash
grep -rn "JSONDecoder\|JSONEncoder" --include="*.swift" Sources/MLXEdgeLLM/
```

**Check for:**
- [ ] `try!` on decode
- [ ] No fallback for corrupt data
- [ ] Schema changes breaking existing files

---

## SPECIFIC FILES TO AUDIT (Priority Order)

### 1. LiDARCaptureEngine.swift (CRITICAL)
The crash happened here. Full audit:
- Memory management during capture
- Stop scan flow
- Delegate callback safety
- Point cloud accumulation
- Export functions

### 2. ScanStorage.swift
- Large scan handling
- Async save operations
- Index consistency

### 3. ScanGalleryView.swift
- Loading large scans
- SceneKit memory
- View lifecycle

### 4. TacticalSceneView.swift
- Coordinator lifecycle
- Scene cleanup
- Measurement visualization

### 5. MeasurementManager.swift
- File I/O
- State consistency

### 6. ReconWalkEngine.swift
- Same issues as LiDARCaptureEngine

---

## OUTPUT FORMAT

After audit, provide:

```markdown
## Crash Audit Results

### Critical (Will Crash)
| File | Line | Issue | Fix |
|------|------|-------|-----|
| LiDARCaptureEngine.swift | 234 | Force unwrap on session.currentFrame! | Guard let |
| ... | ... | ... | ... |

### High Risk (Likely to Crash Under Load)
| File | Line | Issue | Fix |
|------|------|-------|-----|

### Medium Risk (Edge Case Crashes)
| File | Line | Issue | Fix |
|------|------|-------|-----|

### Memory Issues
| File | Issue | Fix |
|------|-------|-----|
| LiDARCaptureEngine.swift | Points array grows to 768MB | Stream to disk in chunks |

### Threading Issues
| File | Line | Issue | Fix |
|------|------|-------|-----|

### Total Issues Found: X
### Issues Fixed: Y
```

---

## FIX PRIORITIES

1. **Fix the stop scan crash FIRST** — this is what Bobby hit
2. **Add memory chunking for large scans** — 64M points needs streaming
3. **Fix all force unwraps** — low-hanging fruit
4. **Add threading safety** — MainActor consistency
5. **Add error handling to file I/O** — graceful degradation

---

## TESTING AFTER FIXES

1. Capture 10M point scan → stop → should not crash
2. Capture 50M point scan → stop → should not crash
3. Capture 100M point scan → should warn about memory, not crash
4. Kill app mid-capture → restart → should recover gracefully
5. Fill disk → save scan → should show error, not crash
6. Load corrupt scan file → should show error, not crash

---

## MEMORY BUDGET REFERENCE

- iPhone 15 Pro: ~4GB RAM, app limit ~2-3GB
- 64M points × 12 bytes = 768MB (just points)
- With mesh, colors, metadata: easily 1.5GB+
- **Must stream to disk or cap capture**
