// DTNBuffer.swift — Persistent buffer for DTN bundles (NASA HDTN pattern)

import Foundation

/// Background actor for DTN file I/O — keeps main thread free
private actor DTNFileIO {
    private let fileManager = FileManager.default
    private let bundleDirectory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(directory: URL) {
        self.bundleDirectory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writeBundle(_ bundle: DTNBundle) throws {
        let data = try encoder.encode(bundle)
        let fileURL = bundleDirectory.appendingPathComponent("\(bundle.id.uuidString).bundle")
        try data.write(to: fileURL)
    }

    func readAllBundles() -> [(URL, DTNBundle)] {
        let files = (try? fileManager.contentsOfDirectory(at: bundleDirectory, includingPropertiesForKeys: nil)) ?? []
        var results: [(URL, DTNBundle)] = []
        for file in files where file.pathExtension == "bundle" {
            if let data = try? Data(contentsOf: file),
               let bundle = try? decoder.decode(DTNBundle.self, from: data) {
                results.append((file, bundle))
            }
        }
        return results
    }

    func updateBundle(_ bundle: DTNBundle) throws {
        let data = try encoder.encode(bundle)
        let fileURL = bundleDirectory.appendingPathComponent("\(bundle.id.uuidString).bundle")
        try data.write(to: fileURL)
    }

    func removeFile(at url: URL) {
        try? fileManager.removeItem(at: url)
    }
}

/// Persistent buffer for DTN bundles (NASA HDTN pattern)
@MainActor
public class DTNBuffer: ObservableObject {
    public static let shared = DTNBuffer()

    @Published public private(set) var pendingCount: Int = 0
    @Published public private(set) var deliveredCount: Int = 0

    private let maxBufferSize = 1000  // Max bundles to store
    private let maxPayloadSize = 1_000_000  // 1MB max per bundle
    private let io: DTNFileIO

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("DTNBundles", isDirectory: true)
        self.io = DTNFileIO(directory: dir)

        Task {
            await refreshCounts()
        }
    }

    // MARK: - Bundle Storage

    /// Store a new bundle for later delivery
    public func store(_ bundle: DTNBundle) async throws {
        let pending = try await getPendingBundles()
        guard pending.count < maxBufferSize else {
            throw DTNError.bufferFull
        }

        guard bundle.payload.count <= maxPayloadSize else {
            throw DTNError.payloadTooLarge
        }

        try await io.writeBundle(bundle)
        await refreshCounts()
    }

    /// Get all pending (undelivered, unexpired) bundles
    public func getPendingBundles() async throws -> [DTNBundle] {
        let allBundles = await io.readAllBundles()

        var pending: [DTNBundle] = []
        for (url, bundle) in allBundles {
            if bundle.isExpired {
                await io.removeFile(at: url)
                continue
            }
            if bundle.isDelivered {
                continue
            }
            pending.append(bundle)
        }

        return pending.sorted { a, b in
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            return a.createdAt < b.createdAt
        }
    }

    /// Get bundles for a specific destination
    public func getBundles(for destination: String) async throws -> [DTNBundle] {
        let all = try await getPendingBundles()
        return all.filter { $0.destination == destination || $0.destination == "all" }
    }

    /// Mark a bundle as delivered
    public func markDelivered(_ bundleID: UUID) async throws {
        let allBundles = await io.readAllBundles()
        guard let match = allBundles.first(where: { $0.1.id == bundleID }) else {
            return
        }

        var bundle = match.1
        bundle.deliveredAt = Date()
        try await io.updateBundle(bundle)
        await refreshCounts()
    }

    /// Record a delivery attempt
    public func recordAttempt(_ bundleID: UUID) async throws {
        let allBundles = await io.readAllBundles()
        guard let match = allBundles.first(where: { $0.1.id == bundleID }) else {
            return
        }

        var bundle = match.1
        bundle.deliveryAttempts += 1
        bundle.lastAttemptAt = Date()
        try await io.updateBundle(bundle)
    }

    /// Remove delivered bundles older than specified age
    public func pruneDelivered(olderThan age: TimeInterval = 3600) async {
        let cutoff = Date().addingTimeInterval(-age)
        let allBundles = await io.readAllBundles()

        for (url, bundle) in allBundles {
            if let deliveredAt = bundle.deliveredAt, deliveredAt < cutoff {
                await io.removeFile(at: url)
            }
        }

        await refreshCounts()
    }

    // MARK: - Helpers

    private func refreshCounts() async {
        let allBundles = await io.readAllBundles()
        var pending = 0
        var delivered = 0

        for (_, bundle) in allBundles {
            if bundle.isDelivered {
                delivered += 1
            } else if !bundle.isExpired {
                pending += 1
            }
        }

        self.pendingCount = pending
        self.deliveredCount = delivered
    }
}

public enum DTNError: Error {
    case bufferFull
    case payloadTooLarge
    case bundleNotFound
    case deliveryFailed
}
