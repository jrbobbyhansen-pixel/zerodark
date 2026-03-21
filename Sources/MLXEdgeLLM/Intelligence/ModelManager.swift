import Foundation

@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var isCopying: Bool = false
    @Published var copyProgress: Double = 0.0
    @Published var copyError: String? = nil

    private init() {}

    var modelInstalled: Bool {
        FileManager.default.fileExists(atPath: LocalInferenceEngine.modelPath.path)
    }

    var installedModelSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: LocalInferenceEngine.modelPath.path),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func installFromBundle() async {
        // INTENTIONAL_STUB: Bundle resource copy for 2.2GB model — Phase 8c
        // Only works if model is added as a resource in project.yml.
        // For development, copy manually:
        // cp ~/Desktop/bitnet-test/models/Phi-3.5-mini-instruct-Q4_K_M.gguf
        //    ~/Library/Developer/CoreSimulator/.../ZeroDark/Documents/Models/phi-3.5-mini.gguf
        guard let bundleURL = Bundle.main.url(forResource: "phi-3.5-mini", withExtension: "gguf") else {
            copyError = "Model not found in app bundle. Copy manually via Files app."
            return
        }
        let destDir = LocalInferenceEngine.modelPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        isCopying = true
        copyProgress = 0.0
        do {
            try FileManager.default.copyItem(at: bundleURL, to: LocalInferenceEngine.modelPath)
            copyProgress = 1.0
        } catch {
            copyError = error.localizedDescription
        }
        isCopying = false
    }
}
