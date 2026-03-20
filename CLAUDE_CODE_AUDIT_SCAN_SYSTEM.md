# ZeroDark Scan System — Full Audit Prompt

## Objective
Audit the recently implemented scan persistence, library, and measurement systems. Verify all code is wired, no dead code exists, builds clean, and features work end-to-end.

## Files to Audit

### Core Scan System
- `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/ScanStorage.swift`
- `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/LiDARCaptureEngine.swift`
- `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/MeasurementTypes.swift`
- `Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/MeasurementManager.swift`

### UI Components
- `Sources/MLXEdgeLLM/App/ScanGalleryView.swift`
- `Sources/MLXEdgeLLM/App/LiDARTabView.swift`
- `Sources/MLXEdgeLLM/App/MeasurementOverlayView.swift`

## Audit Checklist

### 1. Build Verification
```bash
cd ~/Developer/ZeroDark
xcodebuild -scheme ZeroDark -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | grep -E "(error:|warning:|Build Succeeded)"
```
- [ ] Build succeeds with zero errors
- [ ] Note any warnings (fix if straightforward)

### 2. Import/Dependency Check
For each new file, verify it's properly imported where used:

**ScanStorage.swift**
- [ ] `ScanStorage.shared` is called in `LiDARCaptureEngine.saveScanToDisk()`
- [ ] `ScanStorage.shared` is used as `@StateObject` in `ScanGalleryView`
- [ ] `SavedScan` struct is used in gallery views
- [ ] `loadScanIndex()` is called appropriately

**MeasurementTypes.swift**
- [ ] `MeasurementType` enum used in `MeasurementManager`
- [ ] `MeasurementAnnotation` used for persistence
- [ ] `CodableSIMD3` used for JSON encoding points
- [ ] `ScanAnnotations` container used in manager

**MeasurementManager.swift**
- [ ] `@StateObject` in `Scan3DView`
- [ ] Passed to `TacticalSceneView` as `@ObservedObject`
- [ ] Passed to `MeasurementOverlayView`
- [ ] `loadAnnotations(for:)` called on view appear
- [ ] `saveAnnotations()` called after measurements complete

**MeasurementOverlayView.swift**
- [ ] Used in `Scan3DView` as overlay
- [ ] `MeasurementListView` accessible via sheet
- [ ] `MeasurementRow` used in list

### 3. Dead Code Detection
Search for unused functions, structs, and variables:

```bash
# Find potentially unused functions
grep -rn "func " Sources/MLXEdgeLLM/SpatialIntelligence/LiDAR/*.swift | while read line; do
  funcname=$(echo "$line" | sed -n 's/.*func \([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p')
  if [ -n "$funcname" ]; then
    count=$(grep -r "$funcname" Sources/MLXEdgeLLM --include="*.swift" | wc -l)
    if [ "$count" -le 1 ]; then
      echo "POSSIBLY UNUSED: $funcname in $line"
    fi
  fi
done
```

Check for:
- [ ] No orphaned functions (defined but never called)
- [ ] No commented-out code blocks (remove or document why kept)
- [ ] No unused imports
- [ ] No TODO/FIXME left unaddressed (list them if found)

### 4. Data Flow Verification

**Scan Capture → Persistence Flow**
1. [ ] `LiDARCaptureEngine.stopScan()` creates `LiDARScanResult`
2. [ ] `saveScanToDisk()` is called
3. [ ] `ScanStorage.shared.loadScanIndex()` is triggered (or save method handles it)
4. [ ] `savedScans` array updates
5. [ ] Gallery UI shows new scan

**Scan Load → Display Flow**
1. [ ] Tap scan in gallery → `ScanDetailView` loads
2. [ ] `scan.hasUSDZ` check works
3. [ ] `Scan3DView` receives `usdzURL` and `scanDir`
4. [ ] `TacticalSceneView` loads USDZ into SceneKit
5. [ ] 3D model displays with tactical materials

**Measurement Flow**
1. [ ] Tap "Measure" → `measurementManager.startMeasurement()` called
2. [ ] `measurementManager.isActive` becomes true
3. [ ] Tap on mesh → `handleTap()` fires
4. [ ] Hit test returns world coordinates
5. [ ] `measurementManager.addPoint()` called
6. [ ] UI updates (point count, live value)
7. [ ] Auto-complete or Done → `completeMeasurement()` called
8. [ ] `saveAnnotations()` writes to `annotations.json`
9. [ ] Visualization updates (green markers for saved)

### 5. UI State Consistency

**Gallery View States**
- [ ] Empty state shows when `savedScans.isEmpty`
- [ ] List populates correctly when scans exist
- [ ] NavigationLink to detail works
- [ ] Scan type icons display (cube vs figure.walk)

**Detail View States**
- [ ] Name editing works (tap pencil, edit, save)
- [ ] 3D view loads or shows "not available" fallback
- [ ] Metadata card shows correct values
- [ ] GPS coordinates format correctly (or "No GPS")
- [ ] Risk level badge shows correct color

**Measurement Overlay States**
- [ ] Type picker visible when measuring
- [ ] Unit toggle works (m ↔ ft)
- [ ] Instruction text updates per state
- [ ] Live value displays during measurement
- [ ] Point indicators show progress
- [ ] Cancel clears current measurement
- [ ] Done button appears for area (3+ points)
- [ ] Measurements list opens via sheet

### 6. Persistence Verification

**Scan Persistence**
- [ ] `Documents/LiDARScans/{id}/metadata.json` exists after save
- [ ] `metadata.json` contains: id, timestamp, pointCount, riskScore, lat, lon, name
- [ ] `points.ply` or `points.bin` exists
- [ ] `scan.usdz` exists (if mesh exported)
- [ ] Scans survive app restart

**Annotation Persistence**
- [ ] `Documents/LiDARScans/{id}/annotations.json` created on first measurement
- [ ] Contains: measurements array, lastModified timestamp
- [ ] Each measurement has: id, type, points, timestamp, label
- [ ] Annotations load on view appear
- [ ] Deleted measurements removed from file

### 7. Error Handling

- [ ] Missing USDZ → graceful fallback UI (not crash)
- [ ] Corrupted metadata.json → scan skipped (not crash)
- [ ] Tap misses mesh → no point added (not crash)
- [ ] Empty annotations.json → creates fresh container
- [ ] File write fails → logged (not silent)

### 8. Memory & Performance

- [ ] `ScanStorage.shared` is singleton (not recreated)
- [ ] `MeasurementManager` created once per detail view
- [ ] Large point clouds don't cause UI freeze
- [ ] SceneKit scene properly released on dismiss
- [ ] No retain cycles in coordinators

### 9. Code Quality

- [ ] Consistent naming (camelCase functions, PascalCase types)
- [ ] No force unwraps (`!`) in production paths
- [ ] Proper `@MainActor` annotations on UI-bound code
- [ ] `Task { @MainActor in }` for async → main thread hops
- [ ] Clear separation: data models vs managers vs views

## Output Format

After audit, provide:

```markdown
## Audit Results

### Build Status
- [PASS/FAIL] Build result
- Warnings: [count] (list if any)

### Wiring Issues Found
1. [Issue description] → [Fix applied]
2. ...

### Dead Code Removed
1. [Function/struct name] in [file]
2. ...

### TODO/FIXME Items
1. [Item] in [file:line]
2. ...

### Persistence Verified
- [x] Scan save/load
- [x] Annotation save/load
- [x] Name editing persists

### Recommendations
1. [Optional improvement]
2. ...

### Final Status
✅ All systems wired and functional
OR
⚠️ Issues remaining: [list]
```

## Fix Authority
- Fix any wiring issues found
- Remove confirmed dead code
- Add missing imports
- Fix obvious bugs
- Do NOT refactor working code just for style
- Do NOT add new features

## After Audit
Run build again to confirm all fixes compile:
```bash
xcodebuild -scheme ZeroDark -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
