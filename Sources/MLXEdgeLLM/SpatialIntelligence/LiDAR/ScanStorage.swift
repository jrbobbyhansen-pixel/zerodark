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
    var sceneTag: SceneTag?

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

    private init() {
        loadScanIndex()
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
                let sceneTag = SceneTagStore.shared.load(for: UUID(uuidString: meta.id) ?? UUID())

                let scan = SavedScan(
                    id: UUID(uuidString: meta.id) ?? UUID(),
                    timestamp: meta.timestamp,
                    mode: "scan",
                    pointCount: meta.pointCount,
                    riskScore: meta.riskScore ?? sceneTag?.riskScore,
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
    }

    // MARK: - Update Scan

    func updateScanName(_ scan: SavedScan, newName: String) {
        let metaURL = scan.scanDir.appendingPathComponent("metadata.json")
        guard var json = try? JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any] else { return }

        json["name"] = newName

        if let updatedData = try? JSONSerialization.data(withJSONObject: json) {
            try? updatedData.write(to: metaURL)
        }

        // Reload index to reflect changes
        loadScanIndex()
    }

    func updateRiskScore(for id: UUID, riskScore: Float) {
        guard let scan = savedScans.first(where: { $0.id == id }) else { return }
        let metaURL = scan.scanDir.appendingPathComponent("metadata.json")
        guard var json = try? JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any] else { return }

        json["riskScore"] = riskScore

        if let updatedData = try? JSONSerialization.data(withJSONObject: json) {
            try? updatedData.write(to: metaURL)
        }

        // Reload index to reflect changes
        loadScanIndex()
    }

    func deleteScan(_ scan: SavedScan) {
        try? FileManager.default.removeItem(at: scan.scanDir)
        savedScans.removeAll { $0.id == scan.id }
        loadScanIndex()
    }
}
