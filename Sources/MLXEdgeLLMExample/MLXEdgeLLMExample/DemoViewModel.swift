import Foundation
import MLXEdgeLLM
import Combine

@MainActor
final class DemoViewModel: ObservableObject {
    @Published var output: String = ""
    @Published var progress: String = ""
    @Published var isLoading = false
    @Published var selectedImage: PlatformImage?
    
    // MARK: - Vision
    
    func runVLM(model: Model, image: PlatformImage) async {
        startLoading()
        do {
            let vlm = try await MLXEdgeLLM.vision(model) { [weak self] p in
                self?.progress = p
            }
            let result = try await vlm.analyze("Describe this receipt in detail.", image: image)
            output = "📋 \(model.displayName):\n\n\(result)"
        } catch { output = "❌ \(error.localizedDescription)" }
        stopLoading()
    }
    
    func runStreamVLM(model: Model, image: PlatformImage) async {
        startLoading()
        output = ""
        do {
            let vlm = try await MLXEdgeLLM.vision(model) { [weak self] p in
                self?.progress = p
            }
            for try await token in vlm.streamVision("Describe this receipt in detail.", image: image) {
                output += token
            }
        } catch { output = "❌ \(error.localizedDescription)" }
        stopLoading()
    }
    
    // MARK: - Specialized OCR
    
    func runSpecialized(model: Model, image: PlatformImage) async {
        startLoading()
        do {
            let ocr = try await MLXEdgeLLM.specialized(model) { [weak self] p in
                self?.progress = p
            }
            var result = try await ocr.extractDocument(image)
            if case .visionSpecialized(let docTags) = model.purpose, docTags {
                result = MLXEdgeLLM.parseDocTags(result)
                output = "📝 Granite → Markdown:\n\n\(result)"
            } else {
                output = "⚡ FastVLM JSON:\n\n\(result)"
            }
        } catch { output = "❌ \(error.localizedDescription)" }
        stopLoading()
    }
    
    // MARK: - Text
    
    func runTextChat() async {
        startLoading()
        output = ""
        do {
            let llm = try await MLXEdgeLLM.text(.qwen3_1_7b) { [weak self] p in
                self?.progress = p
            }
            for try await token in llm.stream("¿Cuánto es el IVA en México y cómo aparece en tickets?") {
                output += token
            }
        } catch { output = "❌ \(error.localizedDescription)" }
        stopLoading()
    }
    
    // MARK: - Helpers
    
    private func startLoading() { isLoading = true; progress = "" }
    private func stopLoading()  { isLoading = false; progress = "" }
}
