// OfflineMapEngine.swift — MBTiles Offline Map Storage & OpenStreetMap Tile Downloader

import Foundation
import MapKit
import SQLite3

/// MBTiles SQLite reader for offline map tiles
final class MBTilesStore {
    static let shared = MBTilesStore()

    private let fileManager = FileManager.default
    private let maptileDirectory: URL
    private var dbConnections: [String: OpaquePointer] = [:]

    private init() {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        maptileDirectory = paths[0].appendingPathComponent("OfflineMaps", isDirectory: true)
        try? fileManager.createDirectory(at: maptileDirectory, withIntermediateDirectories: true)
    }

    deinit {
        for (_, db) in dbConnections {
            sqlite3_close(db)
        }
    }

    /// Fetch a single tile from the MBTiles store
    func tile(x: Int, y: Int, z: Int, from regionName: String = "default") -> Data? {
        let mbtPath = maptileDirectory.appendingPathComponent("\(regionName).mbtiles")
        guard fileManager.fileExists(atPath: mbtPath.path) else { return nil }

        var db: OpaquePointer?
        let result = sqlite3_open(mbtPath.path, &db)
        guard result == SQLITE_OK, let database = db else { return nil }
        defer { sqlite3_close(database) }

        // MBTiles format: y coordinate is inverted (TMS convention)
        let tmsY = (1 << z) - 1 - y

        let query = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(z))
        sqlite3_bind_int(stmt, 2, Int32(x))
        sqlite3_bind_int(stmt, 3, Int32(tmsY))

        if sqlite3_step(stmt) == SQLITE_ROW {
            let dataPtr = sqlite3_column_blob(stmt, 0)
            let dataSize = sqlite3_column_bytes(stmt, 0)
            return Data(bytes: dataPtr!, count: Int(dataSize))
        }

        return nil
    }

    /// Get list of downloaded map regions with metadata
    func storedRegions() -> [MapRegion] {
        let contents = try? fileManager.contentsOfDirectory(
            at: maptileDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        return (contents ?? [])
            .filter { $0.pathExtension == "mbtiles" }
            .compactMap { url in
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let size = attrs?[.size] as? Int ?? 0
                return MapRegion(
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url,
                    sizeBytes: size
                )
            }
    }

    /// Download tiles for a bounding box from OpenStreetMap
    func downloadRegion(
        boundingBox: MKCoordinateRegion,
        maxZoom: Int,
        regionName: String = "default",
        progress: @escaping (Double) -> Void
    ) async throws {
        let mbtPath = maptileDirectory.appendingPathComponent("\(regionName).mbtiles")

        // Initialize MBTiles database
        try initializeDatabase(at: mbtPath)

        let minLat = boundingBox.center.latitude - (boundingBox.span.latitudeDelta / 2)
        let maxLat = boundingBox.center.latitude + (boundingBox.span.latitudeDelta / 2)
        let minLon = boundingBox.center.longitude - (boundingBox.span.longitudeDelta / 2)
        let maxLon = boundingBox.center.longitude + (boundingBox.span.longitudeDelta / 2)

        var totalTiles = 0
        var downloadedTiles = 0

        // Calculate total tiles needed
        for z in 0...maxZoom {
            let (minX, maxX) = longitudeToTileX(minLon: minLon, maxLon: maxLon, zoom: z)
            let (minY, maxY) = latitudeToTileY(minLat: minLat, maxLat: maxLat, zoom: z)
            totalTiles += (maxX - minX + 1) * (maxY - minY + 1)
        }

        // Download tiles
        for z in 0...maxZoom {
            let (minX, maxX) = longitudeToTileX(minLon: minLon, maxLon: maxLon, zoom: z)
            let (minY, maxY) = latitudeToTileY(minLat: minLat, maxLat: maxLat, zoom: z)

            for x in minX...maxX {
                for y in minY...maxY {
                    if let tileData = await downloadSingleTile(x: x, y: y, z: z) {
                        try storeTile(data: tileData, x: x, y: y, z: z, at: mbtPath)
                    }

                    downloadedTiles += 1
                    progress(Double(downloadedTiles) / Double(totalTiles))
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func initializeDatabase(at path: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path.path) {
            return
        }

        var db: OpaquePointer?
        let result = sqlite3_open(path.path, &db)
        guard result == SQLITE_OK, let database = db else {
            throw NSError(domain: "MBTiles", code: -1, userInfo: nil)
        }
        defer { sqlite3_close(database) }

        let createTables = """
            CREATE TABLE IF NOT EXISTS tiles (
                zoom_level INTEGER,
                tile_column INTEGER,
                tile_row INTEGER,
                tile_data BLOB
            );
            CREATE UNIQUE INDEX IF NOT EXISTS tile_index
                ON tiles (zoom_level, tile_column, tile_row);
            CREATE TABLE IF NOT EXISTS metadata (
                name TEXT,
                value TEXT
            );
        """

        let result2 = sqlite3_exec(database, createTables, nil, nil, nil)
        guard result2 == SQLITE_OK else {
            throw NSError(domain: "MBTiles", code: -1, userInfo: nil)
        }
    }

    private func storeTile(data: Data, x: Int, y: Int, z: Int, at path: URL) throws {
        var db: OpaquePointer?
        let result = sqlite3_open(path.path, &db)
        guard result == SQLITE_OK, let database = db else { return }
        defer { sqlite3_close(database) }

        let tmsY = (1 << z) - 1 - y
        let query = "INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(database, query, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(z))
        sqlite3_bind_int(stmt, 2, Int32(x))
        sqlite3_bind_int(stmt, 3, Int32(tmsY))
        sqlite3_bind_blob(stmt, 4, (data as NSData).bytes, Int32(data.count), nil)

        sqlite3_step(stmt)
    }

    private func downloadSingleTile(x: Int, y: Int, z: Int) async -> Data? {
        let urlString = "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func longitudeToTileX(minLon: Double, maxLon: Double, zoom: Int) -> (Int, Int) {
        let n = Double(1 << zoom)
        let minX = Int((minLon + 180) / 360 * n)
        let maxX = Int((maxLon + 180) / 360 * n) - 1
        return (minX, maxX)
    }

    private func latitudeToTileY(minLat: Double, maxLat: Double, zoom: Int) -> (Int, Int) {
        let n = Double(1 << zoom)
        let minY = Int((1 - log(tan(deg2rad(maxLat)) + 1 / cos(deg2rad(maxLat))) / .pi) / 2 * n)
        let maxY = Int((1 - log(tan(deg2rad(minLat)) + 1 / cos(deg2rad(minLat))) / .pi) / 2 * n) - 1
        return (minY, maxY)
    }

    private func deg2rad(_ degrees: Double) -> Double {
        return degrees * .pi / 180
    }
}

/// MKTileOverlay subclass that reads from MBTiles
final class OfflineMBTilesOverlay: MKTileOverlay {
    let regionName: String

    init(regionName: String = "default") {
        self.regionName = regionName
        super.init(urlTemplate: "dummy")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // This is a workaround since we're using SQLite, not URLs
        // The real tile data comes from loadTile()
        return URL(fileURLWithPath: "")
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        if let data = MBTilesStore.shared.tile(x: Int(path.x), y: Int(path.y), z: Int(path.z), from: regionName) {
            result(data, nil)
        } else {
            // Fallback to network tile
            downloadNetworkTile(x: Int(path.x), y: Int(path.y), z: Int(path.z), result: result)
        }
    }

    private func downloadNetworkTile(x: Int, y: Int, z: Int, result: @escaping (Data?, Error?) -> Void) {
        let urlString = "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png"
        guard let url = URL(string: urlString) else {
            result(nil, NSError(domain: "OfflineMaps", code: -1))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, (response as? HTTPURLResponse)?.statusCode == 200 {
                result(data, nil)
            } else {
                result(nil, error ?? NSError(domain: "OfflineMaps", code: -1))
            }
        }.resume()
    }
}

/// Region metadata
struct MapRegion {
    let name: String
    let path: URL
    let sizeBytes: Int

    var sizeString: String {
        let mb = Double(sizeBytes) / 1024 / 1024
        return String(format: "%.1f MB", mb)
    }
}
