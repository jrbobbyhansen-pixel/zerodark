// DTNBuffer.swift — Persistent buffer for DTN bundles (NASA HDTN pattern)

import Foundation

/// Persistent buffer for DTN bundles (NASA HDTN pattern)
@MainActor
public class DTNBuffer: ObservableObject {
    public static let shared = DTNBuffer()

    @Published public private(set) var pendingCount: Int = 0
    @Published public private(set) var deliveredCount: Int = 0

    private let fileManager = FileManager.default
    private let bundleDirectory: URL
    private let maxBufferSize = 1000  // Max bundles to store
    private let maxPayloadSize = 1_000_000  // 1MB max per bundle

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        bundleDirectory = docs.appendingPathComponent("DTNBundles", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

        // Load counts
        Task {
            await refreshCounts()
        }
    }

    // MARK: - Bundle Storage

    /// Store a new bundle for later delivery
    public func store(_ bundle: DTNBundle) async throws {
        // Check buffer limits
        let pending = try await getPendingBundles()
        guard pending.count < maxBufferSize else {
            throw DTNError.bufferFull
        }

        guard bundle.payload.count <= maxPayloadSize else {
            throw DTNError.payloadTooLarge
        }

        // Encode and save
        let encoder = JSONEncoder()
        let data = try encoder.encode(bundle)
        let fileURL = bundleDirectory.appendingPathComponent("\(bundle.id.uuidString).bundle")
        try data.write(to: fileURL)

        await refreshCounts()
        print("[DTNBuffer] Stored bundle \(bundle.id) for \(bundle.destination)")
    }

    /// Get all pending (undelivered, unexpired) bundles
    public func getPendingBundles() async throws -> [DTNBundle] {
        let files = try fileManager.contentsOfDirectory(at: bundleDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()

        var bundles: [DTNBundle] = []
        for file in files where file.pathExtension == "bundle" {
            if let data = try? Data(contentsOf: file),
               var bundle = try? decoder.decode(DTNBundle.self, from: data) {
                // Skip expired or delivered
                if bundle.isExpired {
                    try? fileManager.removeItem(at: file)
                    continue
                }
                if bundle.isDelivered {
                    continue
                }
                bundles.append(bundle)
            }
        }

        // Sort by priority (highest first), then by age (oldest first)
        return bundles.sorted { a, b in
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
        let fileURL = bundleDirectory.appendingPathComponent("\(bundleID.uuidString).bundle")

        guard let data = try? Data(contentsOf: fileURL),
              var bundle = try? JSONDecoder().decode(DTNBundle.self, from: data) else {
            return
        }

        bundle.deliveredAt = Date()
        let updatedData = try JSONEncoder().encode(bundle)
        try updatedData.write(to: fileURL)

        await refreshCounts()
        print("[DTNBuffer] Marked bundle \(bundleID) as delivered")
    }

    /// Record a delivery attempt
    public func recordAttempt(_ bundleID: UUID) async throws {
        let fileURL = bundleDirectory.appendingPathComponent("\(bundleID.uuidString).bundle")

        guard let data = try? Data(contentsOf: fileURL),
              var bundle = try? JSONDecoder().decode(DTNBundle.self, from: data) else {
            return
        }

        bundle.deliveryAttempts += 1
        bundle.lastAttemptAt = Date()
        let updatedData = try JSONEncoder().encode(bundle)
        try updatedData.write(to: fileURL)
    }

    /// Remove delivered bundles older than specified age
    public func pruneDelivered(olderThan age: TimeInterval = 3600) async {
        let cutoff = Date().addingTimeInterval(-age)
        let files = (try? fileManager.contentsOfDirectory(at: bundleDirectory, includingPropertiesForKeys: nil)) ?? []

        for file in files where file.pathExtension == "bundle" {
            if let data = try? Data(contentsOf: file),
               let bundle = try? JSONDecoder().decode(DTNBundle.self, from: data),
               let deliveredAt = bundle.deliveredAt,
               deliveredAt < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }

        await refreshCounts()
    }

    // MARK: - Helpers

    private func refreshCounts() async {
        let files = (try? fileManager.contentsOfDirectory(at: bundleDirectory, includingPropertiesForKeys: nil)) ?? []
        var pending = 0
        var delivered = 0

        for file in files where file.pathExtension == "bundle" {
            if let data = try? Data(contentsOf: file),
               let bundle = try? JSONDecoder().decode(DTNBundle.self, from: data) {
                if bundle.isDelivered {
                    delivered += 1
                } else if !bundle.isExpired {
                    pending += 1
                }
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
