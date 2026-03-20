// VisionInferenceEngine.swift — On-device moondream2 vision inference (Phase 15 stub)

import Foundation
import UIKit

@MainActor
final class VisionInferenceEngine: ObservableObject {
    static let shared = VisionInferenceEngine()

    @Published var isLoaded = false
    @Published var isProcessing = false

    private let modelName = "moondream2-q4.gguf"

    var modelFileExists: Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = docs.appendingPathComponent("Models/\(modelName)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    func loadModel() async throws {
        guard !isLoaded else { return }
        guard modelFileExists else { throw VisionError.modelNotFound }
        // TODO: Load moondream2 via llama.cpp or mlx-vlm when multimodal API is available (Phase 16)
        isLoaded = true
    }

    func analyze(image: UIImage, question: String) async throws -> String {
        guard isLoaded else { throw VisionError.modelNotLoaded }
        guard image.jpegData(compressionQuality: 0.8) != nil else { throw VisionError.imageEncodingFailed }

        isProcessing = true
        defer { isProcessing = false }

        // TODO: On-device inference — Phase 16
        return "[On-device vision stub — copy moondream2-q4.gguf to Documents/Models/ to enable]"
    }

    enum VisionError: Error {
        case modelNotFound
        case modelNotLoaded
        case imageEncodingFailed
    }
}
