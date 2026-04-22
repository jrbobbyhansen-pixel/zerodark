// ScanStorage.swift — Persistent LiDAR scan storage manager

import Foundation
import UIKit

enum ScanType {
    case quickScan
    case reconWalk
}

/// Represents a saved scan on disk
struct SavedScan: Identifiable {
    let id: UUID
    let timestamp: Date
    let mode: String
    let pointCount: Int
    let riskScore: Float?
    let scanDir: URL
    var scanType: ScanType = .quickScan
    var name: String = ""  // User-editable name
    var latitude: Double?
    var longitude: Double?
    var sceneTag: Any? // SceneTag when available

    var usdzURL: URL {
        scanDir.appendingPathComponent("scan.usdz")
    }

    var hasUSDZ: Bool {
        FileManager.default.fileExists(atPath: usdzURL.path)
    }

    var coordinateString: String? {
        guard let lat = latitude, let lon = longitude else { return nil }
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.5f°%@ %.5f°%@", abs(lat), latDir, abs(lon), lonDir)
    }
}

@MainActor
final class ScanStorage: ObservableObject {
    static let shared = ScanStorage()

    @Published var savedScans: [SavedScan] = []
    @Published var lastError: String?

    /// Hard cap on total scan storage on disk, in bytes. 10 GB matches
    /// the roadmap's PR-C1 spec. When exceeded, oldest-first eviction
    /// runs at the end of loadScanIndex().
    var maxTotalBytes: Int64 = 10 * 1024 * 1024 * 1024

    private init() {
        loadScanIndex()
    }

    /// Compute total on-disk size of scans + recon walks, in bytes.
    private func totalStorageBytes() -> Int64 {
        var total: Int64 = 0
        for scan in savedScans {
            total += directorySize(at: scan.scanDir)
        }
        return total
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var sum: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                sum += Int64(size)
            }
        }
        return sum
    }

    /// Evict oldest scans until total storage fits within `maxTotalBytes`.
    /// Safe to call repeatedly — no-op when under the cap.
    private func enforceStorageCapacity() {
        var total = totalStorageBytes()
        guard total > maxTotalBytes else { return }

        // Oldest-first.
        let sorted = savedScans.sorted { $0.timestamp < $1.timestamp }
        for scan in sorted {
            guard total > maxTotalBytes else { break }
            let size = directorySize(at: scan.scanDir)
            try? FileManager.default.removeItem(at: scan.scanDir)
            savedScans.removeAll { $0.id == scan.id }
            total -= size
        }
    }

    // MARK: - Index Loading

    func loadScanIndex() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var loadedScans: [SavedScan] = []

        // Load LiDAR scans
        let scansDir = docs.appendingPathComponent("LiDARScans", isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(at: scansDir, includingPropertiesForKeys: nil) {
            for scanDirURL in contents {
                let metaURL = scanDirURL.appendingPathComponent("metadata.json")
                guard let metaData = try? Data(contentsOf: metaURL) else { continue }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                struct MetaStruct: Codable {
                    let id: String
                    let timestamp: Date
                    let pointCount: Int
                    let riskScore: Float?
                    var name: String?
                    var lat: Double?
                    var lon: Double?
                }

                guard let meta = try? decoder.decode(MetaStruct.self, from: metaData) else { continue }

                // Load SceneTag if available
                let sceneTag: Any? = nil // SceneTagStore loaded when available

                let scan = SavedScan(
                    id: UUID(uuidString: meta.id) ?? UUID(),
                    timestamp: meta.timestamp,
                    mode: "scan",
                    pointCount: meta.pointCount,
                    riskScore: meta.riskScore,
                    scanDir: scanDirURL,
                    name: meta.name ?? "",
                    latitude: meta.lat,
                    longitude: meta.lon,
                    sceneTag: sceneTag
                )
                loadedScans.append(scan)
            }
        }

        // Load Recon Walk sessions
        let reconDir = docs.appendingPathComponent("ReconWalks", isDirectory: true)
        if let reconContents = try? FileManager.default.contentsOfDirectory(at: reconDir, includingPropertiesForKeys: nil) {
            for sessionDirURL in reconContents {
                let sessionURL = sessionDirURL.appendingPathComponent("session.json")
                guard let data = try? Data(contentsOf: sessionURL) else { continue }

                struct SessionMeta: Codable {
                    let id: UUID
                    let startTime: Date
                    let totalPoints: Int
                    let segmentCount: Int
                    let totalDistance: Double
                }

                let decoder2 = JSONDecoder()
                decoder2.dateDecodingStrategy = .iso8601
                guard let meta = try? decoder2.decode(SessionMeta.self, from: data) else { continue }

                let scan = SavedScan(
                    id: meta.id,
                    timestamp: meta.startTime,
                    mode: "Recon Walk",
                    pointCount: meta.totalPoints,
                    riskScore: nil,
                    scanDir: sessionDirURL,
                    scanType: .reconWalk
                )
                loadedScans.append(scan)
            }
        }

        savedScans = loadedScans.sorted { $0.timestamp > $1.timestamp }

        // After every index load, make sure we're under the storage cap.
        // If this evicts anything, savedScans is updated in place.
        enforceStorageCapacity()
    }

    // MARK: - Update Scan

    func updateScanName(_ scan: SavedScan, newName: String) {
        let metaURL = scan.scanDir.appendingPathComponent("metadata.json")
        do {
            guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any] else { return }
            json["name"] = newName
            let updatedData = try JSONSerialization.data(withJSONObject: json)
            try updatedData.write(to: metaURL, options: .atomic)
        } catch {
            lastError = "Failed to save scan name: \(error.localizedDescription)"
        }
        loadScanIndex()
    }

    func updateRiskScore(for id: UUID, riskScore: Float) {
        guard let scan = savedScans.first(where: { $0.id == id }) else { return }
        let metaURL = scan.scanDir.appendingPathComponent("metadata.json")
        do {
            guard var json = try JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any] else { return }
            json["riskScore"] = riskScore
            let updatedData = try JSONSerialization.data(withJSONObject: json)
            try updatedData.write(to: metaURL, options: .atomic)
        } catch {
            lastError = "Failed to save risk score: \(error.localizedDescription)"
        }
        loadScanIndex()
    }

    func deleteScan(_ scan: SavedScan) {
        do {
            try FileManager.default.removeItem(at: scan.scanDir)
        } catch {
            lastError = "Failed to delete scan: \(error.localizedDescription)"
        }
        savedScans.removeAll { $0.id == scan.id }
        loadScanIndex()
    }
}
