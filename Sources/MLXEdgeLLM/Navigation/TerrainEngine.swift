// TerrainEngine.swift — SRTM Elevation Data Parser & Terrain Analysis

import Foundation
import CoreLocation

/// SRTM HGT file parser for elevation data
final class TerrainEngine {
    static let shared = TerrainEngine()

    private let fileManager = FileManager.default
    private let srtmDirectory: URL
    private var cachedTiles: [String: TerrainTile] = [:]

    private init() {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        srtmDirectory = paths[0].appendingPathComponent("SRTM", isDirectory: true)
        try? fileManager.createDirectory(at: srtmDirectory, withIntermediateDirectories: true)
    }

    /// Get elevation at a specific coordinate (meters)
    func elevationAt(coordinate: CLLocationCoordinate2D) -> Double? {
        let lat = Int(floor(coordinate.latitude))
        let lon = Int(floor(coordinate.longitude))
        let tileName = "N\(String(format: "%02d", lat))W\(String(format: "%03d", abs(lon)))"

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

    /// Import HGT file from disk
    func importHGTFile(at path: URL) throws {
        let filename = path.lastPathComponent
        let destinationPath = srtmDirectory.appendingPathComponent(filename)
        try fileManager.copyItem(at: path, to: destinationPath)
        // Clear cache to reload
        cachedTiles.removeAll()
    }

    // MARK: - Private Helpers

    private func loadTile(named name: String) -> TerrainTile? {
        if let cached = cachedTiles[name] {
            return cached
        }

        let path = srtmDirectory.appendingPathComponent("\(name).hgt")
        guard fileManager.fileExists(atPath: path.path) else { return nil }

        do {
            let data = try Data(contentsOf: path)
            let tile = try parseHGT(data: data, name: name)
            cachedTiles[name] = tile
            return tile
        } catch {
            return nil
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
