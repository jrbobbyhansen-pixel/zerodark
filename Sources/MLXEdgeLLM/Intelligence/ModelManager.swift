import Foundation

/// Reports model install state to the Settings UI.
///
/// Architecture note: ZeroDark migrated from llama.cpp+GGUF to MLX-Swift.
/// The MLX engine downloads weights from HuggingFace at runtime
/// (`mlx-community/Phi-3.5-mini-instruct-4bit`) and caches them in
/// `~/Library/Caches/huggingface/hub/...`. There is no app-bundle GGUF in
/// the live inference path. This manager surfaces the MLX cache size +
/// load state so users know whether the model is ready or still
/// downloading.
@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var isCopying: Bool = false
    @Published var copyProgress: Double = 0.0
    @Published var copyError: String? = nil

    private init() {}

    /// True when the MLX engine reports a loaded model.
    var modelInstalled: Bool {
        LocalInferenceEngine.shared.modelState == .ready
    }

    /// Best-effort estimate of installed model size on disk. Walks the
    /// HuggingFace Hub cache directory under Caches/huggingface and sums
    /// the size of any `mlx-community/Phi-3.5-mini-instruct-4bit` snapshot.
    /// Returns a human-readable string for UI display ("Unknown" if not
    /// found yet — typical state before first model load completes).
    var installedModelSize: String {
        let bytes = Self.computeMLXCacheBytes()
        guard bytes > 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func computeMLXCacheBytes() -> Int64 {
        let fm = FileManager.default
        guard let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return 0 }
        let modelDir = cachesURL
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
        guard let enumerator = fm.enumerator(
            at: modelDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            // Only count files within an mlx-community Phi-3.5 snapshot.
            guard url.path.contains("Phi-3.5-mini") else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true,
                  let sz = values?.fileSize else { continue }
            total += Int64(sz)
        }
        return total
    }
}
