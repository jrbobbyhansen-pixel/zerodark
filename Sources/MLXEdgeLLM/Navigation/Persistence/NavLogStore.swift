// NavLogStore.swift — File-based persistence for navigation logs
// Stores NavLogEntry as JSON in Documents/NavLogs/, viewshed data LZFSE compressed

import Foundation
import Compression
import CoreLocation

// MARK: - NavLogEntry

struct NavLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let trail: [NavTrailPoint]
    let viewshedData: Data?          // LZFSE compressed ViewshedResult visibility
    let batteryTrend: Double
    let totalDistance: Double
    let duration: TimeInterval
    let zuptCount: Int
    let canopyPercentage: Double      // fraction of trail under canopy
}

// MARK: - NavLogStore

final class NavLogStore {
    static let shared = NavLogStore()

    private let directory: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("NavLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    func save(_ entry: NavLogEntry) throws {
        let data = try JSONEncoder().encode(entry)
        let file = directory.appendingPathComponent("\(entry.id.uuidString).json")
        try data.write(to: file, options: .atomic)
    }

    func loadAll() -> [NavLogEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { file -> NavLogEntry? in
                guard let data = try? Data(contentsOf: file) else { return nil }
                return try? JSONDecoder().decode(NavLogEntry.self, from: data)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func load(id: UUID) -> NavLogEntry? {
        let file = directory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(NavLogEntry.self, from: data)
    }

    func delete(id: UUID) {
        let file = directory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - GPX Export

    func exportGPX(entry: NavLogEntry) -> Data {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="ZeroDark NavLogStore">
          <metadata>
            <time>\(ISO8601DateFormatter().string(from: entry.timestamp))</time>
          </metadata>
          <trk>
            <name>Nav Log \(entry.id.uuidString.prefix(8))</name>
            <trkseg>
        """
        for point in entry.trail {
            gpx += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">"
            gpx += "<ele>\(point.altitude)</ele>"
            gpx += "</trkpt>\n"
        }
        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """
        return gpx.data(using: .utf8) ?? Data()
    }

    // MARK: - Viewshed Compression

    /// Compress viewshed visibility data using LZFSE
    static func compressViewshed(_ visibility: [Float]) -> Data? {
        let sourceData = visibility.withUnsafeBytes { Data($0) }
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceData.count)
        defer { destinationBuffer.deallocate() }

        let compressedSize = sourceData.withUnsafeBytes { sourceBytes -> Int in
            guard let sourcePtr = sourceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(
                destinationBuffer, sourceData.count,
                sourcePtr, sourceData.count,
                nil, COMPRESSION_LZFSE
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Decompress viewshed visibility data
    static func decompressViewshed(_ data: Data, expectedCount: Int) -> [Float]? {
        let expectedSize = expectedCount * MemoryLayout<Float>.stride
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { sourceBytes -> Int in
            guard let sourcePtr = sourceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(
                destinationBuffer, expectedSize,
                sourcePtr, data.count,
                nil, COMPRESSION_LZFSE
            )
        }

        guard decompressedSize == expectedSize else { return nil }
        return Array(UnsafeBufferPointer(
            start: destinationBuffer.withMemoryRebound(to: Float.self, capacity: expectedCount) { $0 },
            count: expectedCount
        ))
    }

    // MARK: - Create Entry from Current State

    @MainActor
    static func createEntry(
        trail: [NavTrailPoint],
        viewshed: ViewshedResult?,
        batteryTrend: Double,
        zuptCount: Int,
        canopyPercentage: Double
    ) -> NavLogEntry {
        // Calculate total distance
        var totalDistance: Double = 0
        for i in 1..<trail.count {
            let prev = CLLocation(latitude: trail[i-1].latitude, longitude: trail[i-1].longitude)
            let curr = CLLocation(latitude: trail[i].latitude, longitude: trail[i].longitude)
            totalDistance += prev.distance(from: curr)
        }

        // Duration from first to last point
        let duration: TimeInterval
        if let first = trail.first, let last = trail.last {
            duration = last.timestamp - first.timestamp
        } else {
            duration = 0
        }

        // Compress viewshed if available
        let viewshedData = viewshed.flatMap { NavLogStore.compressViewshed($0.visibility) }

        return NavLogEntry(
            id: UUID(),
            timestamp: Date(),
            trail: trail,
            viewshedData: viewshedData,
            batteryTrend: batteryTrend,
            totalDistance: totalDistance,
            duration: duration,
            zuptCount: zuptCount,
            canopyPercentage: canopyPercentage
        )
    }
}
