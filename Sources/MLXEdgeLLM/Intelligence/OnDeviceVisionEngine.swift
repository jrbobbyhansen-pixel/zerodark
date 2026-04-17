// OnDeviceVisionEngine.swift — On-device image analysis via Apple Vision framework
// Tier 1: VNClassifyImageRequest + VNRecognizeTextRequest — always available offline
// Tier 2: moondream2 CoreML (when downloaded via Arm Your Device) — future tier

import Vision
import UIKit
import Foundation

// MARK: - Analysis mode enum (shared with VisionContentView)

enum OnDeviceVisionMode: String, CaseIterable {
    case plantId = "Plant ID"
    case wound   = "Wound"
    case terrain = "Terrain"
    case map     = "Map"
    case ask     = "Ask"

    var icon: String {
        switch self {
        case .plantId: return "leaf.fill"
        case .wound:   return "bandage.fill"
        case .terrain: return "map.fill"
        case .map:     return "map"
        case .ask:     return "questionmark.circle.fill"
        }
    }

    var defaultQuestion: String {
        switch self {
        case .plantId:
            return "Identify this plant. Is it edible or toxic? What are the identifying features and any lookalikes?"
        case .wound:
            return "Assess this wound. What type is it? What immediate field treatment is required? What are warning signs of complications?"
        case .terrain:
            return "Analyze this terrain. Where is cover, concealment, high ground, and likely avenues of approach or escape?"
        case .map:
            return "Analyze this map or document. What key information does it contain?"
        case .ask:
            return "Describe what you see and analyze it."
        }
    }
}

// MARK: - OnDeviceVisionEngine

@MainActor
final class OnDeviceVisionEngine: ObservableObject {
    static let shared = OnDeviceVisionEngine()

    @Published var isConnected: Bool = true   // Always available — no server required
    @Published var isProcessing: Bool = false

    var visionStatusLabel: String { "Apple Vision" }

    private init() {}

    // MARK: - Public interface

    func query(image: UIImage, question: String, mode: OnDeviceVisionMode = .ask) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        guard let cgImage = image.cgImage else {
            throw VisionEngineError.imageConversionFailed
        }

        switch mode {
        case .map:
            return try await recognizeText(cgImage: cgImage)
        default:
            return try await classifyAndFormat(cgImage: cgImage, mode: mode)
        }
    }

    // MARK: - Text Recognition

    private func recognizeText(cgImage: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if lines.isEmpty {
                    continuation.resume(returning: "No readable text detected in this image.")
                } else {
                    continuation.resume(returning: "Extracted text:\n\n" + lines.joined(separator: "\n"))
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Image Classification

    private func classifyAndFormat(cgImage: CGImage, mode: OnDeviceVisionMode) async throws -> String {
        let labels = try await classifyImage(cgImage: cgImage)
        return formatResult(labels: labels, mode: mode)
    }

    private func classifyImage(cgImage: CGImage) async throws -> [(identifier: String, confidence: Float)] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNClassifyImageRequest { req, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (req.results as? [VNClassificationObservation]) ?? []
                let results = observations
                    .filter { $0.confidence > 0.05 }
                    .prefix(20)
                    .map { (identifier: $0.identifier, confidence: $0.confidence) }
                continuation.resume(returning: Array(results))
            }
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Mode-specific formatting

    private func formatResult(labels: [(identifier: String, confidence: Float)], mode: OnDeviceVisionMode) -> String {
        let top = labels.prefix(12)
        let allNames = top.map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }.joined(separator: ", ")

        switch mode {

        case .plantId:
            let plants = top.filter { isPlantRelated($0.identifier) }
            if plants.isEmpty {
                return "No clear plant features detected.\n\nTop detections: \(allNames)\n\nPoint camera at leaves, flowers, or stems for best results.\n\n⚠️ Do not consume any wild plant without expert confirmation."
            }
            let primary = plants.map { $0.identifier }.joined(separator: ", ")
            let toxicNote = plants.contains(where: { isToxicIndicator($0.identifier) })
                ? "⚠️ Potential toxic indicator detected (mushroom/berry/fungus). Do NOT consume."
                : "Cross-reference with a field guide before consuming any wild plant."
            return "Plant features: \(primary)\n\n\(toxicNote)\n\nAll detections: \(allNames)"

        case .wound:
            let body = top.filter { isBodyRelated($0.identifier) }
            if body.isEmpty {
                return "No body/skin features clearly detected.\n\nEnsure wound is centered and well-lit.\n\nImmediate actions:\n• Apply direct pressure to stop bleeding\n• Do not remove embedded objects\n• Cover with clean dressing\n• Monitor for shock\n\nAll detections: \(allNames)"
            }
            return "Body area: \(body.map { $0.identifier }.joined(separator: ", "))\n\nField treatment protocol:\n• Direct pressure — maintain 5+ minutes\n• Do NOT remove embedded objects\n• Pack deep wounds with clean cloth\n• Elevate if extremity\n• Tourniquet if arterial (2-3\" above wound)\n• Monitor: pale/cold/rapid pulse = shock\n• Evacuate immediately if: arterial, deep, abdominal\n\nAll detections: \(allNames)"

        case .terrain:
            let terrain = top.filter { isTerrainRelated($0.identifier) }
            let dominant = terrain.isEmpty ? top.prefix(4).map { $0.identifier } : terrain.map { $0.identifier }
            return "Terrain: \(dominant.joined(separator: ", "))\n\nTactical assessment:\n• Cover: \(coverAssessment(Array(terrain)))\n• Concealment: \(concealmentAssessment(Array(terrain)))\n• High ground: \(highGroundAssessment(Array(terrain)))\n• Water: \(waterAssessment(Array(terrain)))\n\nAll detections: \(allNames)"

        case .map:
            return "Switch to Map mode for text extraction."

        case .ask:
            let primary = top.prefix(6).map { $0.identifier }.joined(separator: ", ")
            return "Scene analysis:\n\nIdentified: \(primary)\n\nFull scan: \(allNames)"
        }
    }

    // MARK: - Label helpers

    private func isPlantRelated(_ s: String) -> Bool {
        ["plant", "leaf", "tree", "flower", "grass", "moss", "fern", "shrub", "bush",
         "herb", "vegetation", "foliage", "branch", "stem", "bark", "mushroom", "fungus",
         "berry", "fruit", "seed", "weed", "thistle"].contains { s.lowercased().contains($0) }
    }

    private func isToxicIndicator(_ s: String) -> Bool {
        ["mushroom", "fungus", "berry"].contains { s.lowercased().contains($0) }
    }

    private func isBodyRelated(_ s: String) -> Bool {
        ["skin", "hand", "arm", "leg", "foot", "face", "body", "person",
         "finger", "wound", "cut", "blood", "tissue"].contains { s.lowercased().contains($0) }
    }

    private func isTerrainRelated(_ s: String) -> Bool {
        ["mountain", "hill", "valley", "river", "lake", "forest", "tree", "rock", "cliff",
         "desert", "field", "grass", "water", "snow", "ridge", "slope", "ground", "dirt",
         "sand", "urban", "building", "road", "path", "trail"].contains { s.lowercased().contains($0) }
    }

    private func coverAssessment(_ labels: [(identifier: String, confidence: Float)]) -> String {
        let names = labels.map { $0.identifier.lowercased() }
        if names.contains(where: { $0.contains("rock") || $0.contains("cliff") }) { return "Hard cover (rock/concrete)" }
        if names.contains(where: { $0.contains("building") || $0.contains("urban") }) { return "Urban cover available" }
        if names.contains(where: { $0.contains("tree") || $0.contains("forest") }) { return "Soft cover (trees)" }
        return "Limited — seek defilade"
    }

    private func concealmentAssessment(_ labels: [(identifier: String, confidence: Float)]) -> String {
        let names = labels.map { $0.identifier.lowercased() }
        if names.contains(where: { $0.contains("forest") || $0.contains("vegetation") }) { return "Good (dense vegetation)" }
        if names.contains(where: { $0.contains("tree") || $0.contains("shrub") || $0.contains("grass") }) { return "Moderate (scattered vegetation)" }
        if names.contains(where: { $0.contains("desert") || $0.contains("field") || $0.contains("sand") }) { return "Poor — exposed terrain" }
        return "Moderate — assess locally"
    }

    private func highGroundAssessment(_ labels: [(identifier: String, confidence: Float)]) -> String {
        let names = labels.map { $0.identifier.lowercased() }
        if names.contains(where: { $0.contains("mountain") || $0.contains("cliff") || $0.contains("ridge") }) { return "Elevated terrain present" }
        if names.contains(where: { $0.contains("hill") || $0.contains("slope") }) { return "Rolling terrain — moderate elevation gain" }
        if names.contains(where: { $0.contains("valley") || $0.contains("field") || $0.contains("flat") }) { return "Low ground — find elevation" }
        return "Evaluate local topography"
    }

    private func waterAssessment(_ labels: [(identifier: String, confidence: Float)]) -> String {
        let names = labels.map { $0.identifier.lowercased() }
        if names.contains(where: { $0.contains("river") || $0.contains("lake") || $0.contains("water") || $0.contains("stream") }) { return "Water source visible — purify before use" }
        if names.contains(where: { $0.contains("snow") || $0.contains("ice") }) { return "Snow/ice present — melt and purify" }
        return "No visible water — conserve supply"
    }
}

enum VisionEngineError: Error {
    case imageConversionFailed
    case classificationFailed
}
