// TerrainEngine.swift — SRTM Elevation Data Parser & Terrain Analysis

import Foundation
import CoreLocation
import MapKit
import Compression

/// SRTM HGT file parser for elevation data
final class TerrainEngine {
    static let shared = TerrainEngine()

    private let fileManager = FileManager.default
    private let srtmDirectory: URL
    private var cachedTiles: [String: TerrainTile] = [:]
    
    /// AWS-hosted Mapzen/Nextzen terrain tiles (free, public, no auth required)
    private let baseURL = "https://elevation-tiles-prod.s3.amazonaws.com/skadi"

    private init() {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        srtmDirectory = paths[0].appendingPathComponent("SRTM", isDirectory: true)
        try? fileManager.createDirectory(at: srtmDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Tile Download (Tesla-style: download once, cache forever)
    
    /// Check if tile exists locally for a coordinate
    func hasTile(for coordinate: CLLocationCoordinate2D) -> Bool {
        let name = tileName(for: coordinate)
        return loadTile(named: name) != nil
    }
    
    /// Get the tile name for a coordinate
    func tileName(for coordinate: CLLocationCoordinate2D) -> String {
        let lat = Int(floor(coordinate.latitude))
        let lon = Int(floor(coordinate.longitude))
        let latPrefix = lat >= 0 ? "N" : "S"
        let lonPrefix = lon >= 0 ? "E" : "W"
        return "\(latPrefix)\(String(format: "%02d", abs(lat)))\(lonPrefix)\(String(format: "%03d", abs(lon)))"
    }
    
    /// Download URL for a tile (gzipped HGT from AWS)
    func downloadURL(for tileName: String) -> URL? {
        // Format: https://elevation-tiles-prod.s3.amazonaws.com/skadi/N29/N29W099.hgt.gz
        let latPart = String(tileName.prefix(3)) // e.g., "N29"
        return URL(string: "\(baseURL)/\(latPart)/\(tileName).hgt.gz")
    }
    
    /// Download and cache a tile (async)
    func downloadTile(named name: String) async throws {
        guard let url = downloadURL(for: name) else {
            throw TerrainError.invalidTileName
        }
        
        
        let (data, response) = try await PinnedURLSession.shared.session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TerrainError.downloadFailed
        }
        
        // Decompress gzip
        let decompressed = try decompressGzip(data)
        
        // Save to SRTM directory
        let destination = srtmDirectory.appendingPathComponent("\(name).hgt")
        try decompressed.write(to: destination)
        
        
        // Clear cache to pick up new tile
        cachedTiles.removeValue(forKey: name)
    }
    
    /// Download tile for a coordinate
    func downloadTile(for coordinate: CLLocationCoordinate2D) async throws {
        let name = tileName(for: coordinate)
        try await downloadTile(named: name)
    }
    
    /// Get all tiles needed for a region
    func tilesNeeded(for region: MKCoordinateRegion) -> [String] {
        let minLat = Int(floor(region.center.latitude - region.span.latitudeDelta / 2))
        let maxLat = Int(floor(region.center.latitude + region.span.latitudeDelta / 2))
        let minLon = Int(floor(region.center.longitude - region.span.longitudeDelta / 2))
        let maxLon = Int(floor(region.center.longitude + region.span.longitudeDelta / 2))
        
        var tiles: [String] = []
        for lat in minLat...maxLat {
            for lon in minLon...maxLon {
                let latPrefix = lat >= 0 ? "N" : "S"
                let lonPrefix = lon >= 0 ? "E" : "W"
                let name = "\(latPrefix)\(String(format: "%02d", abs(lat)))\(lonPrefix)\(String(format: "%03d", abs(lon)))"
                tiles.append(name)
            }
        }
        return tiles
    }
    
    /// Check which tiles are missing for a region
    func missingTiles(for region: MKCoordinateRegion) -> [String] {
        let needed = tilesNeeded(for: region)
        return needed.filter { loadTile(named: $0) == nil }
    }
    
    // MARK: - Gzip Decompression
    
    private func decompressGzip(_ data: Data) throws -> Data {
        // Skip gzip header (10 bytes minimum)
        guard data.count > 10 else { throw TerrainError.invalidData }
        
        // Find the start of deflate data (skip gzip header)
        var headerSize = 10
        let flags = data[3]
        
        // Check for optional fields
        if flags & 0x04 != 0 { // FEXTRA
            let xlen = Int(data[10]) | (Int(data[11]) << 8)
            headerSize += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while headerSize < data.count && data[headerSize] != 0 { headerSize += 1 }
            headerSize += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while headerSize < data.count && data[headerSize] != 0 { headerSize += 1 }
            headerSize += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            headerSize += 2
        }
        
        let compressedData = data.dropFirst(headerSize).dropLast(8) // Drop header and trailer
        
        // Decompress using Compression framework
        let decompressedSize = 3601 * 3601 * 2 // Max SRTM1 size
        var decompressed = Data(count: decompressedSize)
        
        let result = decompressed.withUnsafeMutableBytes { destBuffer in
            compressedData.withUnsafeBytes { srcBuffer in
                compression_decode_buffer(
                    destBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    decompressedSize,
                    srcBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        
        guard result > 0 else { throw TerrainError.decompressionFailed }
        
        return decompressed.prefix(result)
    }
    
    enum TerrainError: Error, LocalizedError {
        case invalidTileName
        case downloadFailed
        case invalidData
        case decompressionFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidTileName: return "Invalid tile name"
            case .downloadFailed: return "Failed to download terrain data"
            case .invalidData: return "Invalid terrain data"
            case .decompressionFailed: return "Failed to decompress terrain data"
            }
        }
    }

    /// Get elevation at a specific coordinate (meters)
    func elevationAt(coordinate: CLLocationCoordinate2D) -> Double? {
        let lat = Int(floor(coordinate.latitude))
        let lon = Int(floor(coordinate.longitude))
        let latPrefix = lat >= 0 ? "N" : "S"
        let lonPrefix = lon >= 0 ? "E" : "W"
        let tileName = "\(latPrefix)\(String(format: "%02d", abs(lat)))\(lonPrefix)\(String(format: "%03d", abs(lon)))"

        guard let tile = loadTile(named: tileName) else { return nil }

        // Bilinear interpolation
        let localLat = coordinate.latitude - Double(lat)
        let localLon = coordinate.longitude - Double(lon)

        let n = tile.samples - 1  // max index (1200 for SRTM3, 3600 for SRTM1)
        let row = Int(localLat * Double(n))
        let col = Int(localLon * Double(n))

        guard row >= 0 && row < n && col >= 0 && col < n else { return nil }

        let s = tile.samples
        let v00 = tile.elevation[row * s + col]
        let v10 = tile.elevation[row * s + (col + 1)]
        let v01 = tile.elevation[(row + 1) * s + col]
        let v11 = tile.elevation[(row + 1) * s + (col + 1)]

        let fracLat = localLat * Double(n) - Double(row)
        let fracLon = localLon * Double(n) - Double(col)

        let v0 = v00 * (1 - fracLon) + v10 * fracLon
        let v1 = v01 * (1 - fracLon) + v11 * fracLon
        return v0 * (1 - fracLat) + v1 * fracLat
    }

    /// Calculate elevation profile along a route
    func elevationProfile(route: [CLLocationCoordinate2D], sampleRate: Int = 10) -> [ElevationPoint] {
        var profile: [ElevationPoint] = []

        for (index, coordinate) in route.enumerated() {
            if index % sampleRate == 0 {
                if let elevation = elevationAt(coordinate: coordinate) {
                    profile.append(ElevationPoint(
                        coordinate: coordinate,
                        elevation: elevation,
                        distance: distanceAlongRoute(route: route, toIndex: index)
                    ))
                }
            }
        }

        return profile
    }

    /// Calculate slope at a coordinate (degrees)
    func slopeAt(coordinate: CLLocationCoordinate2D) -> Double? {
        guard let centerElev = elevationAt(coordinate: coordinate) else { return nil }

        let offset = 0.0001 // ~10 meters
        let northCoord = CLLocationCoordinate2D(latitude: coordinate.latitude + offset, longitude: coordinate.longitude)
        let eastCoord = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude + offset)

        guard let northElev = elevationAt(coordinate: northCoord),
              let eastElev = elevationAt(coordinate: eastCoord) else {
            return nil
        }

        let northDist = coordinate.distance(to: northCoord)
        let eastDist = coordinate.distance(to: eastCoord)

        let northSlope = (northElev - centerElev) / northDist
        let eastSlope = (eastElev - centerElev) / eastDist

        let magnitude = sqrt(northSlope * northSlope + eastSlope * eastSlope)
        let slope = atan(magnitude) * 180 / .pi

        return slope
    }

    /// Get aspect (compass direction of slope) at a coordinate
    func aspectAt(coordinate: CLLocationCoordinate2D) -> Double? {
        guard let centerElev = elevationAt(coordinate: coordinate) else { return nil }

        let offset = 0.0001
        let northCoord = CLLocationCoordinate2D(latitude: coordinate.latitude + offset, longitude: coordinate.longitude)
        let eastCoord = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude + offset)

        guard let northElev = elevationAt(coordinate: northCoord),
              let eastElev = elevationAt(coordinate: eastCoord) else {
            return nil
        }

        let northGrad = northElev - centerElev
        let eastGrad = eastElev - centerElev

        let aspect = atan2(eastGrad, northGrad) * 180 / .pi
        return aspect < 0 ? aspect + 360 : aspect
    }

    // MARK: - Tactical Terrain Analysis

    /// Route difficulty score — 0 (easy) to 10 (extreme)
    /// Based on cumulative slope severity and total elevation gain
    func routeDifficultyScore(route: [CLLocationCoordinate2D]) -> RouteDifficulty {
        guard route.count >= 2 else { return RouteDifficulty(score: 0, elevationGainM: 0, maxSlopeDeg: 0, classification: .easy) }

        var totalGain: Double = 0
        var maxSlope: Double = 0
        var steepSegments = 0
        var prevElev: Double? = nil

        for coord in route {
            guard let elev = elevationAt(coordinate: coord) else { continue }
            if let prev = prevElev {
                let gain = elev - prev
                if gain > 0 { totalGain += gain }
            }
            prevElev = elev
            if let slope = slopeAt(coordinate: coord) {
                maxSlope = max(maxSlope, slope)
                if slope > 20 { steepSegments += 1 }
            }
        }

        // Scoring: 0-10 scale
        let gainScore = min(totalGain / 500.0, 5.0)          // 500m gain = 5 pts
        let slopeScore = min(maxSlope / 45.0 * 4.0, 4.0)    // 45° slope = 4 pts
        let steepScore = min(Double(steepSegments) / 10.0, 1.0) // 10 steep segments = 1 pt
        let score = gainScore + slopeScore + steepScore

        let classification: RouteDifficulty.Classification
        switch score {
        case ..<2: classification = .easy
        case 2..<4: classification = .moderate
        case 4..<6: classification = .difficult
        case 6..<8: classification = .veryDifficult
        default:   classification = .extreme
        }

        return RouteDifficulty(score: score, elevationGainM: totalGain, maxSlopeDeg: maxSlope, classification: classification)
    }

    /// HLZ (Helicopter Landing Zone) feasibility score — 0 (unusable) to 100 (ideal)
    /// Evaluates a circular area around the center for slope, flatness, and approach clearance
    /// - Parameters:
    ///   - center: Center of candidate LZ
    ///   - radiusMeters: LZ radius (default 20m — minimum for most rotary-wing)
    func hlzScore(center: CLLocationCoordinate2D, radiusMeters: Double = 20.0) -> HLZAssessment {
        let earthRadius = 6_371_000.0
        let offsetDeg = radiusMeters / earthRadius * (180.0 / .pi)

        // Sample 8 points around perimeter + center
        let samplePoints: [CLLocationCoordinate2D] = [
            center,
            CLLocationCoordinate2D(latitude: center.latitude + offsetDeg, longitude: center.longitude),
            CLLocationCoordinate2D(latitude: center.latitude - offsetDeg, longitude: center.longitude),
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + offsetDeg),
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude - offsetDeg),
            CLLocationCoordinate2D(latitude: center.latitude + offsetDeg * 0.707, longitude: center.longitude + offsetDeg * 0.707),
            CLLocationCoordinate2D(latitude: center.latitude - offsetDeg * 0.707, longitude: center.longitude - offsetDeg * 0.707),
            CLLocationCoordinate2D(latitude: center.latitude + offsetDeg * 0.707, longitude: center.longitude - offsetDeg * 0.707),
            CLLocationCoordinate2D(latitude: center.latitude - offsetDeg * 0.707, longitude: center.longitude + offsetDeg * 0.707),
        ]

        let slopes = samplePoints.compactMap { slopeAt(coordinate: $0) }
        guard !slopes.isEmpty else {
            return HLZAssessment(score: 0, maxSlopeDeg: 0, elevationRangeM: 0, isFeasible: false, limitingFactor: "No terrain data")
        }

        let maxSlope = slopes.max() ?? 0
        let elevations = samplePoints.compactMap { elevationAt(coordinate: $0) }
        let elevRange = (elevations.max() ?? 0) - (elevations.min() ?? 0)

        // Score: starts at 100, deductions for slope and roughness
        var score = 100.0
        score -= min(maxSlope * 5.0, 50.0)        // -5 pts per degree slope (max -50)
        score -= min(elevRange * 2.0, 30.0)        // -2 pts per meter elevation range
        let avgSlope = slopes.reduce(0, +) / Double(slopes.count)
        score -= min(avgSlope * 2.0, 20.0)         // -2 pts per degree average slope

        let isFeasible = maxSlope < 7.0 && elevRange < 3.0  // FM 3-04.301: <7° slope for HLZ

        let limitingFactor: String?
        if maxSlope >= 15 { limitingFactor = "Slope \(String(format: "%.0f", maxSlope))° — unsafe for any rotary-wing" }
        else if maxSlope >= 7 { limitingFactor = "Slope \(String(format: "%.0f", maxSlope))° — marginal, experienced pilots only" }
        else if elevRange >= 3 { limitingFactor = "Terrain roughness \(String(format: "%.1f", elevRange))m — may damage landing gear" }
        else { limitingFactor = nil }

        return HLZAssessment(score: max(0, score), maxSlopeDeg: maxSlope, elevationRangeM: elevRange, isFeasible: isFeasible, limitingFactor: limitingFactor)
    }

    /// Terrain cover classification for a coordinate
    /// Returns tactical utility classification based on elevation context
    func coverTerrainClassification(at coordinate: CLLocationCoordinate2D) -> TerrainCoverType {
        guard let slope = slopeAt(coordinate: coordinate),
              let elevation = elevationAt(coordinate: coordinate) else { return .unknown }

        // High slope = rocky/cliff — limited movement, good cover
        if slope > 30 { return .rocky }
        // Very flat low elevation could be open field or urban — can't distinguish without OSM
        if slope < 3 && elevation < 500 { return .openGround }
        // Moderate slope at mid elevation = typical woodland/scrub
        if slope < 15 { return .woodland }
        return .rugged
    }

    // MARK: - Import HGT file from disk
    func importHGTFile(at path: URL) throws {
        let filename = path.lastPathComponent
        let destinationPath = srtmDirectory.appendingPathComponent(filename)
        try fileManager.copyItem(at: path, to: destinationPath)
        // Clear cache to reload
        cachedTiles.removeAll()
    }

    // MARK: - Private Helpers
    
    private func loadTileFromPath(_ path: URL, name: String) -> TerrainTile? {
        do {
            let data = try Data(contentsOf: path)
            let tile = try parseHGT(data: data, name: name)
            cachedTiles[name] = tile
            return tile
        } catch {
            return nil
        }
    }

    private func loadTile(named name: String) -> TerrainTile? {
        if let cached = cachedTiles[name] { return cached }

        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let containerRoot = docs.deletingLastPathComponent()
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        
        // App bundle for bundled terrain - check multiple bundle locations
        let bundleSRTM = Bundle.main.bundleURL.appendingPathComponent("SRTM")
        let bundleResources = Bundle.main.resourceURL
        
        // Direct bundle path (most reliable)
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "hgt", inDirectory: "SRTM") {
            if let tile = loadTileFromPath(URL(fileURLWithPath: bundlePath), name: name) {
                return tile
            }
        }
        
        // Also check bundle root
        if let bundlePath = Bundle.main.path(forResource: name, ofType: "hgt") {
            if let tile = loadTileFromPath(URL(fileURLWithPath: bundlePath), name: name) {
                return tile
            }
        }
        
        // Build comprehensive search paths
        var searchDirs: [URL] = [
            // Documents folder variants
            docs.appendingPathComponent("SRTM"),
            docs.appendingPathComponent("Terrain"),
            docs.appendingPathComponent("terrain"),
            docs.appendingPathComponent("HGT"),
            docs,
            
            // Container root (where Finder drops files)
            containerRoot.appendingPathComponent("SRTM"),
            containerRoot.appendingPathComponent("Terrain"),
            containerRoot.appendingPathComponent("terrain"),
            containerRoot,
            
            // App bundle
            bundleSRTM,
        ]
        
        // Add optional paths
        if let resources = bundleResources {
            searchDirs.append(resources.appendingPathComponent("SRTM"))
            searchDirs.append(resources.appendingPathComponent("Terrain"))
            searchDirs.append(resources)
        }
        if let appSupport = appSupportDir {
            searchDirs.append(appSupport.appendingPathComponent("SRTM"))
            searchDirs.append(appSupport.appendingPathComponent("Terrain"))
        }
        if let library = libraryDir {
            searchDirs.append(library.appendingPathComponent("SRTM"))
        }

        
        // First, list what's actually in these directories
        for dir in [docs, containerRoot] {
            if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                let items = contents.map { $0.lastPathComponent }
            }
        }
        
        for dir in searchDirs {
            let path = dir.appendingPathComponent("\(name).hgt")
            let exists = fileManager.fileExists(atPath: path.path)
            if exists {
            }
            
            guard exists else { continue }
            do {
                let data = try Data(contentsOf: path)
                let tile = try parseHGT(data: data, name: name)
                cachedTiles[name] = tile
                return tile
            } catch {
                continue
            }
        }
        
        return nil
    }
    
    /// List all available terrain tiles
    func availableTiles() -> [String] {
        var tiles: [String] = []
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let containerRoot = docs.deletingLastPathComponent()
        
        let searchDirs: [URL] = [
            docs.appendingPathComponent("SRTM"),
            docs.appendingPathComponent("Terrain"),
            docs.appendingPathComponent("terrain"),
            docs.appendingPathComponent("HGT"),
            docs,
            containerRoot.appendingPathComponent("SRTM"),
            containerRoot.appendingPathComponent("Terrain"),
            containerRoot.appendingPathComponent("terrain"),
            containerRoot
        ]
        
        for dir in searchDirs {
            guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let hgtFiles = contents.filter { $0.pathExtension.lowercased() == "hgt" }
            tiles.append(contentsOf: hgtFiles.map { $0.deletingPathExtension().lastPathComponent })
            
            // Also check subdirectories one level deep
            let subdirs = contents.filter { $0.hasDirectoryPath }
            for subdir in subdirs {
                if let subContents = try? fileManager.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil) {
                    let subHgtFiles = subContents.filter { $0.pathExtension.lowercased() == "hgt" }
                    tiles.append(contentsOf: subHgtFiles.map { $0.deletingPathExtension().lastPathComponent })
                }
            }
        }
        
        let uniqueTiles = Array(Set(tiles))
        return uniqueTiles
    }
    
    /// Preload tiles for a region
    func preloadTiles(for region: MKCoordinateRegion) {
        let minLat = Int(floor(region.center.latitude - region.span.latitudeDelta / 2))
        let maxLat = Int(floor(region.center.latitude + region.span.latitudeDelta / 2))
        let minLon = Int(floor(region.center.longitude - region.span.longitudeDelta / 2))
        let maxLon = Int(floor(region.center.longitude + region.span.longitudeDelta / 2))
        
        
        for lat in minLat...maxLat {
            for lon in minLon...maxLon {
                let latPrefix = lat >= 0 ? "N" : "S"
                let lonPrefix = lon >= 0 ? "E" : "W"
                let tileName = "\(latPrefix)\(String(format: "%02d", abs(lat)))\(lonPrefix)\(String(format: "%03d", abs(lon)))"
                _ = loadTile(named: tileName)
            }
        }
    }

    private func parseHGT(data: Data, name: String) throws -> TerrainTile {
        let srtm1Size = 3601 * 3601 * 2  // 25,934,402 bytes
        let srtm3Size = 1201 * 1201 * 2  //  2,884,802 bytes

        let samples: Int
        if data.count == srtm1Size {
            samples = 3601
        } else if data.count == srtm3Size {
            samples = 1201
        } else {
            throw NSError(domain: "TerrainEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid HGT file size: \(data.count) bytes"])
        }

        var elevations: [Double] = []
        elevations.reserveCapacity(samples * samples)
        let bytes = [UInt8](data)

        for i in stride(from: 0, to: bytes.count, by: 2) {
            let high = Int16(bytes[i]) << 8
            let low  = Int16(bytes[i + 1])
            let raw  = high | low
            elevations.append(raw == -32768 ? 0 : Double(raw))
        }

        // Parse lat/lon from name (e.g. "N30W098")
        let latPrefix = String(name.prefix(1))
        let latVal = Int(name.dropFirst().prefix(2)) ?? 0
        let lat = latPrefix == "S" ? -latVal : latVal

        let lonPrefix = String(name.dropFirst(3).prefix(1))
        let lonVal = Int(name.dropFirst(4).prefix(3)) ?? 0
        let lon = lonPrefix == "W" ? -lonVal : lonVal

        return TerrainTile(
            name: name,
            latitude: lat,
            longitude: lon,
            elevation: elevations,
            samples: samples
        )
    }

    private func distanceAlongRoute(route: [CLLocationCoordinate2D], toIndex index: Int) -> Double {
        var distance = 0.0
        for i in 1...index {
            distance += route[i - 1].distance(to: route[i])
        }
        return distance
    }
}

// MARK: - Tactical Terrain Analysis Results

struct RouteDifficulty {
    enum Classification: String {
        case easy         = "Easy"
        case moderate     = "Moderate"
        case difficult    = "Difficult"
        case veryDifficult = "Very Difficult"
        case extreme      = "Extreme"

        var color: String {
            switch self {
            case .easy:         return "successGreen"
            case .moderate:     return "forestGreen"
            case .difficult:    return "safetyYellow"
            case .veryDifficult: return "sunsetOrange"
            case .extreme:      return "signalRed"
            }
        }

        var icon: String {
            switch self {
            case .easy:          return "figure.walk"
            case .moderate:      return "figure.hiking"
            case .difficult:     return "mountain.2.fill"
            case .veryDifficult: return "exclamationmark.triangle.fill"
            case .extreme:       return "xmark.octagon.fill"
            }
        }
    }

    let score: Double         // 0–10
    let elevationGainM: Double
    let maxSlopeDeg: Double
    let classification: Classification

    var summary: String {
        "\(classification.rawValue) — \(String(format: "%.0f", elevationGainM))m gain, max slope \(String(format: "%.0f", maxSlopeDeg))°"
    }
}

struct HLZAssessment {
    let score: Double          // 0–100
    let maxSlopeDeg: Double
    let elevationRangeM: Double
    let isFeasible: Bool
    let limitingFactor: String?

    var scoreDescription: String {
        switch score {
        case 80...:  return "Excellent LZ"
        case 60..<80: return "Good LZ"
        case 40..<60: return "Marginal LZ"
        case 20..<40: return "Poor LZ"
        default:      return "Unusable"
        }
    }
}

enum TerrainCoverType: String {
    case openGround = "Open Ground"
    case woodland   = "Woodland"
    case rocky      = "Rocky/Cliff"
    case rugged     = "Rugged"
    case unknown    = "Unknown"

    var tacticalNotes: String {
        switch self {
        case .openGround: return "Limited cover. Maximize speed, use defilade."
        case .woodland:   return "Good concealment. Noise discipline critical."
        case .rocky:      return "Excellent cover. Slow movement. Channelized approaches."
        case .rugged:     return "Moderate cover. Careful footing required."
        case .unknown:    return "No terrain data available."
        }
    }

    var icon: String {
        switch self {
        case .openGround: return "sun.max.fill"
        case .woodland:   return "tree.fill"
        case .rocky:      return "mountain.2.fill"
        case .rugged:     return "map.fill"
        case .unknown:    return "questionmark.circle"
        }
    }
}

/// Terrain tile containing elevation grid
struct TerrainTile {
    let name: String
    let latitude: Int
    let longitude: Int
    let elevation: [Double]
    let samples: Int  // 1201 (SRTM3) or 3601 (SRTM1)
}

/// Elevation sample along a route
struct ElevationPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
    let distance: Double // meters along route

    var elevationFeet: Double {
        return elevation * 3.28084
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    /// Calculate distance between two coordinates using Haversine formula
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let lat1 = self.latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - self.latitude) * .pi / 180
        let deltaLon = (other.longitude - self.longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return 6371000 * c // Earth radius in meters
    }
}
