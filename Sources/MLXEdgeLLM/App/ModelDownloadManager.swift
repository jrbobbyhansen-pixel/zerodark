// ModelDownloadManager.swift — Manages CDN downloads for embedding + vision models
// The text LLM (Phi-3.5-mini) is handled separately by LocalInferenceEngine via MLX/HuggingFace.

import Foundation
import CryptoKit

@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    // MARK: - Download state per model

    enum DownloadStatus: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case unpacking
        case downloaded
        case failed(String)

        var isTerminal: Bool {
            if case .downloaded = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .notDownloaded:        return "Not downloaded"
            case .downloading(let p):  return "\(Int(p * 100))%"
            case .unpacking:           return "Unpacking…"
            case .downloaded:          return "Ready"
            case .failed(let e):       return "Failed: \(e)"
            }
        }
    }

    @Published var embeddingStatus: DownloadStatus = .notDownloaded
    @Published var visionStatus: DownloadStatus    = .notDownloaded

    // Active download tasks (keyed by model name for cancellation)
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600   // 1 hour max for large models
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
        ModelURLs.createModelDirectories()
        refreshStatus()
    }

    // MARK: - Status

    func refreshStatus() {
        if FileManager.default.fileExists(atPath: ModelURLs.embeddingModelPath.path) {
            embeddingStatus = .downloaded
        }
        if FileManager.default.fileExists(atPath: ModelURLs.visionModelPath.path) {
            visionStatus = .downloaded
        }
    }

    var allDownloaded: Bool {
        if case .downloaded = embeddingStatus, case .downloaded = visionStatus { return true }
        return false
    }

    // MARK: - Download

    func downloadEmbeddingModel() {
        guard case .notDownloaded = embeddingStatus else { return }
        embeddingStatus = .downloading(progress: 0)
        startDownload(url: ModelURLs.embeddingModelCDN, modelKey: "embedding")
    }

    func downloadVisionModel() {
        guard case .notDownloaded = visionStatus else { return }
        visionStatus = .downloading(progress: 0)
        startDownload(url: ModelURLs.visionModelCDN, modelKey: "vision")
    }

    func downloadAll() {
        if case .notDownloaded = embeddingStatus { downloadEmbeddingModel() }
        if case .notDownloaded = visionStatus    { downloadVisionModel() }
    }

    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        if case .downloading = embeddingStatus { embeddingStatus = .notDownloaded }
        if case .downloading = visionStatus    { visionStatus = .notDownloaded }
    }

    // MARK: - Private

    private func startDownload(url: URL, modelKey: String) {
        let task = session.downloadTask(with: url)
        task.taskDescription = modelKey
        activeTasks[modelKey] = task
        task.resume()
    }

    private func handleDownloadComplete(modelKey: String, tmpURL: URL) {
        let destination: URL
        let destDir: URL

        switch modelKey {
        case "embedding":
            destination = ModelURLs.embeddingModelPath
            destDir     = ModelURLs.embeddingModelDir
        case "vision":
            destination = ModelURLs.visionModelPath
            destDir     = ModelURLs.visionModelDir
        default:
            return
        }

        do {
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Remove any existing file before moving
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            // If the download is a zip, unpack it; otherwise move directly
            if tmpURL.pathExtension == "zip" {
                setStatus(for: modelKey, to: .unpacking)
                unzip(from: tmpURL, to: destDir)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: destination)
            }

            setStatus(for: modelKey, to: .downloaded)
        } catch {
            setStatus(for: modelKey, to: .failed(error.localizedDescription))
        }

        activeTasks.removeValue(forKey: modelKey)
    }

    private func unzip(from zipURL: URL, to destDir: URL) {
        // Use Process on macOS or a Swift zip library on iOS.
        // For iOS, copy the zip to a temp working path and use ZipArchive or similar.
        // For now, treat the downloaded file as a direct mlpackage directory bundle
        // (the CDN should serve the mlpackage directly, not zipped, when possible).
        let finalPath = destDir.appendingPathComponent(zipURL.deletingPathExtension().lastPathComponent)
        try? FileManager.default.moveItem(at: zipURL, to: finalPath)
    }

    private func setStatus(for key: String, to status: DownloadStatus) {
        switch key {
        case "embedding": embeddingStatus = status
        case "vision":    visionStatus    = status
        default: break
        }
    }

    private func updateProgress(for key: String, progress: Double) {
        switch key {
        case "embedding": embeddingStatus = .downloading(progress: progress)
        case "vision":    visionStatus    = .downloading(progress: progress)
        default: break
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let key = downloadTask.taskDescription else { return }
        // Copy to a stable temp path before async dispatch (iOS may delete `location` quickly)
        let stableTmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(key)-\(UUID().uuidString)")
        try? FileManager.default.copyItem(at: location, to: stableTmp)
        Task { @MainActor in
            self.handleDownloadComplete(modelKey: key, tmpURL: stableTmp)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let key = downloadTask.taskDescription else { return }
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            // Fallback: use known expected size
            let expected = key == "embedding" ? ModelURLs.embeddingModelBytes : ModelURLs.visionModelBytes
            progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0
        }
        Task { @MainActor in
            self.updateProgress(for: key, progress: min(progress, 0.99))
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let key = task.taskDescription else { return }
        Task { @MainActor in
            self.setStatus(for: key, to: .failed(error.localizedDescription))
            self.activeTasks.removeValue(forKey: key)
        }
    }
}
