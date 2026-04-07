// YOLOThreatDetector.swift — CoreML YOLOv8n pipeline with LiDAR depth → 3D threat projection
// Runs at 10Hz (throttled), projects 2D detections into 3D world coordinates via depth map

import Foundation
import ARKit
import Vision
import CoreML
import Combine
import simd

// MARK: - YOLOThreatDetector

@MainActor
final class YOLOThreatDetector: ObservableObject {

    @Published private(set) var activeDetections: [YOLODetection] = []
    @Published private(set) var isModelLoaded = false
    @Published private(set) var inferenceTimeMs: Double = 0

    private var visionModel: VNCoreMLModel?
    private var frameCounter: Int = 0
    private let frameSkip: Int
    private let config: ThreatClassMap.Config
    private let capability: DeviceCapability

    // Detections older than this are pruned
    private let detectionTimeout: TimeInterval = 0.5
    private var detectionTimestamps: [UUID: Date] = [:]

    init(capability: DeviceCapability = .current, config: ThreatClassMap.Config = .default) {
        self.capability = capability
        self.config = config
        self.frameSkip = capability.yoloFrameSkip
    }

    // MARK: - Model Loading

    func loadModel() async {
        do {
            // Try compiled model first, then mlpackage (Xcode compiles .mlpackage → .mlmodelc at build time)
            guard let modelURL = Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlmodelc")
                    ?? Bundle.main.url(forResource: "YOLOv8n", withExtension: "mlpackage") else {
                print("[YOLOThreatDetector] YOLOv8n model not found in bundle")
                return
            }

            let mlModel = try await MLModel.load(contentsOf: modelURL, configuration: {
                let config = MLModelConfiguration()
                config.computeUnits = .all  // Use Neural Engine + GPU
                return config
            }())

            visionModel = try VNCoreMLModel(for: mlModel)
            isModelLoaded = true
            print("[YOLOThreatDetector] Model loaded, frameSkip=\(frameSkip)")
        } catch {
            print("[YOLOThreatDetector] Failed to load model: \(error)")
        }
    }

    // MARK: - Frame Processing

    /// Process an AR frame. Throttled to run inference every `frameSkip` frames.
    func processFrame(_ frame: ARFrame) {
        frameCounter += 1
        guard frameCounter % frameSkip == 0, isModelLoaded else { return }

        let pixelBuffer = frame.capturedImage
        let camera = frame.camera
        let depthMap = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap
        let transform = frame.camera.transform
        let intrinsics = frame.camera.intrinsics
        let imageResolution = frame.camera.imageResolution

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let startTime = CFAbsoluteTimeGetCurrent()

            let detections = await self.runInference(
                pixelBuffer: pixelBuffer,
                depthMap: depthMap,
                cameraTransform: transform,
                intrinsics: intrinsics,
                imageResolution: imageResolution
            )

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            await MainActor.run {
                self.activeDetections = detections
                self.inferenceTimeMs = elapsed
                self.pruneStaleDetections()
            }
        }
    }

    // MARK: - Vision Inference

    private func runInference(
        pixelBuffer: CVPixelBuffer,
        depthMap: CVPixelBuffer?,
        cameraTransform: simd_float4x4,
        intrinsics: simd_float3x3,
        imageResolution: CGSize
    ) async -> [YOLODetection] {
        guard let visionModel else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                guard let self, error == nil,
                      let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let detections = results.compactMap { observation -> YOLODetection? in
                    guard let topLabel = observation.labels.first,
                          topLabel.confidence >= self.config.minConfidence else { return nil }

                    let classId = self.cocoClassId(for: topLabel.identifier)
                    let bbox = observation.boundingBox // Vision coordinates (origin bottom-left)

                    // Sample depth at bbox center
                    let centerX = bbox.midX
                    let centerY = 1.0 - bbox.midY // Flip to top-left origin

                    var position3D: SIMD3<Float>?
                    var distance: Float?

                    if let depthMap {
                        let depth = self.sampleDepth(
                            depthMap: depthMap,
                            normalizedX: Float(centerX),
                            normalizedY: Float(centerY)
                        )

                        if let depth, depth > 0.1 && depth < 30.0 {
                            distance = depth
                            position3D = self.unprojectToWorld(
                                pixelX: Float(centerX) * Float(imageResolution.width),
                                pixelY: Float(centerY) * Float(imageResolution.height),
                                depth: depth,
                                intrinsics: intrinsics,
                                cameraTransform: cameraTransform
                            )
                        }
                    }

                    return YOLODetection(
                        classId: classId,
                        className: topLabel.identifier,
                        confidence: topLabel.confidence,
                        boundingBox: bbox,
                        position3D: position3D,
                        distance: distance
                    )
                }

                continuation.resume(returning: detections)
            }

            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Depth Sampling

    private func sampleDepth(depthMap: CVPixelBuffer, normalizedX: Float, normalizedY: Float) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let x = Int(normalizedX * Float(width - 1))
        let y = Int(normalizedY * Float(height - 1))

        guard x >= 0, x < width, y >= 0, y < height,
              let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let pixel = baseAddress.advanced(by: y * bytesPerRow + x * MemoryLayout<Float32>.size)
        return pixel.assumingMemoryBound(to: Float32.self).pointee
    }

    // MARK: - 3D Unprojection

    private func unprojectToWorld(
        pixelX: Float,
        pixelY: Float,
        depth: Float,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float> {
        // Unproject from pixel to camera-space using intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        let camX = (pixelX - cx) * depth / fx
        let camY = (pixelY - cy) * depth / fy
        let camZ = depth

        // Camera space point (ARKit convention: +x right, +y up, -z forward)
        let cameraPoint = SIMD4<Float>(camX, -camY, -camZ, 1.0)

        // Transform to world space
        let worldPoint = cameraTransform * cameraPoint
        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    // MARK: - Helpers

    private func cocoClassId(for identifier: String) -> Int {
        // Reverse lookup from class name to ID
        let lowered = identifier.lowercased()
        for (id, name) in ThreatClassMap.classNames {
            if name == lowered { return id }
        }
        return -1
    }

    private func pruneStaleDetections() {
        let now = Date()
        detectionTimestamps = detectionTimestamps.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < detectionTimeout
        }
    }
}
