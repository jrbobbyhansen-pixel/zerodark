// TileDownloadManager.swift — Observable Offline Map Tile Download Job Manager

import Foundation
import MapKit
import Combine
import SQLite3

struct TileDownloadJob: Identifiable {
    let id = UUID()
    let regionName: String
    let bounds: MKCoordinateRegion
    let minZoom: Int
    let maxZoom: Int
    var totalTiles: Int = 0
    var downloadedTiles: Int = 0
    var failedTiles: Int = 0
    var status: DownloadStatus = .pending
    var estimatedBytes: Int64 = 0
    var downloadedBytes: Int64 = 0

    enum DownloadStatus {
        case pending, downloading, paused, complete, failed
    }

    var progress: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(downloadedTiles) / Double(totalTiles)
    }

    var estimatedStorageMB: Double {
        // OSM tiles average ~15KB at z14, ~5KB at z12, ~1KB at z8
        var total = 0.0
        for z in minZoom...maxZoom {
            let n = Double(1 << z)
            let minLat = bounds.center.latitude - bounds.span.latitudeDelta / 2
            let maxLat = bounds.center.latitude + bounds.span.latitudeDelta / 2
            let minLon = bounds.center.longitude - bounds.span.longitudeDelta / 2
            let maxLon = bounds.center.longitude + bounds.span.longitudeDelta / 2

            func lon2tile(_ lon: Double) -> Int { Int((lon + 180) / 360 * n) }
            func lat2tile(_ lat: Double) -> Int {
                let rad = lat * .pi / 180
                return Int((1 - log(tan(rad) + 1/cos(rad)) / .pi) / 2 * n)
            }

            let minX = lon2tile(minLon)
            let maxX = lon2tile(maxLon)
            let minY = lat2tile(maxLat)
            let maxY = lat2tile(minLat)
            let tilesAtZoom = (maxX - minX + 1) * (maxY - minY + 1)

            let avgKB: Double
            switch z {
            case 0...8:  avgKB = 1.0
            case 9...12: avgKB = 5.0
            case 13...15: avgKB = 15.0
            default:     avgKB = 40.0
            }
            total += Double(tilesAtZoom) * avgKB / 1024.0
        }
        return total
    }
}

@MainActor
final class TileDownloadManager: ObservableObject {
    static let shared = TileDownloadManager()

    @Published var jobs: [TileDownloadJob] = []
    @Published var activeJob: TileDownloadJob? = nil
    @Published var isDownloading = false

    private let urlSession = URLSession(configuration: {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 8
        config.httpAdditionalHeaders = ["User-Agent": "ZeroDark/1.0 offline-map-download"]
        return config
    }())

    private let mbtileDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("OfflineMaps", isDirectory: true)
    }()

    private init() {
        try? FileManager.default.createDirectory(at: mbtileDirectory, withIntermediateDirectories: true)
    }

    // Calculate total tile count for a region and zoom range
    func estimateTileCount(bounds: MKCoordinateRegion, minZoom: Int, maxZoom: Int) -> Int {
        var total = 0
        for z in minZoom...maxZoom {
            total += tileCount(bounds: bounds, zoom: z)
        }
        return total
    }

    // Start downloading a region
    func startDownload(
        regionName: String,
        bounds: MKCoordinateRegion,
        minZoom: Int = 8,
        maxZoom: Int = 16,
        tileURLTemplate: String = AppConfig.osmTileURLTemplate
    ) async {
        var job = TileDownloadJob(regionName: regionName, bounds: bounds, minZoom: minZoom, maxZoom: maxZoom)
        job.totalTiles = estimateTileCount(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom)
        jobs.append(job)
        isDownloading = true
        activeJob = job

        // Create MBTiles SQLite database
        let dbPath = mbtileDirectory.appendingPathComponent("\(regionName).mbtiles")
        guard let db = createMBTilesDB(at: dbPath) else {
            if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[idx].status = .failed
            }
            isDownloading = false
            return
        }

        // Build flat tile list
        var allTiles: [(z: Int, x: Int, y: Int)] = []
        for z in minZoom...maxZoom {
            let (minX, maxX, minY, maxY) = tileRange(bounds: bounds, zoom: z)
            for x in minX...maxX {
                for y in minY...maxY {
                    allTiles.append((z, x, y))
                }
            }
        }

        // Download in batches of 8 concurrent tiles (respects httpMaximumConnectionsPerHost)
        let batchSize = 8
        let session = urlSession  // capture non-isolated for task group
        var batchStart = 0
        while batchStart < allTiles.count {
            guard isDownloading else { break }

            let batchEnd = min(batchStart + batchSize, allTiles.count)
            let batch = Array(allTiles[batchStart..<batchEnd])

            // Download this batch concurrently, collect results
            let results: [(z: Int, x: Int, y: Int, data: Data?)] = await withTaskGroup(
                of: (Int, Int, Int, Data?).self
            ) { group in
                for tile in batch {
                    let urlStr = tileURLTemplate
                        .replacingOccurrences(of: "{z}", with: "\(tile.z)")
                        .replacingOccurrences(of: "{x}", with: "\(tile.x)")
                        .replacingOccurrences(of: "{y}", with: "\(tile.y)")
                    guard let url = URL(string: urlStr) else { continue }
                    group.addTask {
                        do {
                            let (data, _) = try await session.data(from: url)
                            return (tile.z, tile.x, tile.y, data)
                        } catch {
                            return (tile.z, tile.x, tile.y, nil)
                        }
                    }
                }
                var out: [(Int, Int, Int, Data?)] = []
                for await r in group { out.append(r) }
                return out
            }

            // Write to SQLite on main actor (SQLite writes must be serial)
            for (z, x, y, data) in results {
                if let data = data {
                    writeTile(db: db, z: z, x: x, y: y, data: data)
                    if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                        jobs[idx].downloadedTiles += 1
                        jobs[idx].downloadedBytes += Int64(data.count)
                        activeJob = jobs[idx]
                    }
                } else {
                    if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                        jobs[idx].failedTiles += 1
                    }
                }
            }

            batchStart += batchSize
        }

        sqlite3_close(db)

        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx].status = .complete
        }
        isDownloading = false
        activeJob = nil
    }

    func cancelDownload() {
        isDownloading = false
    }

    func deleteRegion(named regionName: String) {
        let path = mbtileDirectory.appendingPathComponent("\(regionName).mbtiles")
        try? FileManager.default.removeItem(at: path)
        jobs.removeAll { $0.regionName == regionName }
    }

    // MARK: - MBTiles SQLite helpers

    private func createMBTilesDB(at url: URL) -> OpaquePointer? {
        // Create MBTiles format SQLite DB with tiles table
        // MBTiles spec: zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return nil }
        let createSQL = """
            CREATE TABLE IF NOT EXISTS metadata (name TEXT, value TEXT);
            CREATE TABLE IF NOT EXISTS tiles (
                zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER,
                tile_data BLOB, UNIQUE(zoom_level, tile_column, tile_row)
            );
            CREATE UNIQUE INDEX IF NOT EXISTS tile_index ON tiles (zoom_level, tile_column, tile_row);
            INSERT OR REPLACE INTO metadata VALUES ('name', 'ZeroDark');
            INSERT OR REPLACE INTO metadata VALUES ('format', 'png');
        """
        sqlite3_exec(db, createSQL, nil, nil, nil)
        return db
    }

    private func writeTile(db: OpaquePointer, z: Int, x: Int, y: Int, data: Data) {
        // MBTiles uses TMS y (inverted): tmsY = (2^z - 1) - y
        let tmsY = (1 << z) - 1 - y
        let sql = "INSERT OR REPLACE INTO tiles (zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int(stmt, 1, Int32(z))
        sqlite3_bind_int(stmt, 2, Int32(x))
        sqlite3_bind_int(stmt, 3, Int32(tmsY))
        data.withUnsafeBytes { ptr in
            // Use nil as destructor since memory is managed by Swift
            _ = sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(data.count), nil)
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Tile coordinate math

    private func tileCount(bounds: MKCoordinateRegion, zoom: Int) -> Int {
        let (minX, maxX, minY, maxY) = tileRange(bounds: bounds, zoom: zoom)
        return (maxX - minX + 1) * (maxY - minY + 1)
    }

    private func tileRange(bounds: MKCoordinateRegion, zoom: Int) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let n = Double(1 << zoom)
        let minLat = bounds.center.latitude - bounds.span.latitudeDelta / 2
        let maxLat = bounds.center.latitude + bounds.span.latitudeDelta / 2
        let minLon = bounds.center.longitude - bounds.span.longitudeDelta / 2
        let maxLon = bounds.center.longitude + bounds.span.longitudeDelta / 2

        func lon2tile(_ lon: Double) -> Int { Int((lon + 180) / 360 * n) }
        func lat2tile(_ lat: Double) -> Int {
            let rad = lat * .pi / 180
            return Int((1 - log(tan(rad) + 1/cos(rad)) / .pi) / 2 * n)
        }

        return (lon2tile(minLon), lon2tile(maxLon), lat2tile(maxLat), lat2tile(minLat))
    }
}
