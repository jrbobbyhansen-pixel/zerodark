// OfflineTileProvider.swift — Read PMTiles/MBTiles for offline maps
// Supports USB-transferred map packages in Documents/Maps/

import Foundation
import MapKit
import SQLite3

// MARK: - Tile Coordinate

struct TileCoordinate: Hashable {
    let z: Int  // zoom level
    let x: Int  // column
    let y: Int  // row (TMS or XYZ depending on format)
    
    var tmsY: Int {
        // Convert XYZ to TMS (flip Y)
        (1 << z) - 1 - y
    }
}

// MARK: - MBTiles Reader

final class MBTilesReader {
    private var db: OpaquePointer?
    private let path: URL
    private var metadata: [String: String] = [:]
    
    var name: String { metadata["name"] ?? path.deletingPathExtension().lastPathComponent }
    var format: String { metadata["format"] ?? "png" }
    var minZoom: Int { Int(metadata["minzoom"] ?? "0") ?? 0 }
    var maxZoom: Int { Int(metadata["maxzoom"] ?? "18") ?? 18 }
    var attribution: String { metadata["attribution"] ?? "OpenStreetMap contributors" }
    
    init?(path: URL) {
        self.path = path
        
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        
        loadMetadata()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func loadMetadata() {
        let sql = "SELECT name, value FROM metadata"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 0),
               let valuePtr = sqlite3_column_text(stmt, 1) {
                let name = String(cString: namePtr)
                let value = String(cString: valuePtr)
                metadata[name] = value
            }
        }
    }
    
    func getTile(at coord: TileCoordinate) -> Data? {
        let sql = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_bind_int(stmt, 1, Int32(coord.z)) == SQLITE_OK,
              sqlite3_bind_int(stmt, 2, Int32(coord.x)) == SQLITE_OK,
              sqlite3_bind_int(stmt, 3, Int32(coord.tmsY)) == SQLITE_OK else { return nil }  // MBTiles uses TMS
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        let bytes = sqlite3_column_blob(stmt, 0)
        let length = sqlite3_column_bytes(stmt, 0)
        
        guard let bytes = bytes, length > 0 else { return nil }
        
        return Data(bytes: bytes, count: Int(length))
    }
}

// MARK: - PMTiles Reader (Protomaps format)

final class PMTilesReader {
    private let fileHandle: FileHandle
    private let path: URL
    private var header: PMTilesHeader?
    private var rootDirectory: [PMTilesEntry] = []
    
    struct PMTilesHeader {
        let version: UInt8
        let rootDirectoryOffset: UInt64
        let rootDirectoryLength: UInt64
        let jsonMetadataOffset: UInt64
        let jsonMetadataLength: UInt64
        let leafDirectoryOffset: UInt64
        let tileDataOffset: UInt64
        let tileDataLength: UInt64
        let numAddressedTiles: UInt64
        let numTileEntries: UInt64
        let numTileContents: UInt64
        let clustered: Bool
        let internalCompression: UInt8
        let tileCompression: UInt8
        let tileType: UInt8
        let minZoom: UInt8
        let maxZoom: UInt8
        let minLon: Double
        let minLat: Double
        let maxLon: Double
        let maxLat: Double
    }
    
    struct PMTilesEntry {
        let tileId: UInt64
        let offset: UInt64
        let length: UInt32
        let runLength: UInt32
    }
    
    init?(path: URL) {
        self.path = path
        
        guard let handle = try? FileHandle(forReadingFrom: path) else {
            return nil
        }
        self.fileHandle = handle
        
        do {
            guard try parseHeader() else {
                return nil
            }
        } catch {
            return nil
        }
    }
    
    deinit {
        try? fileHandle.close()
    }
    
    private func parseHeader() throws -> Bool {
        guard let data = try? fileHandle.read(upToCount: 127) else { return false }
        guard data.count >= 127 else { return false }
        
        // Magic bytes check: "PMTiles"
        guard data.count >= 7 else { return false }
        let magicData = data.subdata(in: 0..<7)
        let magic = String(data: magicData, encoding: .utf8)
        guard magic == "PMTiles" else { return false }
        
        let version = data[7]
        guard version == 3 else { return false }  // Only support v3
        
        // Safe reading helper
        func safeReadUInt64(at offset: Int) -> UInt64 {
            guard offset + 8 <= data.count else { return 0 }
            var value: UInt64 = 0
            for i in 0..<8 {
                value |= UInt64(data[offset + i]) << (8 * i)
            }
            return value
        }
        
        func safeReadInt32(at offset: Int) -> Int32 {
            guard offset + 4 <= data.count else { return 0 }
            var value: Int32 = 0
            let bytes = [data[offset], data[offset+1], data[offset+2], data[offset+3]]
            withUnsafeMutableBytes(of: &value) { ptr in
                ptr.copyBytes(from: bytes)
            }
            return Int32(bigEndian: value)
        }
        
        // Parse header fields safely
        header = PMTilesHeader(
            version: version,
            rootDirectoryOffset: safeReadUInt64(at: 8),
            rootDirectoryLength: safeReadUInt64(at: 16),
            jsonMetadataOffset: safeReadUInt64(at: 24),
            jsonMetadataLength: safeReadUInt64(at: 32),
            leafDirectoryOffset: safeReadUInt64(at: 40),
            tileDataOffset: safeReadUInt64(at: 48),
            tileDataLength: safeReadUInt64(at: 56),
            numAddressedTiles: safeReadUInt64(at: 64),
            numTileEntries: safeReadUInt64(at: 72),
            numTileContents: safeReadUInt64(at: 80),
            clustered: data.count > 88 ? data[88] == 1 : false,
            internalCompression: data.count > 89 ? data[89] : 0,
            tileCompression: data.count > 90 ? data[90] : 0,
            tileType: data.count > 91 ? data[91] : 0,
            minZoom: data.count > 92 ? data[92] : 0,
            maxZoom: data.count > 93 ? data[93] : 18,
            minLon: Double(safeReadInt32(at: 94)) / 10_000_000,
            minLat: Double(safeReadInt32(at: 98)) / 10_000_000,
            maxLon: Double(safeReadInt32(at: 102)) / 10_000_000,
            maxLat: Double(safeReadInt32(at: 106)) / 10_000_000
        )
        
        return true
    }
    
    func getTile(at coord: TileCoordinate) -> Data? {
        guard let header = header else { return nil }
        
        // Convert z/x/y to Hilbert curve tile ID
        let tileId = zxyToTileId(z: coord.z, x: coord.x, y: coord.y)
        
        // Search for tile in directory (simplified - full impl needs directory traversal)
        // For now, calculate offset directly for clustered tiles
        
        do {
            try fileHandle.seek(toOffset: header.tileDataOffset + tileId * 256)
            guard let tileData = try fileHandle.read(upToCount: 256) else { return nil }
            return tileData.isEmpty ? nil : tileData
        } catch {
            return nil
        }
    }
    
    private func zxyToTileId(z: Int, x: Int, y: Int) -> UInt64 {
        // Simplified tile ID calculation
        // Full implementation would use Hilbert curve
        var id: UInt64 = 0
        for i in 0..<z {
            let level = z - 1 - i
            let rx = (x >> level) & 1
            let ry = (y >> level) & 1
            id += UInt64((1 << (2 * level)) * ((3 * rx) ^ ry))
        }
        return id
    }
}

// MARK: - Unified Tile Provider

@MainActor
final class OfflineTileProvider: ObservableObject {
    static let shared = OfflineTileProvider()
    
    @Published var availableMaps: [String] = []
    @Published var currentMap: String?
    
    private var mbtilesReaders: [String: MBTilesReader] = [:]
    private var pmtilesReaders: [String: PMTilesReader] = [:]
    private var tileCache = NSCache<NSString, NSData>()
    
    private init() {
        tileCache.countLimit = 500  // Cache 500 tiles in memory
        scanForMaps()
    }
    
    func scanForMaps() {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mapsDir = documentsDir.appendingPathComponent("OfflineMaps", isDirectory: true)

        availableMaps.removeAll()
        mbtilesReaders.removeAll()
        pmtilesReaders.removeAll()

        // Collect map files from both locations
        var mapURLs: [URL] = []

        // 1. Check OfflineMaps subfolder
        if let contents = try? FileManager.default.contentsOfDirectory(at: mapsDir, includingPropertiesForKeys: nil) {
            mapURLs.append(contentsOf: contents)
        }

        // 2. Check Documents root (Finder drops files here, can't navigate into subfolders)
        if let rootContents = try? FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
            let rootMaps = rootContents.filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "mbtiles" || ext == "pmtiles"
            }
            mapURLs.append(contentsOf: rootMaps)
        }

        let containerRoot = documentsDir.deletingLastPathComponent()

        // 3. Check container root /OfflineMaps/
        let containerMapsDir = containerRoot.appendingPathComponent("OfflineMaps", isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(at: containerMapsDir,
            includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            let maps = contents.filter { ["mbtiles", "pmtiles"].contains($0.pathExtension.lowercased()) }
            mapURLs.append(contentsOf: maps)
        }

        // 4. Check Documents/Maps/
        let docsMapsDir = documentsDir.appendingPathComponent("Maps", isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(at: docsMapsDir,
            includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            let maps = contents.filter { ["mbtiles", "pmtiles"].contains($0.pathExtension.lowercased()) }
            mapURLs.append(contentsOf: maps)
        }

        for url in mapURLs {
            let ext = url.pathExtension.lowercased()
            let name = url.deletingPathExtension().lastPathComponent

            if ext == "mbtiles" {
                if let reader = MBTilesReader(path: url) {
                    mbtilesReaders[name] = reader
                    availableMaps.append(name)
                }
            } else if ext == "pmtiles" {
                // PMTiles parsing can fail — wrapped in failable init
                if let reader = PMTilesReader(path: url) {
                    pmtilesReaders[name] = reader
                    availableMaps.append(name)
                } else {
                }
            }
        }

        if currentMap == nil, let first = availableMaps.first {
            currentMap = first
        }
    }
    
    func getTile(z: Int, x: Int, y: Int) -> Data? {
        guard let mapName = currentMap else { return nil }
        
        // Check cache
        let cacheKey = "\(mapName)-\(z)-\(x)-\(y)" as NSString
        if let cached = tileCache.object(forKey: cacheKey) {
            return cached as Data
        }
        
        let coord = TileCoordinate(z: z, x: x, y: y)
        var tileData: Data?
        
        if let reader = mbtilesReaders[mapName] {
            tileData = reader.getTile(at: coord)
        } else if let reader = pmtilesReaders[mapName] {
            tileData = reader.getTile(at: coord)
        }
        
        // Cache result
        if let data = tileData {
            tileCache.setObject(data as NSData, forKey: cacheKey)
        }
        
        return tileData
    }
    
    func selectMap(_ name: String) {
        guard availableMaps.contains(name) else { return }
        currentMap = name
        tileCache.removeAllObjects()
    }
    
    var hasOfflineMaps: Bool {
        !availableMaps.isEmpty
    }
}

// MARK: - MapKit Tile Overlay

final class OfflineTileOverlay: MKTileOverlay {
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        Task { @MainActor in
            if let tileData = OfflineTileProvider.shared.getTile(z: path.z, x: path.x, y: path.y) {
                result(tileData, nil)
            } else {
                // Return transparent tile if not found
                result(nil, nil)
            }
        }
    }
}
