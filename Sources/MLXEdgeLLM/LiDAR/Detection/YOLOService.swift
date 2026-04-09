// YOLOService.swift — Async service facade over YOLOThreatDetector
// Provides a clean async/await API for on-demand detection outside the pipeline

import Foundation
import ARKit

@MainActor
final class YOLOService: ObservableObject {
    static let shared = YOLOService()

    @Published private(set) var isReady = false
    @Published private(set) var lastInferenceMs: Double = 0

    private let detector: YOLOThreatDetector

    private init(capability: DeviceCapability = .current) {
        self.detector = YOLOThreatDetector(capability: capability)
    }

    var activeDetections: [YOLODetection] {
        detector.activeDetections
    }

    // MARK: - Lifecycle

    func loadModel() async {
        await detector.loadModel()
        isReady = detector.isModelLoaded
    }

    // MARK: - Detection

    /// Run detection on a single AR frame (respects internal frame throttling).
    func processFrame(_ frame: ARFrame) {
        detector.processFrame(frame)
        lastInferenceMs = detector.inferenceTimeMs
    }

    /// Filter detections by minimum confidence threshold.
    func filteredDetections(minConfidence: Float = 0.5) -> [YOLODetection] {
        detector.activeDetections.filter { $0.confidence >= minConfidence }
    }

    /// Get detections classified as threats (level > .none).
    func threatDetections(config: ThreatClassMap.Config = .default) -> [YOLODetection] {
        detector.activeDetections.filter { $0.tacticalLevel(config: config) > .none }
    }
}
