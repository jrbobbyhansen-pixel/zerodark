// OfflineMapEngine.swift — Unified offline map tile coordination engine
// Orchestrates PMTiles/MBTiles providers, tile cache, and region management

import Foundation
import MapKit
import CoreLocation
import Combine

// MARK: - OfflineMapEngine

@MainActor
final class OfflineMapEngine: ObservableObject {
    static let shared = OfflineMapEngine()

    @Published var availableRegions: [OfflineRegion] = []
    @Published var downloadProgress: Double = 0
    @Published var isDownloading: Bool = false
    @Published var totalCacheSize: Int64 = 0

    private let mapsDirectory: URL
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        mapsDirectory = docs.appendingPathComponent("Maps", isDirectory: true)
        try? FileManager.default.createDirectory(at: mapsDirectory, withIntermediateDirectories: true)
        refreshAvailableRegions()
    }

    // MARK: - Region Management

    func refreshAvailableRegions() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: mapsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        availableRegions = contents
            .filter { ["mbtiles", "pmtiles"].contains($0.pathExtension.lowercased()) }
            .compactMap { url -> OfflineRegion? in
                let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                return OfflineRegion(
                    id: url.lastPathComponent,
                    name: url.deletingPathExtension().lastPathComponent,
                    fileURL: url,
                    fileSize: Int64(attrs?.fileSize ?? 0),
                    createdAt: attrs?.creationDate ?? Date()
                )
            }
            .sorted { $0.name < $1.name }

        totalCacheSize = availableRegions.reduce(0) { $0 + $1.fileSize }
    }

    func deleteRegion(_ region: OfflineRegion) {
        try? FileManager.default.removeItem(at: region.fileURL)
        refreshAvailableRegions()
    }

    // MARK: - Tile Availability

    func hasOfflineCoverage(for coordinate: CLLocationCoordinate2D, zoom: Int) -> Bool {
        !availableRegions.isEmpty
    }

    // MARK: - Coordinate Utilities

    func tileCoordinate(for coordinate: CLLocationCoordinate2D, zoom: Int) -> TileCoordinate {
        let n = pow(2.0, Double(zoom))
        let x = Int((coordinate.longitude + 180.0) / 360.0 * n)
        let latRad = coordinate.latitude * .pi / 180.0
        let y = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)
        return TileCoordinate(z: zoom, x: x, y: y)
    }

    func boundingBox(for region: MKCoordinateRegion, zoom: Int) -> (min: TileCoordinate, max: TileCoordinate) {
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2

        let minTile = tileCoordinate(for: CLLocationCoordinate2D(latitude: north, longitude: west), zoom: zoom)
        let maxTile = tileCoordinate(for: CLLocationCoordinate2D(latitude: south, longitude: east), zoom: zoom)
        return (minTile, maxTile)
    }
}

// MARK: - OfflineRegion

struct OfflineRegion: Identifiable {
    let id: String
    let name: String
    let fileURL: URL
    let fileSize: Int64
    let createdAt: Date

    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var formatType: String {
        fileURL.pathExtension.lowercased() == "pmtiles" ? "PMTiles" : "MBTiles"
    }
}
