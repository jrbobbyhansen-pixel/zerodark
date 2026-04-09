// GeoPackageService.swift — GeoPackage reader using raw SQLite3
// GeoPackage files are SQLite databases with spatial feature tables.
// Reads gpkg_contents + feature tables + geometry blobs.

import Foundation
import CoreLocation
import SQLite3

// MARK: - GeoPackage Feature Model

struct GPKGFeature: Identifiable, Sendable {
    let id: String
    let name: String
    let geometryType: GeometryType
    let coordinates: [CLLocationCoordinate2D]
    let properties: [String: String]

    enum GeometryType: String, Sendable {
        case point       = "Point"
        case lineString  = "LineString"
        case polygon     = "Polygon"
        case multiPoint  = "MultiPoint"
        case unknown     = "Unknown"
    }
}

// MARK: - GeoPackage Layer Model

struct GPKGLayer: Identifiable, Sendable {
    let id: String
    let name: String
    let featureCount: Int
    let geometryType: GPKGFeature.GeometryType
}

// MARK: - GeoPackage Service

@MainActor
final class GeoPackageService: ObservableObject {
    static let shared = GeoPackageService()

    @Published var importedLayers: [GPKGLayer] = []
    @Published var isImporting = false
    @Published var currentFileName: String?
    @Published var errorMessage: String?

    private var dbPointer: OpaquePointer?

    private let geoPackageDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("GeoPackages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - File Management

    func listAvailableFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: geoPackageDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "gpkg" }
    }

    // MARK: - Import

    func importGeoPackage(from url: URL) async throws {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        // Copy to Documents/GeoPackages if needed
        let destURL = geoPackageDir.appendingPathComponent(url.lastPathComponent)
        if url != destURL {
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: url, to: destURL)
        }
        currentFileName = url.lastPathComponent

        // Open SQLite database
        closeDatabase()
        guard sqlite3_open_v2(destURL.path, &dbPointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            errorMessage = "Failed to open GeoPackage database"
            return
        }

        // Read gpkg_contents table to discover layers
        var layers: [GPKGLayer] = []
        var stmt: OpaquePointer?
        let query = "SELECT table_name, data_type FROM gpkg_contents WHERE data_type = 'features'"

        if sqlite3_prepare_v2(dbPointer, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let tableNameC = sqlite3_column_text(stmt, 0) else { continue }
                let tableName = String(cString: tableNameC)

                // Count features in table
                let count = countRows(in: tableName)

                // Detect geometry type from gpkg_geometry_columns
                let geomType = detectGeometryType(for: tableName)

                layers.append(GPKGLayer(
                    id: tableName,
                    name: tableName,
                    featureCount: count,
                    geometryType: geomType
                ))
            }
        }
        sqlite3_finalize(stmt)

        importedLayers = layers
    }

    // MARK: - Read Features

    func getFeatures(from layerName: String, limit: Int = 500) -> [GPKGFeature] {
        guard let db = dbPointer else { return [] }
        var features: [GPKGFeature] = []
        var stmt: OpaquePointer?

        // Get geometry column name
        let geomCol = geometryColumnName(for: layerName) ?? "geom"

        // Read feature rows
        let query = "SELECT rowid, \(geomCol) FROM \"\(layerName)\" LIMIT \(limit)"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)

            // Parse GeoPackage binary geometry header
            if let blobPointer = sqlite3_column_blob(stmt, 1) {
                let blobSize = Int(sqlite3_column_bytes(stmt, 1))
                let data = Data(bytes: blobPointer, count: blobSize)

                if let (geomType, coords) = parseGeoPackageGeometry(data) {
                    features.append(GPKGFeature(
                        id: "\(layerName)_\(rowid)",
                        name: "\(layerName) #\(rowid)",
                        geometryType: geomType,
                        coordinates: coords,
                        properties: [:]
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)
        return features
    }

    // MARK: - Close

    func closeGeoPackage() {
        closeDatabase()
        importedLayers = []
        currentFileName = nil
    }

    private func closeDatabase() {
        if let db = dbPointer {
            sqlite3_close(db)
            dbPointer = nil
        }
    }

    // MARK: - SQLite Helpers

    private func countRows(in table: String) -> Int {
        guard let db = dbPointer else { return 0 }
        var stmt: OpaquePointer?
        let query = "SELECT COUNT(*) FROM \"\(table)\""
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    private func detectGeometryType(for table: String) -> GPKGFeature.GeometryType {
        guard let db = dbPointer else { return .unknown }
        var stmt: OpaquePointer?
        let query = "SELECT geometry_type_name FROM gpkg_geometry_columns WHERE table_name = ?"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return .unknown }
        sqlite3_bind_text(stmt, 1, (table as NSString).utf8String, -1, nil)
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let typeC = sqlite3_column_text(stmt, 0) else { return .unknown }
        let typeName = String(cString: typeC).uppercased()

        switch typeName {
        case "POINT", "MULTIPOINT": return typeName == "POINT" ? .point : .multiPoint
        case "LINESTRING", "MULTILINESTRING": return .lineString
        case "POLYGON", "MULTIPOLYGON": return .polygon
        default: return .unknown
        }
    }

    private func geometryColumnName(for table: String) -> String? {
        guard let db = dbPointer else { return nil }
        var stmt: OpaquePointer?
        let query = "SELECT column_name FROM gpkg_geometry_columns WHERE table_name = ?"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, (table as NSString).utf8String, -1, nil)
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let colC = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: colC)
    }

    // MARK: - GeoPackage Binary Geometry Parser

    /// Parse GeoPackage Standard Binary geometry header + WKB payload
    /// Header: 2-byte magic (GP), 1 byte version, 1 byte flags, 4 byte SRS ID, envelope, then WKB
    private func parseGeoPackageGeometry(_ data: Data) -> (GPKGFeature.GeometryType, [CLLocationCoordinate2D])? {
        guard data.count >= 8 else { return nil }

        // Verify magic bytes "GP" (0x47, 0x50)
        guard data[0] == 0x47, data[1] == 0x50 else { return nil }

        let flags = data[3]
        let envelopeType = (flags >> 1) & 0x07
        let byteOrder = flags & 0x01 // 0 = big endian, 1 = little endian

        // Calculate envelope size
        let envelopeSize: Int
        switch envelopeType {
        case 0: envelopeSize = 0
        case 1: envelopeSize = 32  // minX, maxX, minY, maxY
        case 2: envelopeSize = 48  // + minZ, maxZ
        case 3: envelopeSize = 48  // + minM, maxM
        case 4: envelopeSize = 64  // + minZ, maxZ, minM, maxM
        default: envelopeSize = 0
        }

        let wkbOffset = 8 + envelopeSize
        guard data.count > wkbOffset + 5 else { return nil }

        // Parse WKB: 1 byte order + 4 byte type + geometry data
        let wkbData = data.dropFirst(wkbOffset)
        return parseWKB(Data(wkbData))
    }

    private func parseWKB(_ data: Data) -> (GPKGFeature.GeometryType, [CLLocationCoordinate2D])? {
        guard data.count >= 5 else { return nil }

        let littleEndian = data[0] == 0x01
        let wkbType = readUInt32(data, offset: 1, littleEndian: littleEndian)

        switch wkbType {
        case 1: // Point
            guard data.count >= 21 else { return nil }
            let x = readDouble(data, offset: 5, littleEndian: littleEndian)
            let y = readDouble(data, offset: 13, littleEndian: littleEndian)
            return (.point, [CLLocationCoordinate2D(latitude: y, longitude: x)])

        case 2: // LineString
            guard data.count >= 9 else { return nil }
            let numPoints = Int(readUInt32(data, offset: 5, littleEndian: littleEndian))
            var coords: [CLLocationCoordinate2D] = []
            var offset = 9
            for _ in 0..<numPoints {
                guard data.count >= offset + 16 else { break }
                let x = readDouble(data, offset: offset, littleEndian: littleEndian)
                let y = readDouble(data, offset: offset + 8, littleEndian: littleEndian)
                coords.append(CLLocationCoordinate2D(latitude: y, longitude: x))
                offset += 16
            }
            return (.lineString, coords)

        case 3: // Polygon (return exterior ring)
            guard data.count >= 9 else { return nil }
            let numRings = Int(readUInt32(data, offset: 5, littleEndian: littleEndian))
            guard numRings >= 1, data.count >= 13 else { return nil }
            let numPoints = Int(readUInt32(data, offset: 9, littleEndian: littleEndian))
            var coords: [CLLocationCoordinate2D] = []
            var offset = 13
            for _ in 0..<numPoints {
                guard data.count >= offset + 16 else { break }
                let x = readDouble(data, offset: offset, littleEndian: littleEndian)
                let y = readDouble(data, offset: offset + 8, littleEndian: littleEndian)
                coords.append(CLLocationCoordinate2D(latitude: y, longitude: x))
                offset += 16
            }
            return (.polygon, coords)

        default:
            return nil
        }
    }

    private func readUInt32(_ data: Data, offset: Int, littleEndian: Bool) -> UInt32 {
        let bytes = [data[offset], data[offset+1], data[offset+2], data[offset+3]]
        if littleEndian {
            return UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        } else {
            return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        }
    }

    private func readDouble(_ data: Data, offset: Int, littleEndian: Bool) -> Double {
        var bytes = [UInt8](data[offset..<offset+8])
        if !littleEndian { bytes.reverse() }
        return bytes.withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: Double.self, capacity: 1) { $0.pointee }
        }
    }

    deinit {
        if let db = dbPointer { sqlite3_close(db) }
    }
}
