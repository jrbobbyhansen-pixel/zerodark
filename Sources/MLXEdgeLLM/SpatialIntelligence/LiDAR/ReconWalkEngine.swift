import Foundation
import ARKit
import RealityKit
import CoreLocation
import AVFoundation
import Combine
import SceneKit
import UIKit

// MARK: - Models

struct ReconWalkSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var breadcrumbs: [Breadcrumb]
    var segmentCount: Int
    var totalDistance: Double
    var totalPoints: Int
    var coverageArea: Double
    var duration: TimeInterval

    struct Breadcrumb: Codable {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        let heading: Double
        let altitude: Double
    }
}

struct ReconWalkConfig {
    var segmentInterval: TimeInterval = 30
    var captureVideo: Bool = true
    var breadcrumbInterval: TimeInterval = 1.0
    var covertMode: CovertMode = .none

    enum CovertMode: String, CaseIterable {
        case none, texting, photo, map
        var label: String {
            switch self {
            case .none: return "Normal"
            case .texting: return "Texting"
            case .photo: return "Photo"
            case .map: return "Map"
            }
        }
    }
}

// MARK: - ReconWalkEngine

@MainActor
final class ReconWalkEngine: NSObject, ObservableObject {
    static let shared = ReconWalkEngine()

    @Published var isRecording = false
    @Published var currentSession: ReconWalkSession?
    @Published var elapsedTime: TimeInterval = 0
    @Published var distanceWalked: Double = 0
    @Published var pointCount: Int = 0
    @Published var segmentCount: Int = 0
    @Published var coverageArea: Double = 0
    @Published var currentSpeed: Double = 0

    var config = ReconWalkConfig()
    var arSession: ARSession?

    private var locationManager = CLLocationManager()
    private var startLocation: CLLocation?
    private var lastLocation: CLLocation?
    private var sessionTimer: Timer?
    private var segmentTimer: Timer?
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var collectedPoints: [SIMD3<Float>] = []
    private var sessionDirectory: URL?
    private var currentSegmentIndex = 0

    // Video
    private var videoWriter: AVAssetWriter?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoInput: AVAssetWriterInput?
    private var videoStartTime: CMTime?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 1
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Start/Stop

    func startReconWalk() {
        guard !isRecording else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReconWalks/\(timestamp)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionDirectory = dir

        currentSession = ReconWalkSession(
            id: UUID(), startTime: Date(), breadcrumbs: [],
            segmentCount: 0, totalDistance: 0, totalPoints: 0, coverageArea: 0, duration: 0
        )

        setupARSession()
        if config.captureVideo { setupVideoCapture(dir: dir) }
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        startTimers()

        isRecording = true
        elapsedTime = 0; distanceWalked = 0; pointCount = 0; segmentCount = 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func stopReconWalk() {
        guard isRecording else { return }

        saveCurrentSegment()
        arSession?.pause()
        finalizeVideoCapture()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        sessionTimer?.invalidate()
        segmentTimer?.invalidate()

        currentSession?.endTime = Date()
        currentSession?.duration = elapsedTime
        currentSession?.totalDistance = distanceWalked
        currentSession?.totalPoints = pointCount
        currentSession?.coverageArea = coverageArea

        saveSessionMetadata()
        isRecording = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - AR Session

    private func setupARSession() {
        arSession = ARSession()
        arSession?.delegate = self

        let cfg = ARWorldTrackingConfiguration()
        cfg.sceneReconstruction = .meshWithClassification
        cfg.worldAlignment = .gravityAndHeading
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            cfg.frameSemantics = .sceneDepth
        }
        arSession?.run(cfg)
    }

    // MARK: - Video Capture

    private func setupVideoCapture(dir: URL) {
        let url = dir.appendingPathComponent("video.mp4")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920, AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )

        writer.add(input)
        writer.startWriting()

        videoWriter = writer
        videoInput = input
        pixelBufferAdaptor = adaptor
    }

    private func finalizeVideoCapture() {
        videoInput?.markAsFinished()
        videoWriter?.finishWriting { print("[ReconWalk] Video saved") }
        videoWriter = nil; videoInput = nil; pixelBufferAdaptor = nil; videoStartTime = nil
    }

    // MARK: - Segment Management

    private func saveCurrentSegment() {
        guard let dir = sessionDirectory else { return }
        let segDir = dir.appendingPathComponent("segment_\(currentSegmentIndex)")
        try? FileManager.default.createDirectory(at: segDir, withIntermediateDirectories: true)

        exportPointCloudToPLY(segDir.appendingPathComponent("points.ply"))
        exportMeshToUSDZ(segDir.appendingPathComponent("mesh.usdz"))

        currentSegmentIndex += 1
        segmentCount = currentSegmentIndex
        collectedPoints.removeAll()
    }

    private func exportPointCloudToPLY(_ url: URL) {
        guard !collectedPoints.isEmpty else { return }
        var ply = "ply\nformat ascii 1.0\nelement vertex \(collectedPoints.count)\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
        for p in collectedPoints { ply += "\(p.x) \(p.y) \(p.z)\n" }
        try? ply.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportMeshToUSDZ(_ url: URL) {
        let scene = SCNScene()
        for (_, anchor) in meshAnchors {
            if let node = scnNode(from: anchor) {
                scene.rootNode.addChildNode(node)
            }
        }
        scene.write(to: url, options: nil, delegate: nil) { _, error, _ in
            if let e = error { print("[ReconWalk] USDZ export error: \(e)") }
        }
    }

    private func scnNode(from anchor: ARMeshAnchor) -> SCNNode? {
        let geo = anchor.geometry
        let vertexCount = geo.vertices.count
        guard vertexCount > 0 else { return nil }

        // Extract vertices via MTLBuffer pointer arithmetic
        var positions: [SCNVector3] = []
        let vertexBuf = geo.vertices.buffer.contents()
        let stride = geo.vertices.stride
        let offset = geo.vertices.offset
        for i in 0..<vertexCount {
            let ptr = vertexBuf.advanced(by: offset + i * stride)
                .bindMemory(to: SIMD3<Float>.self, capacity: 1)
            let local = ptr.pointee
            let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            positions.append(SCNVector3(world.x, world.y, world.z))
        }

        // Build face indices from geometry elements
        let faceCount = geo.faces.count
        var indices: [Int32] = []
        let facesBuf = geo.faces.buffer.contents()
        let faceStride = Int(geo.faces.bytesPerIndex)
        for i in 0..<(faceCount * 3) {
            let ptr = facesBuf.advanced(by: i * faceStride)
                .bindMemory(to: Int32.self, capacity: 1)
            indices.append(ptr.pointee)
        }

        let vertexSource = SCNGeometrySource(vertices: positions)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.5)

        return SCNNode(geometry: geometry)
    }

    // MARK: - Timers

    private func startTimers() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsedTime += 1
                self.coverageArea = self.distanceWalked * 5.0  // 5m scan width estimate
                self.currentSession?.segmentCount = self.segmentCount
            }
        }
        segmentTimer = Timer.scheduledTimer(withTimeInterval: config.segmentInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.saveCurrentSegment() }
        }
    }

    // MARK: - Session Metadata

    private func saveSessionMetadata() {
        guard let session = currentSession, let dir = sessionDirectory else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(session) {
            try? data.write(to: dir.appendingPathComponent("session.json"))
        }
        saveGPX(session.breadcrumbs, to: dir.appendingPathComponent("track.gpx"))
    }

    private func saveGPX(_ crumbs: [ReconWalkSession.Breadcrumb], to url: URL) {
        let fmt = ISO8601DateFormatter()
        var gpx = "<?xml version=\"1.0\"?>\n<gpx version=\"1.1\" creator=\"ZeroDark\">\n  <trk><name>Recon Walk</name><trkseg>\n"
        for c in crumbs {
            gpx += "    <trkpt lat=\"\(c.latitude)\" lon=\"\(c.longitude)\"><ele>\(c.altitude)</ele><time>\(fmt.string(from: c.timestamp))</time></trkpt>\n"
        }
        gpx += "  </trkseg></trk>\n</gpx>"
        try? gpx.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - ARSessionDelegate

extension ReconWalkEngine: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for case let mesh as ARMeshAnchor in anchors {
                self.meshAnchors[mesh.identifier] = mesh
                let pts = self.extractPoints(from: mesh)
                self.collectedPoints.append(contentsOf: pts)
                self.pointCount = self.collectedPoints.count
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for case let mesh as ARMeshAnchor in anchors {
                self.meshAnchors[mesh.identifier] = mesh
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            guard let input = self.videoInput, input.isReadyForMoreMediaData,
                  let adaptor = self.pixelBufferAdaptor else { return }
            let ts = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
            if self.videoStartTime == nil {
                self.videoStartTime = ts
                self.videoWriter?.startSession(atSourceTime: ts)
            }
            adaptor.append(frame.capturedImage, withPresentationTime: ts)
        }
    }

    nonisolated private func extractPoints(from anchor: ARMeshAnchor) -> [SIMD3<Float>] {
        let geo = anchor.geometry
        let count = geo.vertices.count
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(count)
        let buf = geo.vertices.buffer.contents()
        let stride = geo.vertices.stride
        let offset = geo.vertices.offset
        for i in 0..<count {
            let ptr = buf.advanced(by: offset + i * stride)
                .bindMemory(to: SIMD3<Float>.self, capacity: 1)
            let local = ptr.pointee
            let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            result.append(SIMD3<Float>(world.x, world.y, world.z))
        }
        return result
    }
}

// MARK: - CLLocationManagerDelegate

extension ReconWalkEngine: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            if let last = self.lastLocation {
                let delta = loc.distance(from: last)
                if delta > 0.5 { self.distanceWalked += delta }
                self.currentSpeed = max(0, loc.speed)
            } else { self.startLocation = loc }
            self.lastLocation = loc
            let crumb = ReconWalkSession.Breadcrumb(
                timestamp: Date(),
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude,
                heading: 0,
                altitude: loc.altitude
            )
            self.currentSession?.breadcrumbs.append(crumb)
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let reconWalkComplete = Notification.Name("reconWalkComplete")
}
