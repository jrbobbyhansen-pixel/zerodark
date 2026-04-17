// LiDARCaptureEngine.swift — Real-time 3D Scanning and Analysis
// Wires to Camera tab for structural and environmental analysis

import Foundation
import ARKit
import RealityKit
import MetalKit
import Combine
import CoreLocation
import SwiftUI
import SceneKit

// MARK: - Scan Configuration

struct LiDARScanConfig {
    var scanMode: ScanMode = .standard
    var captureDepth: Bool = true
    var captureConfidence: Bool = true
    var captureNormals: Bool = true
    var meshDetail: MeshDetail = .high
    var maxRange: Float = 8.0  // meters (iPhone 12+ LiDAR effective to ~5m, but can read farther in good conditions)
    var autoSave: Bool = true
    
    enum ScanMode {
        case standard       // Normal outdoor scanning
        case structural     // Building/infrastructure analysis
        case terrain        // Terrain mapping
        case concealment    // Find cover/concealment positions
        case tactical       // Full tactical analysis
    }
    
    enum MeshDetail {
        case low      // Fast, low memory
        case medium   // Balanced
        case high     // Maximum detail
        case adaptive // Based on content
    }

    // Pipeline feature flags (v2.0)
    var enableKalmanFusion: Bool = true
    var enableYOLO: Bool = true
    var enableRangeExtension: Bool = true
    var enableClutterFilter: Bool = true
    var enableHapticOverlay: Bool = true
}

// MARK: - Scan Result

struct LiDARScanResult: Identifiable {
    let id = UUID()
    let timestamp: Date
    let location: CLLocationCoordinate2D?
    let heading: Double?
    
    // Raw data
    let pointCloud: [SIMD3<Float>]
    let meshAnchors: [ARMeshAnchor]
    let depthMap: CVPixelBuffer?
    let confidenceMap: CVPixelBuffer?
    
    // Analysis results
    var structuralAnalysis: StructuralAnalysis?
    var terrainAnalysis: TerrainAnalysis?
    var tacticalAnalysis: TacticalAnalysis?
    
    // Metadata
    var scanDuration: TimeInterval
    var pointCount: Int
    var boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    
    /// LiDAR sensor position in 3D space (for route planning)
    var lidarPosition: SIMD3<Float> {
        // Use center of bounding box as approximate position
        return (boundingBox.min + boundingBox.max) / 2
    }
}

// MARK: - Analysis Results

struct StructuralAnalysis {
    let surfaces: [DetectedSurface]
    let openings: [DetectedOpening]  // Doors, windows, breaches
    let entryPoints: [EntryPoint]
    let materialEstimates: [MaterialEstimate]
    let structuralVulnerabilities: [Vulnerability]
    let confidenceScore: Float
    // Enhanced by PlaneDetection + BuildingExtractor + VolumeMeasure + HeightMeasure
    var detectedPlanes: [DetectedPlane] = []
    var buildingFootprints: [ExtractedBuilding] = []
    var estimatedVolume: Float = 0
    var maxHeight: Float = 0
}

struct TerrainAnalysis {
    let elevation: [LiDARElevationPoint]
    let slope: [SlopeRegion]
    let coverPositions: [CoverPosition]
    let deadSpace: [DeadSpaceRegion]
    let routeOptions: [RouteOption]
    let obstructions: [Obstruction]
}

struct TacticalAnalysis {
    let observationPosts: [ObservationPost]
    let fieldsOfFire: [FieldOfFire]
    let concealmentPositions: [ConcealmentPosition]
    let approachRoutes: [ApproachRoute]
    let escapeRoutes: [EscapeRoute]
    let threatVectors: [ThreatVector]
    let overallAssessment: String
    let riskScore: Float  // 0-1
    // Enhanced by HazardDetector + PersonDetector
    var hazards: [ScanHazard] = []
    var detectedPersonCount: Int = 0
}

// MARK: - Inline Hazard Type (avoids dependency on HazardDetector.swift)

struct ScanHazard: Identifiable {
    let id = UUID()
    let type: String
    let position: SIMD3<Float>
    let severity: String
    let description: String
}

// MARK: - Detection Types

struct DetectedSurface {
    let id = UUID()
    let type: SurfaceType
    let vertices: [SIMD3<Float>]
    let normal: SIMD3<Float>
    let area: Float
    let material: MaterialEstimate?
    
    enum SurfaceType {
        case ground, wall, ceiling, roof, obstacle

        var description: String {
            switch self {
            case .ground: return "Ground"
            case .wall: return "Wall"
            case .ceiling: return "Ceiling"
            case .roof: return "Roof"
            case .obstacle: return "Obstacle"
            }
        }
    }
}

struct DetectedOpening {
    let id = UUID()
    let type: OpeningType
    let center: SIMD3<Float>
    let dimensions: SIMD2<Float>  // width, height
    let normal: SIMD3<Float>
    let accessibility: Float  // 0-1
    
    enum OpeningType {
        case door, window, breach, passage, vent

        var description: String {
            switch self {
            case .door: return "Door"
            case .window: return "Window"
            case .breach: return "Breach"
            case .passage: return "Passage"
            case .vent: return "Vent"
            }
        }
    }
}

struct EntryPoint: Identifiable {
    let id = UUID()
    let opening: DetectedOpening
    let difficulty: Float  // 0-1
    let visibility: Float  // 0-1, how exposed
    let approachOptions: [SIMD3<Float>]
}

struct MaterialEstimate {
    let surfaceId: UUID
    let material: Material
    let confidence: Float
    
    enum Material {
        case concrete, wood, metal, glass, earth, vegetation, water, unknown
    }
}

struct Vulnerability: Identifiable {
    let id = UUID()
    let location: SIMD3<Float>
    let type: VulnerabilityType
    let severity: Float  // 0-1
    let description: String

    enum VulnerabilityType {
        case structural, thermal, acoustic, visual, access

        var description: String {
            switch self {
            case .structural: return "Structural"
            case .thermal: return "Thermal"
            case .acoustic: return "Acoustic"
            case .visual: return "Visual"
            case .access: return "Access"
            }
        }
    }
}

struct LiDARElevationPoint {
    let position: SIMD2<Float>
    let elevation: Float
    let slope: Float
    let aspect: Float  // Direction slope faces
}

struct SlopeRegion {
    let vertices: [SIMD2<Float>]
    let averageSlope: Float
    let maxSlope: Float
    let traversability: Float  // 0-1
}

struct CoverPosition: Identifiable {
    let id = UUID()
    let center: SIMD3<Float>
    let type: CoverType
    let protection: Float  // 0-1
    let exposedDirections: [SIMD3<Float>]
    var visibilityFromThreats: Float = 0.5  // 0 = invisible, 1 = fully visible
    var accessibility: Float = 1.0  // 0 = inaccessible, 1 = easily accessible

    enum CoverType: String {
        case hardCover     // Stops bullets
        case concealment   // Hides but doesn't stop
        case partial       // Some protection

        var description: String {
            switch self {
            case .hardCover: return "Hard Cover"
            case .concealment: return "Concealment"
            case .partial: return "Partial"
            }
        }
    }
}

struct DeadSpaceRegion {
    let vertices: [SIMD3<Float>]
    let fromPositions: [SIMD3<Float>]  // Observer positions this is dead from
    let accessibility: Float
}

struct RouteOption {
    let waypoints: [SIMD3<Float>]
    let distance: Float
    let elevation: Float
    let exposure: Float  // 0-1, how visible
    let difficulty: Float  // 0-1
    let estimatedTime: TimeInterval
}

struct Obstruction {
    let center: SIMD3<Float>
    let boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)
    let passable: Bool
    let type: ObstructionType
    
    enum ObstructionType {
        case vegetation, rock, structure, water, fence, vehicle
    }
}

struct ObservationPost: Identifiable {
    let id = UUID()
    let position: SIMD3<Float>
    let fieldOfView: Float  // degrees
    let coverage: Float  // 0-1
    let concealment: Float  // 0-1
    let accessibility: Float  // 0-1
}

struct FieldOfFire {
    let origin: SIMD3<Float>
    let sectors: [Sector]
    let deadSpaces: [DeadSpaceRegion]
    
    struct Sector {
        let azimuthStart: Float
        let azimuthEnd: Float
        let maxRange: Float
        let obstacleCount: Int
    }
}

struct ConcealmentPosition: Identifiable {
    let id = UUID()
    let center: SIMD3<Float>
    let radius: Float
    let visibilityFromThreats: Float  // 0-1
    let egress: [SIMD3<Float>]
}

struct ApproachRoute: Identifiable {
    let id = UUID()
    let waypoints: [SIMD3<Float>]
    let coverPositions: [CoverPosition]
    let exposureScore: Float  // 0-1
    let estimatedTime: TimeInterval
    let difficulty: Float

    var description: String {
        String(format: "Route (%.0fm, exposure: %.0f%%)", waypoints.count > 1 ? Float(waypoints.count) * 5 : 0, exposureScore * 100)
    }
}

struct EscapeRoute: Identifiable {
    let id = UUID()
    let waypoints: [SIMD3<Float>]
    let coverPositions: [CoverPosition]
    let exitPoints: [SIMD3<Float>]
    let speed: Float  // meters/second possible
    let riskScore: Float
}

struct ThreatVector {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    let probability: Float
    let type: ThreatType
    
    enum ThreatType {
        case visual, acoustic, physical, unknown
    }
}

// MARK: - LiDAR Capture Engine

@MainActor
final class LiDARCaptureEngine: NSObject, ObservableObject {
    static let shared = LiDARCaptureEngine()
    
    // Published state
    @Published var isScanning = false
    @Published var scanProgress: Float = 0
    @Published var currentPointCount: Int = 0
    @Published var lastScanResult: LiDARScanResult?
    @Published var scanHistory: [LiDARScanResult] = []
    @Published var analysisStatus: String = "Ready"
    @Published var isAnalyzing = false
    
    // Scan quality guidance
    @Published var scanGuidance: ScanGuidance = .ready
    @Published var pointsPerSecond: Int = 0
    @Published var hasReachedMinimum: Bool = false
    
    // Coverage tracking — 8x8 grid based on camera look direction
    // Each cell tracks point density in that view direction
    @Published var coverageGrid: [[Float]] = Array(repeating: Array(repeating: 0, count: 8), count: 8)
    private var maxCellDensity: Float = 1.0  // For normalization
    
    // Point rate tracking
    private var lastPointCount: Int = 0
    private var lastRateCheck: Date = Date()
    private var frameCount: Int = 0
    
    /// Minimum points for a usable scan
    static let minimumUsablePoints = 100_000
    /// Good scan threshold
    static let goodScanPoints = 200_000
    /// Excellent scan threshold
    static let excellentScanPoints = 500_000
    
    enum ScanGuidance: String {
        case ready = "Point at room and tap SCAN"
        case scanSlower = "Scan slower for better quality"
        case moveCloser = "Move closer to surfaces (1-3m)"
        case goodCoverage = "Good coverage"
        case keepGoing = "Keep scanning more angles..."
        case minimumReached = "Minimum reached - add more for detail"
        case goodScan = "Good scan — stop when ready"
        case excellentScan = "Excellent coverage"
    }
    
    // AR Session
    private var arSession: ARSession?
    private var arView: ARView?
    
    // Scan data
    private var collectedPoints: [SIMD3<Float>] = []
    private var meshAnchors: [ARMeshAnchor] = []
    private var scanStartTime: Date?
    private let maxPointCount = 10_000_000
    private var hasWarnedPointLimit = false
    private var pointStreamURL: URL?
    private var pointStreamHandle: FileHandle?
    private var streamedPointCount: Int = 0

    // Configuration
    var config = LiDARScanConfig()

    // Enhanced LiDAR Pipeline (Kalman + ClutterFilter + YOLO + Haptics)
    // LiDARPipeline integration deferred — pipeline stack not yet in build phase
    private(set) var pipeline: Any?

    // LingBot-Map streaming 3D state (TSDF + GCA keyframes)
    private(set) var lingBotEngine: (any LingBotMapEngine)?

    // ICP scan matcher — produces BreadcrumbEngine corrections when GPS degrades
    private let scanMatcher = ScanMatcher()

    // Location
    private var locationManager: CLLocationManager?
    private var currentLocation: CLLocationCoordinate2D?
    private var currentHeading: Double?
    
    // Callbacks
    var onScanComplete: ((LiDARScanResult) -> Void)?
    var onAnalysisComplete: ((LiDARScanResult) -> Void)?
    
    override private init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Device Capability
    
    var isLiDARAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    
    // MARK: - Setup
    
    func setupARView(_ arView: ARView) {
        self.arView = arView
        self.arSession = arView.session
        arView.session.delegate = self
    }
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
        locationManager?.startUpdatingHeading()
    }
    
    // MARK: - Scanning
    
    func startScan() {
        guard isLiDARAvailable else {
            analysisStatus = "LiDAR not available"
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]

        if config.captureDepth {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arSession?.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        isScanning = true
        scanProgress = 0
        collectedPoints = []
        meshAnchors = []
        scanStartTime = Date()
        hasWarnedPointLimit = false

        // Setup point streaming to disk
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        pointStreamURL = tempURL
        pointStreamHandle = try? FileHandle(forWritingTo: tempURL)
        streamedPointCount = 0
        // Write placeholder header (count updated at stop)
        var placeholder = UInt32(0)
        pointStreamHandle?.write(Data(bytes: &placeholder, count: 4))

        analysisStatus = "Scanning..."

        // Enhanced pipeline deferred — LiDAR/Core stack not yet in build phase
        self.pipeline = nil

        // LingBot-Map streaming state (TSDF + GCA keyframes) — active now
        let lidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        if lidarAvailable {
            let memGB = Int(ProcessInfo.processInfo.physicalMemory / (1_024 * 1_024 * 1_024))
            let maxVoxels = memGB >= 8 ? 1_500_000 : (memGB >= 6 ? 1_000_000 : 500_000)
            let voxelConfig = VoxelStreamMap.Config(maxVoxelCount: maxVoxels)
            self.lingBotEngine = VoxelLingBotEngine(config: voxelConfig)
        } else {
            self.lingBotEngine = nil
        }

        // Reset guidance tracking
        scanGuidance = .goodCoverage
        pointsPerSecond = 0
        hasReachedMinimum = false
        lastPointCount = 0
        lastRateCheck = Date()
        frameCount = 0
        
        // Reset coverage grid
        coverageGrid = Array(repeating: Array(repeating: 0, count: 8), count: 8)
        maxCellDensity = 1.0

        // Reset scan matcher reference map for new scan
        scanMatcher.reset()
    }

    func startScan(config: LiDARScanConfig) {
        self.config = config
        startScan()
    }
    
    func stopScan() {
        isScanning = false
        arSession?.pause()
        // pipeline deferred — no stop() needed
        pipeline = nil
        let capturedLingBot = lingBotEngine
        lingBotEngine = nil

        guard let startTime = scanStartTime else { return }

        // Finalize stream file (update header with actual count)
        let streamURL = pointStreamURL
        if let handle = pointStreamHandle {
            handle.seek(toFileOffset: 0)
            var count = UInt32(streamedPointCount)
            handle.write(Data(bytes: &count, count: 4))
            try? handle.close()
        }
        pointStreamHandle = nil
        pointStreamURL = nil

        // Capture RAM buffer (last 100K) for analysis + bbox
        let points = collectedPoints
        let anchors = meshAnchors
        let location = currentLocation
        let heading = currentHeading
        let bbox = calculateBoundingBox()   // reads collectedPoints (100K max)
        let totalCount = streamedPointCount > 0 ? streamedPointCount : points.count

        // Free memory immediately
        collectedPoints = []
        meshAnchors = []

        let result = LiDARScanResult(
            timestamp: Date(),
            location: location,
            heading: heading,
            pointCloud: points,             // last 100K for analysis
            meshAnchors: anchors,
            depthMap: nil,
            confidenceMap: nil,
            scanDuration: Date().timeIntervalSince(startTime),
            pointCount: totalCount,
            boundingBox: bbox
        )

        lastScanResult = result
        scanHistory = []                    // Clear — full point arrays waste memory
        analysisStatus = "Saving..."

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.saveScanAsync(result, streamURL: streamURL, lingBotEngine: capturedLingBot)
        }
    }

    // MARK: - Streaming SceneTag Updates (LingBot-Map)

    @MainActor
    private func updateStreamingCovers(_ candidates: [(position: SIMD3<Float>, protection: Float)]) {
        guard var tag = AppState.shared.latestSceneTag as? SceneTag else { return }
        tag.covers = candidates.map { cand in
            SceneTag.TaggedCover(
                center: CodablePoint3D(cand.position),
                type: "streaming",
                protection: cand.protection
            )
        }
        AppState.shared.latestSceneTag = tag
        // Do NOT persist to disk here — SceneTagStore.save only runs at stopScan
    }

    private func streamPointsToDisk(_ points: [SIMD3<Float>]) {
        // Write to stream file
        if let handle = pointStreamHandle, !points.isEmpty {
            var data = Data(capacity: points.count * 12)
            for point in points {
                var p = point
                data.append(Data(bytes: &p, count: 12))
            }
            handle.write(data)
            streamedPointCount += points.count
        }

        // Keep last 100K in RAM for analysis/bounding box
        collectedPoints.append(contentsOf: points)
        if collectedPoints.count > 100_000 {
            collectedPoints.removeFirst(collectedPoints.count - 100_000)
        }
    }

    private func saveScanAsync(_ result: LiDARScanResult, streamURL: URL?, lingBotEngine: (any LingBotMapEngine)?) async {
        let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiDARScans", isDirectory: true)
        let scanDir = scansDir.appendingPathComponent(result.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)

        await saveMetadataAsync(result, to: scanDir)

        await MainActor.run { analysisStatus = "Saving points..." }
        let pointsDest = scanDir.appendingPathComponent("points.bin")
        if let src = streamURL, FileManager.default.fileExists(atPath: src.path) {
            do {
                try FileManager.default.moveItem(at: src, to: pointsDest)
            } catch {
                // Fallback: save 100K RAM buffer
                try? await savePointsBinary(result.pointCloud, to: pointsDest)
            }
        } else if !result.pointCloud.isEmpty {
            do {
                try await savePointsBinary(result.pointCloud, to: pointsDest)
            } catch {
            }
        }

        await MainActor.run { analysisStatus = "Exporting 3D model..." }
        do {
            try await exportMeshToUSDZAsync(result.meshAnchors, to: scanDir.appendingPathComponent("scan.usdz"))
        } catch {
        }

        // Snapshot voxel map to disk (background, writes voxel_map.bin)
        let voxelMapRef: String?
        if let lbe = lingBotEngine as? VoxelLingBotEngine {
            voxelMapRef = lbe.map.snapshotToDisk(scanDir: scanDir)?.lastPathComponent
        } else {
            voxelMapRef = lingBotEngine?.streamingMapRef
        }

        // Build and save initial SceneTag
        // Use streaming cover candidates (from VoxelStreamMap) if available,
        // otherwise fall back to batch cover detection from point cloud.
        let detections: [YOLODetection] = []  // YOLO detections are in AppState.latestSceneTag via streaming
        let streamingCandidates = lingBotEngine?.queryCoverCandidates() ?? []
        let covers: [CoverPosition]
        if !streamingCandidates.isEmpty {
            covers = streamingCandidates.map { cand in
                CoverPosition(center: cand.position, type: .hardCover, protection: cand.protection, exposedDirections: [])
            }
        } else {
            covers = findCoverPositions(pointCloud: result.pointCloud, meshAnchors: result.meshAnchors)
        }
        var sceneTag = SceneTag.from(
            result: result,
            detections: detections,
            coverPositions: covers,
            scanDir: scanDir,
            streamingMapRef: voxelMapRef
        )
        SceneTagStore.shared.save(sceneTag)

        await MainActor.run {
            ScanStorage.shared.loadScanIndex()
            AppState.shared.latestSceneTag = sceneTag
            analysisStatus = "Saved"
        }

        await analyzeResult(result, scanDir: scanDir, sceneTag: &sceneTag)
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

    // MARK: - Analysis
    
    private func analyzeResult(_ result: LiDARScanResult, scanDir: URL? = nil, sceneTag: inout SceneTag) async {
        isAnalyzing = true
        var analyzedResult = result

        // Phase 1: Core preprocessing (normals + ground classification)
        analysisStatus = "Estimating normals..."
        let normals = PointCloudEngine.shared.estimateNormals(result.pointCloud)

        analysisStatus = "Classifying ground..."
        let groundResult = GroundClassification().classify(result.pointCloud)

        // Phase 2: Plane detection on non-ground points
        analysisStatus = "Detecting planes..."
        let detectedPlanes = PlaneDetection.detectPlanes(in: groundResult.nonGround, normals: normals)
        let wallPlanes = detectedPlanes.filter { $0.classification == .wall }

        // Phase 3: Building extraction from wall clusters
        analysisStatus = "Extracting buildings..."
        let buildings = BuildingExtractor().extract(wallPlanes: wallPlanes, allPoints: result.pointCloud)

        // Phase 4: Measurements
        let volumeResult = VolumeMeasure.calculateVolume(from: result.pointCloud)
        let groundPlaneY = detectedPlanes.first(where: { $0.classification == .floor })?.centroid.y
        let heightResult = HeightMeasure.measureHeight(points: result.pointCloud, groundPlaneY: groundPlaneY)

        // Phase 5: Structural analysis (enhanced with planes, buildings, volume, height)
        analysisStatus = "Analyzing structure..."
        var structuralAnalysis = await performStructuralAnalysis(result)
        structuralAnalysis.detectedPlanes = detectedPlanes
        structuralAnalysis.buildingFootprints = buildings
        structuralAnalysis.estimatedVolume = volumeResult.volume
        structuralAnalysis.maxHeight = heightResult.maxHeight
        analyzedResult.structuralAnalysis = structuralAnalysis

        // Phase 6: Terrain analysis (enhanced with ground classification)
        analysisStatus = "Analyzing terrain..."
        let terrainAnalysis = await performTerrainAnalysis(result)
        analyzedResult.terrainAnalysis = terrainAnalysis

        // Phase 7: Hazard detection from DEM + planes
        analysisStatus = "Detecting hazards..."

        // Phase 8: Tactical assessment
        analysisStatus = "Performing tactical assessment..."
        var tacticalAnalysis = await performTacticalAnalysis(result, terrain: terrainAnalysis, structure: structuralAnalysis)
        tacticalAnalysis.detectedPersonCount = 0  // Pipeline YOLO deferred
        analyzedResult.tacticalAnalysis = tacticalAnalysis

        // Update the scan's riskScore in storage after analysis completes
        if let riskScore = analyzedResult.tacticalAnalysis?.riskScore {
            sceneTag.riskScore = riskScore
            Task { @MainActor in
                ScanStorage.shared.updateRiskScore(for: result.id, riskScore: riskScore)
            }
        }

        // Generate MLX tactical assessment (post-scan, not per-frame)
        analysisStatus = "Generating tactical assessment..."
        let assessment = await LiDARIntelBridge.shared.generateAssessment(
            threats: sceneTag.threats,
            covers: sceneTag.covers,
            tacticalAnalysis: analyzedResult.tacticalAnalysis,
            terrainAnalysis: analyzedResult.terrainAnalysis
        )
        sceneTag.assessment = assessment

        // Persist updated SceneTag with risk score and assessment
        SceneTagStore.shared.save(sceneTag)
        await MainActor.run {
            AppState.shared.latestSceneTag = sceneTag
        }

        lastScanResult = analyzedResult
        isAnalyzing = false
        analysisStatus = "Analysis complete"

        onScanComplete?(analyzedResult)
        onAnalysisComplete?(analyzedResult)
    }
    
    private func performStructuralAnalysis(_ result: LiDARScanResult) async -> StructuralAnalysis {
        var surfaces: [DetectedSurface] = []
        var openings: [DetectedOpening] = []
        var entryPoints: [EntryPoint] = []
        var materials: [MaterialEstimate] = []
        var vulnerabilities: [Vulnerability] = []
        
        // Process mesh anchors to find surfaces
        for anchor in result.meshAnchors {
            let geometry = anchor.geometry
            let extractedVertices = geometry.extractVertexPositions()
            let vertexCount = extractedVertices.count

            // Sample vertices to detect surfaces (simplified approach)
            var sampleVertices: [SIMD3<Float>] = []
            let sampleStride = max(1, vertexCount / 100)  // Sample 100 points max

            for i in Swift.stride(from: 0, to: vertexCount, by: sampleStride) {
                let vertex = extractedVertices[i]
                let worldPos = anchor.transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1)
                sampleVertices.append(SIMD3(worldPos.x, worldPos.y, worldPos.z))
            }
            
            // Estimate surface from sampled vertices
            if sampleVertices.count >= 3 {
                let normal = estimateNormalFromPoints(sampleVertices)
                let surfaceType = classifySurface(normal: normal, vertices: sampleVertices)
                
                let surface = DetectedSurface(
                    type: surfaceType,
                    vertices: sampleVertices,
                    normal: normal,
                    area: Float(sampleVertices.count) * 0.01,  // Estimated area
                    material: nil
                )
                surfaces.append(surface)
            }
        }
        
        // Find openings (gaps in walls)
        openings = findOpenings(surfaces: surfaces, pointCloud: result.pointCloud)
        
        // Identify entry points
        for opening in openings {
            let entry = EntryPoint(
                opening: opening,
                difficulty: calculateEntryDifficulty(opening),
                visibility: calculateVisibility(opening, from: result.pointCloud),
                approachOptions: findApproachOptions(to: opening, avoiding: surfaces)
            )
            entryPoints.append(entry)
        }
        
        // Find vulnerabilities
        vulnerabilities = findVulnerabilities(surfaces: surfaces, openings: openings)
        
        return StructuralAnalysis(
            surfaces: surfaces,
            openings: openings,
            entryPoints: entryPoints,
            materialEstimates: materials,
            structuralVulnerabilities: vulnerabilities,
            confidenceScore: calculateConfidence(result)
        )
    }
    
    private func performTerrainAnalysis(_ result: LiDARScanResult) async -> TerrainAnalysis {
        var elevation: [LiDARElevationPoint] = []
        var slopes: [SlopeRegion] = []
        var cover: [CoverPosition] = []
        var deadSpace: [DeadSpaceRegion] = []
        var routes: [RouteOption] = []
        var obstructions: [Obstruction] = []
        
        // Build elevation grid
        let gridSize: Float = 0.5  // meters
        var elevationGrid: [SIMD2<Int>: Float] = [:]
        
        for point in result.pointCloud {
            let gridX = Int(point.x / gridSize)
            let gridZ = Int(point.z / gridSize)
            let key = SIMD2(gridX, gridZ)
            
            if let existing = elevationGrid[key] {
                elevationGrid[key] = min(existing, point.y)  // Use lowest point
            } else {
                elevationGrid[key] = point.y
            }
        }
        
        // Calculate elevation points with slope
        for (gridPos, elev) in elevationGrid {
            let neighbors = [
                SIMD2(gridPos.x + 1, gridPos.y),
                SIMD2(gridPos.x - 1, gridPos.y),
                SIMD2(gridPos.x, gridPos.y + 1),
                SIMD2(gridPos.x, gridPos.y - 1)
            ]
            
            var slope: Float = 0
            var aspect: Float = 0
            var count = 0
            
            for neighbor in neighbors {
                if let neighborElev = elevationGrid[neighbor] {
                    let dElev = neighborElev - elev
                    slope += abs(dElev) / gridSize
                    aspect += atan2(Float(neighbor.y - gridPos.y), Float(neighbor.x - gridPos.x))
                    count += 1
                }
            }
            
            if count > 0 {
                elevation.append(LiDARElevationPoint(
                    position: SIMD2(Float(gridPos.x) * gridSize, Float(gridPos.y) * gridSize),
                    elevation: elev,
                    slope: slope / Float(count),
                    aspect: aspect / Float(count)
                ))
            }
        }
        
        // Find cover positions
        cover = findCoverPositions(pointCloud: result.pointCloud, meshAnchors: result.meshAnchors)

        // Dead space is deferred to performTacticalAnalysis (needs observation posts first)

        // Calculate route options through cover
        routes = calculateRouteOptions(elevation: elevation, cover: cover, obstructions: obstructions)
        
        return TerrainAnalysis(
            elevation: elevation,
            slope: slopes,
            coverPositions: cover,
            deadSpace: deadSpace,
            routeOptions: routes,
            obstructions: obstructions
        )
    }
    
    private func performTacticalAnalysis(_ result: LiDARScanResult, terrain: TerrainAnalysis, structure: StructuralAnalysis) async -> TacticalAnalysis {
        var observationPosts: [ObservationPost] = []
        var fieldsOfFire: [FieldOfFire] = []
        var concealment: [ConcealmentPosition] = []
        var approach: [ApproachRoute] = []
        var escape: [EscapeRoute] = []
        var threats: [ThreatVector] = []
        
        // Find observation posts (high ground with good visibility)
        for elevPoint in terrain.elevation.sorted(by: { $0.elevation > $1.elevation }).prefix(10) {
            let position = SIMD3(elevPoint.position.x, elevPoint.elevation, elevPoint.position.y)
            let coverage = calculateCoverage(from: position, pointCloud: result.pointCloud)
            let concealment = calculateConcealment(at: position, surfaces: structure.surfaces)
            
            if coverage > 0.3 {  // At least 30% coverage
                observationPosts.append(ObservationPost(
                    position: position,
                    fieldOfView: 360,  // Panoramic
                    coverage: coverage,
                    concealment: concealment,
                    accessibility: calculateAccessibility(to: position, terrain: terrain)
                ))
            }
        }
        
        // Calculate fields of fire from key positions
        for op in observationPosts {
            fieldsOfFire.append(calculateFieldOfFire(from: op.position, pointCloud: result.pointCloud))
        }
        
        // Compute dead space now that we have observation posts (fixes circular dependency)
        let deadSpace = findDeadSpace(
            pointCloud: result.pointCloud,
            elevation: terrain.elevation,
            observerPositions: observationPosts.map(\.position)
        )

        // Find concealment positions
        for cover in terrain.coverPositions {
            concealment.append(ConcealmentPosition(
                center: cover.center,
                radius: 1.0,
                visibilityFromThreats: 1.0 - cover.protection,
                egress: findEgressRoutes(from: cover.center, terrain: terrain)
            ))
        }
        
        // Calculate approach routes
        let targetPosition = result.boundingBox.0  // Use min corner as target
        approach = calculateApproachRoutes(to: targetPosition, terrain: terrain, cover: terrain.coverPositions)
        
        // Calculate escape routes
        escape = calculateEscapeRoutes(from: targetPosition, terrain: terrain)
        
        // Identify threat vectors
        threats = identifyThreatVectors(terrain: terrain, structure: structure)
        
        // Overall assessment
        let riskScore = calculateOverallRisk(
            terrain: terrain,
            structure: structure,
            threats: threats
        )
        
        let assessment = generateAssessment(
            observationPosts: observationPosts,
            cover: terrain.coverPositions,
            threats: threats,
            riskScore: riskScore
        )
        
        return TacticalAnalysis(
            observationPosts: observationPosts,
            fieldsOfFire: fieldsOfFire,
            concealmentPositions: concealment,
            approachRoutes: approach,
            escapeRoutes: escape,
            threatVectors: threats,
            overallAssessment: assessment,
            riskScore: riskScore
        )
    }
    
    // MARK: - Helper Functions
    
    private func estimateNormalFromPoints(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard points.count >= 3 else { return SIMD3(0, 1, 0) }
        
        // Use PCA to find dominant plane normal
        let center = points.reduce(SIMD3<Float>.zero) { $0 + $1 } / Float(points.count)
        
        // Simplified: use first 3 points
        let v1 = points[1] - points[0]
        let v2 = points[2] - points[0]
        return normalize(cross(v1, v2))
    }
    
    private func calculateNormal(vertices: [SIMD3<Float>]) -> SIMD3<Float> {
        guard vertices.count >= 3 else { return SIMD3(0, 1, 0) }
        let v1 = vertices[1] - vertices[0]
        let v2 = vertices[2] - vertices[0]
        return normalize(cross(v1, v2))
    }
    
    private func classifySurface(normal: SIMD3<Float>, vertices: [SIMD3<Float>]) -> DetectedSurface.SurfaceType {
        let upDot = abs(dot(normal, SIMD3(0, 1, 0)))
        
        if upDot > 0.9 {
            // Mostly horizontal
            let avgY = vertices.reduce(0) { $0 + $1.y } / Float(vertices.count)
            return avgY < 0.5 ? .ground : .ceiling
        } else if upDot < 0.1 {
            return .wall
        } else {
            return .roof
        }
    }
    
    private func calculateArea(vertices: [SIMD3<Float>]) -> Float {
        guard vertices.count >= 3 else { return 0 }
        let v1 = vertices[1] - vertices[0]
        let v2 = vertices[2] - vertices[0]
        return length(cross(v1, v2)) / 2
    }
    
    private func estimateMaterial(classification: ARMeshClassification?) -> MaterialEstimate? {
        guard let classValue = classification else { return nil }
        
        let material: MaterialEstimate.Material
        switch classValue {
        case .wall: material = .concrete
        case .floor: material = .concrete
        case .ceiling: material = .concrete
        case .table: material = .wood
        case .seat: material = .wood
        case .window: material = .glass
        case .door: material = .wood
        default: material = .unknown
        }
        
        return MaterialEstimate(surfaceId: UUID(), material: material, confidence: 0.7)
    }
    
    private func findOpenings(surfaces: [DetectedSurface], pointCloud: [SIMD3<Float>]) -> [DetectedOpening] {
        var openings: [DetectedOpening] = []
        
        // Find walls and look for gaps
        let walls = surfaces.filter { $0.type == .wall }
        
        for wall in walls {
            // Simplified opening detection
            let avgX = wall.vertices.reduce(0) { $0 + $1.x } / Float(wall.vertices.count)
            let avgY = wall.vertices.reduce(0) { $0 + $1.y } / Float(wall.vertices.count)
            let avgZ = wall.vertices.reduce(0) { $0 + $1.z } / Float(wall.vertices.count)
            
            // Check for nearby gaps in point cloud
            let nearbyPoints = pointCloud.filter { point in
                length(point - SIMD3(avgX, avgY, avgZ)) < 2.0
            }
            
            if nearbyPoints.count < 50 {  // Sparse area might be opening
                openings.append(DetectedOpening(
                    type: avgY > 1.5 ? .window : .door,
                    center: SIMD3(avgX, avgY, avgZ),
                    dimensions: SIMD2(1.0, 2.0),
                    normal: wall.normal,
                    accessibility: 0.8
                ))
            }
        }
        
        return openings
    }
    
    private func calculateEntryDifficulty(_ opening: DetectedOpening) -> Float {
        switch opening.type {
        case .door: return 0.2
        case .window: return 0.5
        case .breach: return 0.8
        case .passage: return 0.3
        case .vent: return 0.9
        }
    }
    
    private func calculateVisibility(_ opening: DetectedOpening, from points: [SIMD3<Float>]) -> Float {
        // Calculate how visible this opening is from surrounding points
        var visibleCount = 0
        for point in points.prefix(1000) {  // Sample
            let direction = normalize(opening.center - point)
            let alignment = abs(dot(direction, opening.normal))
            if alignment > 0.5 {
                visibleCount += 1
            }
        }
        return Float(visibleCount) / Float(min(points.count, 1000))
    }
    
    private func findApproachOptions(to opening: DetectedOpening, avoiding surfaces: [DetectedSurface]) -> [SIMD3<Float>] {
        // Calculate approach vectors that avoid walls
        var approaches: [SIMD3<Float>] = []
        
        let angles: [Float] = [-45, 0, 45]  // Degrees from normal
        for angle in angles {
            let radians = angle * .pi / 180
            let approachDir = SIMD3(
                opening.normal.x * cos(radians) - opening.normal.z * sin(radians),
                0,
                opening.normal.x * sin(radians) + opening.normal.z * cos(radians)
            )
            approaches.append(opening.center + approachDir * 3)  // 3m out
        }
        
        return approaches
    }
    
    private func findVulnerabilities(surfaces: [DetectedSurface], openings: [DetectedOpening]) -> [Vulnerability] {
        var vulnerabilities: [Vulnerability] = []
        
        // Each opening is a potential vulnerability
        for opening in openings {
            vulnerabilities.append(Vulnerability(
                location: opening.center,
                type: .access,
                severity: 1.0 - calculateEntryDifficulty(opening),
                description: "Entry point via \(opening.type)"
            ))
        }
        
        return vulnerabilities
    }
    
    private func findCoverPositions(pointCloud: [SIMD3<Float>], meshAnchors: [ARMeshAnchor]) -> [CoverPosition] {
        var cover: [CoverPosition] = []

        // Stage 1: Point density grid (existing heuristic)
        let gridSize: Float = 1.0
        var pointGrid: [SIMD3<Int>: Int] = [:]

        for point in pointCloud {
            let gridPos = SIMD3(Int(point.x / gridSize), Int(point.y / gridSize), Int(point.z / gridSize))
            pointGrid[gridPos, default: 0] += 1
        }

        for (gridPos, count) in pointGrid where count > 20 {
            let center = SIMD3(Float(gridPos.x) * gridSize, Float(gridPos.y) * gridSize, Float(gridPos.z) * gridSize)

            // Height check: cover must be ≥0.5m above ground to be useful
            let groundLevel = estimateGroundLevel(near: center, pointCloud: pointCloud)
            guard center.y - groundLevel >= 0.5 else { continue }

            cover.append(CoverPosition(
                center: center,
                type: count > 100 ? .hardCover : .concealment,
                protection: min(Float(count) / 200.0, 1.0),
                exposedDirections: calculateExposedDirections(from: center, pointCloud: pointCloud)
            ))
        }

        // Stage 2: ARMeshClassification — walls/seats/tables provide cover
        for anchor in meshAnchors {
            let geometry = anchor.geometry
            guard geometry.classification != nil else { continue }

            let vertices = geometry.extractVertexPositions()
            guard let classifications = geometry.extractClassifications() else { continue }

            // Group wall/seat/table vertices into cover clusters
            var wallVertices: [SIMD3<Float>] = []
            for (i, classification) in classifications.enumerated() where i < vertices.count {
                let worldPos = anchor.transform * SIMD4<Float>(vertices[i], 1.0)
                let pos = SIMD3(worldPos.x, worldPos.y, worldPos.z)

                switch classification {
                case .wall, .seat, .table:
                    wallVertices.append(pos)
                default:
                    break
                }
            }

            // Cluster wall vertices into cover positions (simple grid bucketing)
            var wallGrid: [SIMD3<Int>: [SIMD3<Float>]] = [:]
            for v in wallVertices {
                let key = SIMD3(Int(v.x / gridSize), Int(v.y / gridSize), Int(v.z / gridSize))
                wallGrid[key, default: []].append(v)
            }

            for (_, verts) in wallGrid where verts.count > 5 {
                let avg = verts.reduce(SIMD3<Float>.zero, +) / Float(verts.count)
                let groundLevel = estimateGroundLevel(near: avg, pointCloud: pointCloud)
                guard avg.y - groundLevel >= 0.5 else { continue }

                // Avoid duplicating existing density-based covers
                let isDuplicate = cover.contains { length($0.center - avg) < gridSize }
                if !isDuplicate {
                    cover.append(CoverPosition(
                        center: avg,
                        type: .hardCover,
                        protection: min(Float(verts.count) / 50.0, 1.0),
                        exposedDirections: calculateExposedDirections(from: avg, pointCloud: pointCloud)
                    ))
                }
            }
        }

        // Stage 3: YOLO vehicle detections as hard cover — deferred (pipeline not active)

        return cover
    }

    private func estimateGroundLevel(near position: SIMD3<Float>, pointCloud: [SIMD3<Float>]) -> Float {
        // Find lowest points within 2m horizontal radius as ground estimate
        let nearby = pointCloud.filter {
            let dx = $0.x - position.x
            let dz = $0.z - position.z
            return (dx * dx + dz * dz) < 4.0
        }
        return nearby.map(\.y).min() ?? position.y
    }
    
    private func calculateExposedDirections(from position: SIMD3<Float>, pointCloud: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let directions: [SIMD3<Float>] = [
            SIMD3(1, 0, 0), SIMD3(-1, 0, 0),
            SIMD3(0, 0, 1), SIMD3(0, 0, -1),
            SIMD3(0.707, 0, 0.707), SIMD3(0.707, 0, -0.707),
            SIMD3(-0.707, 0, 0.707), SIMD3(-0.707, 0, -0.707)
        ]
        
        var exposed: [SIMD3<Float>] = []
        
        for dir in directions {
            // Check if there's cover in this direction
            let checkPoint = position + dir * 2
            let nearbyPoints = pointCloud.filter { length($0 - checkPoint) < 1.0 }
            
            if nearbyPoints.count < 10 {  // Not much cover
                exposed.append(dir)
            }
        }
        
        return exposed
    }
    
    private func findDeadSpace(pointCloud: [SIMD3<Float>], elevation: [LiDARElevationPoint], observerPositions: [SIMD3<Float>] = []) -> [DeadSpaceRegion] {
        var deadSpaceRegions: [DeadSpaceRegion] = []

        guard !observerPositions.isEmpty && !pointCloud.isEmpty else { return [] }

        // Divide terrain into grid cells
        let gridSize: Float = 2.0  // 2-meter grid cells
        var minX = Float.infinity, maxX = -Float.infinity
        var minZ = Float.infinity, maxZ = -Float.infinity

        for point in pointCloud {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }

        let gridCols = Int((maxX - minX) / gridSize) + 1
        let gridRows = Int((maxZ - minZ) / gridSize) + 1

        // For each grid cell, check visibility from observer positions
        for row in 0..<gridRows {
            for col in 0..<gridCols {
                let cellCenterX = minX + Float(col) * gridSize + gridSize / 2
                let cellCenterZ = minZ + Float(row) * gridSize + gridSize / 2

                // Find Y coordinate at this location from elevation
                let cellPos = SIMD3<Float>(cellCenterX, 0, cellCenterZ)
                var cellY: Float = 0

                var closestDist = Float.infinity
                for point in pointCloud {
                    let dist = simd_distance(cellPos, point)
                    if dist < closestDist {
                        closestDist = dist
                        cellY = point.y
                    }
                }

                // Check if visible from any observer
                var isVisible = false
                for observer in observerPositions {
                    let toCell = cellPos - observer
                    let distance = simd_length(toCell)

                    // Simple line-of-sight check: raytrace a few steps
                    var blocked = false
                    let steps = Int(distance / 0.5)

                    for step in 1...steps {
                        let t = Float(step) / Float(steps)
                        let checkPoint = observer + toCell * t

                        // Check if any point cloud point blocks this ray
                        for cloudPoint in pointCloud.prefix(500) {
                            if simd_distance(checkPoint, cloudPoint) < 0.5 {
                                blocked = true
                                break
                            }
                        }
                        if blocked { break }
                    }

                    if !blocked {
                        isVisible = true
                        break
                    }
                }

                // If not visible, mark as dead space
                if !isVisible && !observerPositions.isEmpty {
                    let deadSpaceVerts = [
                        SIMD3<Float>(cellCenterX - gridSize/2, cellY, cellCenterZ - gridSize/2),
                        SIMD3<Float>(cellCenterX + gridSize/2, cellY, cellCenterZ - gridSize/2),
                        SIMD3<Float>(cellCenterX + gridSize/2, cellY, cellCenterZ + gridSize/2),
                        SIMD3<Float>(cellCenterX - gridSize/2, cellY, cellCenterZ + gridSize/2)
                    ]

                    deadSpaceRegions.append(DeadSpaceRegion(
                        vertices: deadSpaceVerts,
                        fromPositions: observerPositions,
                        accessibility: 0.8
                    ))
                }
            }
        }

        return deadSpaceRegions
    }
    
    private func calculateRouteOptions(elevation: [LiDARElevationPoint], cover: [CoverPosition], obstructions: [Obstruction]) -> [RouteOption] {
        guard cover.count >= 2 else { return [] }

        var routes: [RouteOption] = []

        // Build elevation lookup for slope penalty
        var elevLookup: [SIMD2<Int>: Float] = [:]
        for ep in elevation {
            let key = SIMD2(Int(ep.position.x * 2), Int(ep.position.y * 2))
            elevLookup[key] = ep.elevation
        }

        // Route 1: Low-exposure path through cover positions (greedy nearest-neighbor)
        var visited = Set<Int>()
        var waypoints: [SIMD3<Float>] = [cover[0].center]
        visited.insert(0)
        var totalDist: Float = 0
        var maxExposure: Float = 0

        while visited.count < min(cover.count, 8) {
            let current = waypoints.last!
            var bestIdx = -1
            var bestDist: Float = .infinity
            for (i, c) in cover.enumerated() where !visited.contains(i) {
                let d = simd_distance(current, c.center)
                if d < bestDist {
                    bestDist = d
                    bestIdx = i
                }
            }
            guard bestIdx >= 0 else { break }
            visited.insert(bestIdx)
            waypoints.append(cover[bestIdx].center)
            totalDist += bestDist
            maxExposure = max(maxExposure, 1.0 - cover[bestIdx].protection)
        }

        if waypoints.count >= 2 {
            let elevGain = abs((waypoints.last?.y ?? 0) - (waypoints.first?.y ?? 0))
            routes.append(RouteOption(
                waypoints: waypoints,
                distance: totalDist,
                elevation: elevGain,
                exposure: maxExposure,
                difficulty: min(elevGain / 10.0 + maxExposure * 0.5, 1.0),
                estimatedTime: TimeInterval(totalDist / 1.2) // ~1.2 m/s walking
            ))
        }

        // Route 2: Direct route (shortest path, higher exposure)
        if cover.count >= 2 {
            let start = cover[0].center
            let end = cover[cover.count - 1].center
            let directDist = simd_distance(start, end)
            routes.append(RouteOption(
                waypoints: [start, end],
                distance: directDist,
                elevation: abs(end.y - start.y),
                exposure: 0.8,
                difficulty: 0.3,
                estimatedTime: TimeInterval(directDist / 1.5)
            ))
        }

        return routes
    }
    
    private func calculateCoverage(from position: SIMD3<Float>, pointCloud: [SIMD3<Float>]) -> Float {
        // Calculate percentage of area visible from position
        let maxRange: Float = 50.0
        var visibleCount = 0
        
        for point in pointCloud.prefix(1000) {
            let distance = length(point - position)
            if distance < maxRange {
                visibleCount += 1
            }
        }
        
        return Float(visibleCount) / Float(min(pointCloud.count, 1000))
    }
    
    private func calculateConcealment(at position: SIMD3<Float>, surfaces: [DetectedSurface]) -> Float {
        var concealment: Float = 0
        
        for surface in surfaces {
            let avgPos = surface.vertices.reduce(SIMD3<Float>.zero) { $0 + $1 } / Float(surface.vertices.count)
            let distance = length(avgPos - position)
            
            if distance < 3.0 {  // Within 3 meters
                concealment += surface.area / 10.0  // Contribute based on area
            }
        }
        
        return min(concealment, 1.0)
    }
    
    private func calculateAccessibility(to position: SIMD3<Float>, terrain: TerrainAnalysis) -> Float {
        // Find nearest elevation point to get local slope
        let posXZ = SIMD2(position.x, position.z)
        var nearestSlope: Float = 0
        var nearestDist: Float = .infinity

        for ep in terrain.elevation {
            let d = simd_distance(posXZ, ep.position)
            if d < nearestDist {
                nearestDist = d
                nearestSlope = ep.slope
            }
        }

        // Slope penalty: flat (0°) = 1.0, steep (45°+) = 0.1
        let slopePenalty = max(0.1, 1.0 - nearestSlope / 1.0) // slope is rise/run, 1.0 = 45°

        // Obstruction penalty: count obstructions within 3m of position
        let obstructionCount = terrain.obstructions.filter {
            simd_distance($0.center, position) < 3.0
        }.count
        let obstructionPenalty = max(0.2, 1.0 - Float(obstructionCount) * 0.3)

        return slopePenalty * obstructionPenalty
    }
    
    private func calculateFieldOfFire(from position: SIMD3<Float>, pointCloud: [SIMD3<Float>]) -> FieldOfFire {
        var sectors: [FieldOfFire.Sector] = []

        // Divide into 8 sectors and raycast against point cloud
        for i in 0..<8 {
            let azStart = Float(i) * 45.0
            let azEnd = Float(i + 1) * 45.0
            let azStartRad = azStart * .pi / 180.0
            let azEndRad = azEnd * .pi / 180.0

            var obstacleCount = 0
            var maxRange: Float = 0

            // Check point cloud points in this sector
            for point in pointCloud {
                let delta = point - position
                let horizontalDist = sqrt(delta.x * delta.x + delta.z * delta.z)
                guard horizontalDist > 0.5 else { continue } // Skip points at origin

                let azimuth = atan2(delta.x, delta.z) // radians, 0 = +Z
                let azDeg = azimuth * 180.0 / .pi
                let normalizedAz = azDeg < 0 ? azDeg + 360.0 : azDeg

                if normalizedAz >= azStart && normalizedAz < azEnd {
                    maxRange = max(maxRange, horizontalDist)

                    // Points above eye level within range are obstacles
                    if delta.y > 0.3 && horizontalDist < 50.0 {
                        obstacleCount += 1
                    }
                }
            }

            sectors.append(FieldOfFire.Sector(
                azimuthStart: azStart,
                azimuthEnd: azEnd,
                maxRange: maxRange > 0 ? maxRange : 50.0,
                obstacleCount: obstacleCount
            ))
        }

        return FieldOfFire(origin: position, sectors: sectors, deadSpaces: [])
    }
    
    private func findEgressRoutes(from position: SIMD3<Float>, terrain: TerrainAnalysis) -> [SIMD3<Float>] {
        // Find exit directions: pick the 3 nearest cover positions in different directions
        let candidates = terrain.coverPositions
            .filter { simd_distance($0.center, position) > 2.0 } // At least 2m away
            .sorted { simd_distance($0.center, position) < simd_distance($1.center, position) }

        var egress: [SIMD3<Float>] = []
        var usedDirections: [SIMD3<Float>] = []

        for candidate in candidates {
            let dir = simd_normalize(candidate.center - position)
            // Only add if direction is sufficiently different from existing egress routes
            let isTooSimilar = usedDirections.contains { simd_dot($0, dir) > 0.7 }
            if !isTooSimilar {
                egress.append(candidate.center)
                usedDirections.append(dir)
                if egress.count >= 3 { break }
            }
        }

        return egress
    }
    
    private func calculateApproachRoutes(to target: SIMD3<Float>, terrain: TerrainAnalysis, cover: [CoverPosition]) -> [ApproachRoute] {
        guard !cover.isEmpty else { return [] }

        var routes: [ApproachRoute] = []

        // Strategy 1: Route through cover positions (low-visibility path)
        var lowVisibilityWaypoints: [SIMD3<Float>] = []
        lowVisibilityWaypoints.append(lastScanResult?.lidarPosition ?? SIMD3<Float>.zero)

        // Sort cover positions by distance to target and visibility
        let sortedCover = cover.sorted { cover1, cover2 in
            let dist1 = simd_distance(cover1.center, target)
            let dist2 = simd_distance(cover2.center, target)
            let vis1 = cover1.visibilityFromThreats
            let vis2 = cover2.visibilityFromThreats

            // Prefer closer, lower-visibility positions
            return (dist1 + vis1) < (dist2 + vis2)
        }

        // Add intermediate cover positions to route
        for i in 0..<min(3, sortedCover.count) {
            lowVisibilityWaypoints.append(sortedCover[i].center)
        }
        lowVisibilityWaypoints.append(target)

        // Calculate metrics
        var totalDistance: Float = 0
        var maxExposure: Float = 0
        var maxDifficulty: Float = 0

        for i in 0..<(lowVisibilityWaypoints.count - 1) {
            let segment = lowVisibilityWaypoints[i + 1] - lowVisibilityWaypoints[i]
            totalDistance += simd_length(segment)

            // Estimate difficulty from slope
            let elevation = segment.y / max(0.1, simd_length(SIMD2<Float>(segment.x, segment.z)))
            maxDifficulty = max(maxDifficulty, min(abs(elevation), 1.0))
        }

        // Calculate exposure (inverse of visibility from threats)
        maxExposure = sortedCover.isEmpty ? 0.5 : cover.map { $0.visibilityFromThreats }.max() ?? 0.5

        let timeEstimate = TimeInterval(totalDistance / 1.4)  // ~1.4 m/s walking speed

        routes.append(ApproachRoute(
            waypoints: lowVisibilityWaypoints,
            coverPositions: Array(sortedCover.prefix(3)),
            exposureScore: maxExposure,
            estimatedTime: timeEstimate,
            difficulty: maxDifficulty
        ))

        // Strategy 2: Direct route (fastest, highest visibility)
        let directStart = lastScanResult?.lidarPosition ?? SIMD3<Float>.zero
        let directRoute = [directStart, target]
        let directDistance = simd_distance(directStart, target)
        let directTime = TimeInterval(directDistance / 1.4)

        routes.append(ApproachRoute(
            waypoints: directRoute,
            coverPositions: [],
            exposureScore: 0.8,
            estimatedTime: directTime,
            difficulty: abs((target.y - directStart.y) / max(0.1, directDistance))
        ))

        return routes
    }
    
    private func calculateEscapeRoutes(from position: SIMD3<Float>, terrain: TerrainAnalysis) -> [EscapeRoute] {
        var escapeRoutes: [EscapeRoute] = []

        // Find nearby cover positions and sort by speed/accessibility
        let coverOptions = terrain.coverPositions.sorted { cover1, cover2 in
            let dist1 = simd_distance(cover1.center, position)
            let dist2 = simd_distance(cover2.center, position)
            let accessibility1 = cover1.accessibility
            let accessibility2 = cover2.accessibility

            // Prefer closer, more accessible positions
            return (dist1 / max(0.1, accessibility1)) < (dist2 / max(0.1, accessibility2))
        }

        // Generate up to 3 escape routes
        for i in 0..<min(3, coverOptions.count) {
            let targetCover = coverOptions[i]
            let distance = simd_distance(position, targetCover.center)

            // Build route through intermediate cover if available
            var waypoints: [SIMD3<Float>] = [position]

            // Add intermediate waypoint for longer routes
            if distance > 10.0 && i < coverOptions.count - 1 {
                let intermediate = coverOptions[i + 1]
                waypoints.append(intermediate.center)
            }

            waypoints.append(targetCover.center)

            // Calculate metrics
            let totalDistance = waypoints.dropFirst().reduce(0.0) { acc, point in
                acc + simd_distance(waypoints[waypoints.count - 1], point)
            }

            // Assume max sprint speed ~4 m/s for short distances
            let speed = min(4.0, 10.0 / max(0.5, targetCover.accessibility))
            let timeToEscape = TimeInterval(totalDistance / speed)

            // Risk score: combination of exposure and distance
            let averageExposure = (coverOptions.prefix(i + 1).map { $0.visibilityFromThreats }.reduce(0, +) / Float(i + 1))
            let riskScore = averageExposure + (distance / 50.0)  // Further is less risky

            escapeRoutes.append(EscapeRoute(
                waypoints: waypoints,
                coverPositions: [targetCover],
                exitPoints: coverOptions.prefix(2).map { $0.center },
                speed: speed,
                riskScore: min(riskScore, 1.0)
            ))
        }

        return escapeRoutes
    }
    
    private func identifyThreatVectors(terrain: TerrainAnalysis, structure: StructuralAnalysis) -> [ThreatVector] {
        var threats: [ThreatVector] = []
        
        // Each opening is a potential threat vector
        for opening in structure.openings {
            threats.append(ThreatVector(
                origin: opening.center,
                direction: opening.normal,
                probability: opening.accessibility,
                type: .visual
            ))
        }
        
        return threats
    }
    
    private func calculateOverallRisk(terrain: TerrainAnalysis, structure: StructuralAnalysis, threats: [ThreatVector]) -> Float {
        let coverScore = Float(terrain.coverPositions.count) / 10.0
        let threatScore = Float(threats.count) / 5.0
        let vulnerabilityScore = Float(structure.structuralVulnerabilities.count) / 5.0
        
        return min((threatScore + vulnerabilityScore) / (1 + coverScore), 1.0)
    }
    
    private func generateAssessment(observationPosts: [ObservationPost], cover: [CoverPosition], threats: [ThreatVector], riskScore: Float) -> String {
        var assessment = "Tactical Assessment:\n"
        
        assessment += "- \(observationPosts.count) observation positions identified\n"
        assessment += "- \(cover.count) cover positions available\n"
        assessment += "- \(threats.count) potential threat vectors\n"
        assessment += "- Overall risk: \(riskScore < 0.3 ? "LOW" : riskScore < 0.7 ? "MEDIUM" : "HIGH")\n"
        
        if let bestOP = observationPosts.first {
            assessment += "- Best observation post: \(String(format: "%.1f, %.1f, %.1f", bestOP.position.x, bestOP.position.y, bestOP.position.z))\n"
        }
        
        return assessment
    }
    
    private func calculateBoundingBox() -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard !collectedPoints.isEmpty else {
            return (SIMD3.zero, SIMD3.zero)
        }
        
        var minP = collectedPoints[0]
        var maxP = collectedPoints[0]
        
        for point in collectedPoints {
            minP = min(minP, point)
            maxP = max(maxP, point)
        }
        
        return (minP, maxP)
    }
    
    private func calculateConfidence(_ result: LiDARScanResult) -> Float {
        let pointDensity = Float(result.pointCount) / 10000.0
        let scanDuration = Float(result.scanDuration) / 30.0
        return min((pointDensity + scanDuration) / 2, 1.0)
    }

    /// Build a 2D DEM grid from point cloud (used by HazardDetector).
    /// Returns [[Float]] where grid[row][col] = min elevation.
    private func buildDEMGrid(from points: [SIMD3<Float>], cellSize: Float) -> [[Float]] {
        guard !points.isEmpty else { return [] }

        var gridDict: [SIMD2<Int>: Float] = [:]
        for p in points {
            let key = SIMD2(Int(floor(p.x / cellSize)), Int(floor(p.z / cellSize)))
            if let existing = gridDict[key] {
                gridDict[key] = min(existing, p.y)
            } else {
                gridDict[key] = p.y
            }
        }

        guard !gridDict.isEmpty else { return [] }
        let allKeys = Array(gridDict.keys)
        let minX = allKeys.map(\.x).min()!, maxX = allKeys.map(\.x).max()!
        let minZ = allKeys.map(\.y).min()!, maxZ = allKeys.map(\.y).max()!
        let rows = maxZ - minZ + 1
        let cols = maxX - minX + 1

        var grid = [[Float]](repeating: [Float](repeating: .nan, count: cols), count: rows)
        for (key, elev) in gridDict {
            grid[key.y - minZ][key.x - minX] = elev
        }
        return grid
    }

    // MARK: - 3D Export

    /// Save point cloud as binary (100x faster than ASCII PLY)
    private func savePointsBinary(_ points: [SIMD3<Float>], to url: URL) async throws {
        guard !points.isEmpty else { return }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var count = UInt32(points.count)
        handle.write(Data(bytes: &count, count: 4))
        let chunkSize = 85_000
        for chunkStart in stride(from: 0, to: points.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, points.count)
            var data = Data(capacity: (chunkEnd - chunkStart) * 12)
            for point in points[chunkStart..<chunkEnd] {
                var p = point
                data.append(Data(bytes: &p, count: 12))
            }
            handle.write(data)
            await Task.yield()
        }
        try handle.close()
    }

    /// Async export AR mesh anchors to USDZ format
    private func exportMeshToUSDZAsync(_ anchors: [ARMeshAnchor], to url: URL) async throws {
        guard !anchors.isEmpty else { return }
        let scene = SCNScene()
        for anchor in anchors {
            if let node = scnNodeFromMeshAnchor(anchor) {
                scene.rootNode.addChildNode(node)
            }
        }
        guard !scene.rootNode.childNodes.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            scene.write(to: url, options: nil, delegate: nil) { progress, error, stop in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if progress >= 1.0 {
                    continuation.resume()
                }
            }
        }
    }

    /// Convert ARMeshAnchor to SCNNode with geometry
    private func scnNodeFromMeshAnchor(_ anchor: ARMeshAnchor) -> SCNNode? {
        let geometry = anchor.geometry
        let vertexCount = geometry.vertices.count

        guard vertexCount > 0 else { return nil }

        // Extract vertices
        var positions: [SCNVector3] = []
        let vertexBuffer = geometry.vertices.buffer.contents()
        let vertexStride = geometry.vertices.stride
        let vertexOffset = geometry.vertices.offset

        for i in 0..<vertexCount {
            let ptr = vertexBuffer.advanced(by: vertexOffset + i * vertexStride)
                .bindMemory(to: SIMD3<Float>.self, capacity: 1)
            let localPosition = ptr.pointee

            // Transform to world coordinates
            let worldPosition = anchor.transform * SIMD4<Float>(localPosition.x, localPosition.y, localPosition.z, 1)
            positions.append(SCNVector3(worldPosition.x, worldPosition.y, worldPosition.z))
        }

        // Extract face indices
        let faceCount = geometry.faces.count
        var indices: [UInt32] = []

        if faceCount > 0 {
            let indexBuffer = geometry.faces.buffer.contents()
            let bytesPerIndex = geometry.faces.bytesPerIndex

            for i in 0..<(faceCount * 3) {
                let ptr = indexBuffer.advanced(by: i * bytesPerIndex)

                if bytesPerIndex == 4 {
                    indices.append(ptr.bindMemory(to: UInt32.self, capacity: 1).pointee)
                } else if bytesPerIndex == 2 {
                    indices.append(UInt32(ptr.bindMemory(to: UInt16.self, capacity: 1).pointee))
                }
            }
        }

        // Create SCNGeometry
        let positionSource = SCNGeometrySource(vertices: positions)

        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: faceCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let scnGeometry = SCNGeometry(sources: [positionSource], elements: [element])

        // Apply material based on mesh classification (optional enhancement)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.gray.withAlphaComponent(0.8)
        material.isDoubleSided = true
        scnGeometry.materials = [material]

        let node = SCNNode(geometry: scnGeometry)
        return node
    }
}

// MARK: - Depth Buffer Point Extraction

extension LiDARCaptureEngine {
    /// Extract 3D points from depth buffer - FAST path for dense point clouds
    /// Tactical mode: stride=1, every pixel, ~192K pts/frame @ 60fps
    /// Called off main actor — config passed as value to avoid data race
    nonisolated func extractPointsFromDepth(
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        camera: ARCamera,
        transform: simd_float4x4,
        config: LiDARScanConfig = LiDARScanConfig()
    ) -> [SIMD3<Float>] {
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return [] }
        let depthPointer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        // Get camera intrinsics for unprojection
        let intrinsics = camera.intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        
        var points: [SIMD3<Float>] = []
        
        // Always capture at maximum quality — analysis choice comes AFTER scan
        // stride=2 gives ~50K pts/frame, excellent balance of speed and detail
        // stride=1 is too memory-heavy for most use cases
        let stride = 2
        let expectedPoints = (width / stride) * (height / stride)
        points.reserveCapacity(expectedPoints)
        
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.stride
        
        for y in Swift.stride(from: 0, to: height, by: stride) {
            for x in Swift.stride(from: 0, to: width, by: stride) {
                let index = y * floatsPerRow + x
                let depth = depthPointer[index]
                
                // Skip invalid depths - tactical mode extends range
                let maxDepth: Float = config.maxRange
                guard depth > 0.05 && depth < maxDepth else { continue }
                
                // Unproject to camera space
                let xCam = (Float(x) - cx) * depth / fx
                let yCam = (Float(y) - cy) * depth / fy
                let zCam = depth
                
                // Transform to world space
                let cameraPoint = SIMD4<Float>(xCam, -yCam, -zCam, 1.0)  // Flip Y and Z for ARKit convention
                let worldPoint = transform * cameraPoint
                
                points.append(SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z))
            }
        }
        
        return points
    }
}

// MARK: - ARSessionDelegate

extension LiDARCaptureEngine: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Capture frame data immediately (ARFrame is not Sendable after delegate returns)
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else { return }
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        let camera = frame.camera
        let transform = frame.camera.transform
        let frameTimestamp = frame.timestamp

        // Capture the full ARFrame for pipeline processing (YOLO, Kalman update)
        let capturedFrame = frame

        Task { @MainActor [weak self] in
            guard let self, isScanning else { return }

            // Pipeline Kalman fusion deferred (pipeline stack not yet in build phase)
            let fusedTransform = transform

            // Snapshot config + LingBot engine on main actor (safe), dispatch extraction off-thread
            let capturedConfig = config
            let capturedLingBot = lingBotEngine
            let capturedIntrinsics = camera.intrinsics
            let capturedTimestamp = Float(frameTimestamp)

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }

                // Extract points OFF the main thread — doesn't block UI at all
                let newPoints = self.extractPointsFromDepth(
                    depthMap: depthMap,
                    confidenceMap: confidenceMap,
                    camera: camera,
                    transform: fusedTransform,
                    config: capturedConfig
                )

                let newPointsFinal = newPoints

                // Feed into LingBot-Map streaming state (TSDF + GCA keyframes)
                if let lbe = capturedLingBot {
                    Task.detached(priority: .utility) {
                        await lbe.integrateFrame(
                            points: newPointsFinal,
                            normals: nil,
                            cameraTransform: fusedTransform,
                            intrinsics: capturedIntrinsics,
                            timestamp: capturedTimestamp
                        )
                    }
                }

                // ICP scan matching — injects position corrections into BreadcrumbEngine
                // when GPS degrades (activates at >30m accuracy, matches DR fallback threshold).
                // Runs every 10 frames (~3 Hz at 30 fps) to avoid blocking the frame pipeline.
                let capturedFrameCount = await MainActor.run { self.frameCount }
                if capturedFrameCount % 10 == 0 {
                    let gpsAccuracy = await MainActor.run { BreadcrumbEngine.shared.lastGPSAccuracy }
                    let matcher = self.scanMatcher
                    Task.detached(priority: .utility) {
                        if let correction = matcher.match(
                            incoming: newPointsFinal,
                            gpsAccuracy: gpsAccuracy
                        ) {
                            await MainActor.run {
                                BreadcrumbEngine.shared.injectScanMatchCorrection(correction)
                            }
                        }
                    }
                }

                // Minimal main actor hop: append + update coverage + periodic streaming updates
                await MainActor.run {
                    guard self.isScanning else { return }
                    self.frameCount += 1

                    // Check memory limit before adding more points
                    if self.streamedPointCount >= self.maxPointCount {
                        if !self.hasWarnedPointLimit {
                            self.hasWarnedPointLimit = true
                            self.analysisStatus = "Point limit reached (10M). Stop scan to save."
                        }
                        return
                    }

                    // Always capture every frame for maximum quality
                    self.streamPointsToDisk(newPointsFinal)

                    // Update coverage grid based on camera look direction
                    let forward = SIMD3<Float>(-transform.columns.2.x, -transform.columns.2.y, -transform.columns.2.z)
                    let yaw = atan2(forward.x, forward.z)  // -π to π
                    let pitch = asin(forward.y)  // -π/2 to π/2

                    let col = Int((yaw + .pi) / (2 * .pi) * 8) % 8
                    let row = Int((pitch + .pi/2) / .pi * 8) % 8

                    self.coverageGrid[row][col] += Float(newPointsFinal.count) / 10000.0
                    if self.coverageGrid[row][col] > self.maxCellDensity {
                        self.maxCellDensity = self.coverageGrid[row][col]
                    }

                    // Streaming SceneTag update every 30 frames (~1 Hz at 30 fps)
                    if self.frameCount % 30 == 0, let lbe = capturedLingBot {
                        self.updateStreamingCovers(lbe.queryCoverCandidates())
                    }
                }
            }
        }
        
        Task { @MainActor in
            guard isScanning else { return }
            
            // Update progress based on collected data (targeting 200K for 95%)
            scanProgress = min(Float(collectedPoints.count) / Float(Self.goodScanPoints), 0.99)
            currentPointCount = collectedPoints.count
            
            // Calculate points per second for rate guidance
            let now = Date()
            let elapsed = now.timeIntervalSince(lastRateCheck)
            if elapsed >= 1.0 {
                pointsPerSecond = Int(Double(collectedPoints.count - lastPointCount) / elapsed)
                lastPointCount = collectedPoints.count
                lastRateCheck = now
                
                // Update guidance based on point rate and total count
                updateScanGuidance()
            }
            
            // Check minimum threshold (with haptic feedback)
            if !hasReachedMinimum && collectedPoints.count >= Self.minimumUsablePoints {
                hasReachedMinimum = true
                // Trigger haptic
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
    
    private func updateScanGuidance() {
        let points = collectedPoints.count
        let rate = pointsPerSecond
        
        // Priority order for guidance
        if points >= Self.excellentScanPoints {
            scanGuidance = .excellentScan
        } else if points >= Self.goodScanPoints {
            scanGuidance = .goodScan
        } else if points >= Self.minimumUsablePoints {
            scanGuidance = .minimumReached
        } else if rate < 1000 && points > 5000 {
            // Low point rate - probably scanning too fast or too far away
            scanGuidance = .scanSlower
        } else if rate < 500 && points > 10000 {
            // Very low rate - probably too far
            scanGuidance = .moveCloser
        } else if points > 20000 {
            scanGuidance = .keepGoing
        } else {
            scanGuidance = .goodCoverage
        }
    }
    
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    // Check memory limit before adding mesh points
                    if streamedPointCount >= maxPointCount {
                        if !hasWarnedPointLimit {
                            hasWarnedPointLimit = true
                            analysisStatus = "Point limit reached (10M). Stop scan to save."
                        }
                        continue
                    }

                    meshAnchors.append(meshAnchor)

                    // Extract points from mesh
                    let geometry = meshAnchor.geometry
                    let vertices = geometry.extractVertexPositions()

                    // Accumulate mesh vertices into a local array, then stream
                    var meshPoints: [SIMD3<Float>] = []
                    for i in 0..<vertices.count {
                        let vertex = vertices[i]
                        let worldPos = meshAnchor.transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1)
                        meshPoints.append(SIMD3(worldPos.x, worldPos.y, worldPos.z))
                    }
                    streamPointsToDisk(meshPoints)
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Update existing mesh anchors
    }
}

// MARK: - CLLocationManagerDelegate

extension LiDARCaptureEngine: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last?.coordinate
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            currentHeading = newHeading.trueHeading
        }
    }
}

// MARK: - ARMeshGeometry Extension

extension ARMeshGeometry {
    func extractVertexPositions() -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        let vertexSource = self.vertices
        let count = vertexSource.count
        result.reserveCapacity(Int(count))

        let buffer = vertexSource.buffer
        let stride = vertexSource.stride
        let offset = vertexSource.offset

        for i in 0..<Int(count) {
            let elementOffset = offset + i * stride
            let pointer = buffer.contents().advanced(by: elementOffset)
            let vertex = pointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            result.append(vertex)
        }
        return result
    }

    func extractClassifications() -> [ARMeshClassification]? {
        guard let classificationSource = self.classification else { return nil }
        var result: [ARMeshClassification] = []
        let count = classificationSource.count
        result.reserveCapacity(Int(count))

        let buffer = classificationSource.buffer
        let stride = classificationSource.stride
        let offset = classificationSource.offset

        for i in 0..<Int(count) {
            let elementOffset = offset + i * stride
            let pointer = buffer.contents().advanced(by: elementOffset)
            let classification = pointer.assumingMemoryBound(to: ARMeshClassification.self).pointee
            result.append(classification)
        }
        return result
    }
}

// MARK: - ScanMode Extensions

extension LiDARScanConfig.ScanMode: CaseIterable {
    public static var allCases: [LiDARScanConfig.ScanMode] {
        [.standard, .structural, .terrain, .tactical, .concealment]
    }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .structural: return "Structural"
        case .terrain: return "Terrain"
        case .tactical: return "Tactical"
        case .concealment: return "Concealment"
        }
    }

    var description: String {
        switch self {
        case .standard: return "General-purpose scan for documentation and basic analysis"
        case .structural: return "Identifies surfaces, openings, entry points, and material estimates"
        case .terrain: return "Maps elevation, slope, cover positions, and dead space"
        case .tactical: return "Full analysis: OPs, fields of fire, approach routes, threat vectors"
        case .concealment: return "Identifies positions offering cover from observation and fire"
        }
    }

    var hudColor: Color {
        switch self {
        case .standard: return ZDDesign.skyBlue
        case .structural: return ZDDesign.safetyYellow
        case .terrain: return ZDDesign.forestGreen
        case .tactical: return ZDDesign.signalRed
        case .concealment: return ZDDesign.darkSage
        }
    }
}
