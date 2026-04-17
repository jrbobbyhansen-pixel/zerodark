// ContourGeneratorEngine.swift — Contour line generation from LiDAR or SRTM
// Bridges point cloud → DEM → marching squares → geo-coordinates → ContourOverlay
// Exports as GeoJSON for offline map use

import Foundation
import MapKit
import CoreLocation

// MARK: - Contour Source

enum ContourSource {
    /// LiDAR point cloud with GPS scan origin
    case lidar(pointCloud: [SIMD3<Float>], origin: CLLocationCoordinate2D, cellSize: Float = 0.5)
    /// SRTM tile data around a coordinate
    case srtm(center: CLLocationCoordinate2D, radiusKm: Double = 2.0, resolution: Int = 50)
}

// MARK: - ContourGeneratorEngine

final class ContourGeneratorEngine {
    static let shared = ContourGeneratorEngine()
    private init() {}

    // MARK: - Public API

    /// Generate a ContourOverlay from either a LiDAR scan or SRTM terrain data.
    /// Returns nil if the source has too few points or no elevation data.
    func generate(
        source: ContourSource,
        interval: Double
    ) async -> ContourOverlay? {
        switch source {
        case let .lidar(pointCloud, origin, cellSize):
            return await generateFromLiDAR(
                pointCloud: pointCloud,
                origin: origin,
                cellSize: cellSize,
                interval: interval
            )
        case let .srtm(center, radiusKm, resolution):
            return await generateFromSRTM(
                center: center,
                radiusKm: radiusKm,
                resolution: resolution,
                interval: interval
            )
        }
    }

    /// Export a ContourOverlay as GeoJSON FeatureCollection.
    /// Each contour line → LineString feature with "elevation" and "isMajor" properties.
    func exportGeoJSON(_ overlay: ContourOverlay) -> Data? {
        var features: [[String: Any]] = []

        for line in overlay.contourLines {
            guard line.points.count >= 2 else { continue }

            let coordinates = line.points.map { [$0.lon, $0.lat] }
            let geometry: [String: Any] = [
                "type": "LineString",
                "coordinates": coordinates
            ]
            let feature: [String: Any] = [
                "type": "Feature",
                "geometry": geometry,
                "properties": [
                    "elevation": line.elevation,
                    "elevationFeet": line.elevationFeet,
                    "isMajor": line.isMajor
                ]
            ]
            features.append(feature)
        }

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]

        return try? JSONSerialization.data(withJSONObject: collection, options: .prettyPrinted)
    }

    /// Save GeoJSON export to the Documents directory.
    /// Returns the file URL on success.
    func saveGeoJSON(_ overlay: ContourOverlay, filename: String? = nil) -> URL? {
        guard let data = exportGeoJSON(overlay) else { return nil }
        let name = filename ?? "contours-\(Int(Date().timeIntervalSince1970)).geojson"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - LiDAR Path

    private func generateFromLiDAR(
        pointCloud: [SIMD3<Float>],
        origin: CLLocationCoordinate2D,
        cellSize: Float,
        interval: Double
    ) async -> ContourOverlay? {
        guard pointCloud.count > 100 else { return nil }

        return await Task.detached(priority: .userInitiated) { [weak self] () -> ContourOverlay? in
            guard let self else { return nil }

            // 1. Build DEM grid (XZ plane, Y = elevation)
            let xs = pointCloud.map { $0.x }
            let zs = pointCloud.map { $0.z }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minZ = zs.min(), let maxZ = zs.max() else { return nil }

            let cols = max(3, Int(ceil((maxX - minX) / cellSize)) + 1)
            let rows = max(3, Int(ceil((maxZ - minZ) / cellSize)) + 1)

            var rawGrid = Array(repeating: Array(repeating: Double.nan, count: cols), count: rows)
            for p in pointCloud {
                let c = Int((p.x - minX) / cellSize)
                let r = Int((p.z - minZ) / cellSize)
                guard r >= 0, r < rows, c >= 0, c < cols else { continue }
                let y = Double(p.y)
                if rawGrid[r][c].isNaN || y > rawGrid[r][c] {
                    rawGrid[r][c] = y
                }
            }
            self.fillHoles(grid: &rawGrid, rows: rows, cols: cols)

            // 2. Run marching squares via ContourExtraction
            let dem = DigitalElevationModel(grid: rawGrid, cellSize: Double(cellSize))
            let contours = ContourExtraction(dem: dem, interval: interval).extractContours()
            guard !contours.isEmpty else { return nil }

            // 3. Convert grid (col, row) → geo coordinates
            // ARKit convention: +X = east, +Z = south (toward initial scene depth)
            // col * cellSize = east meters from minX in ARKit space
            // row * cellSize = south meters from minZ in ARKit space
            // ARKit origin ≈ user GPS location when session started (origin param)
            let metersPerDegLat = 111_320.0
            let metersPerDegLon = 111_320.0 * cos(origin.latitude * .pi / 180)

            var contourLines: [ContourLine] = []
            for contour in contours {
                var geoPoints: [(lat: Double, lon: Double)] = []
                for pt in contour.points {
                    // pt.x = col (east direction), pt.y = row (south direction)
                    let eastMeters  = Double(minX) + pt.x * Double(cellSize)
                    let southMeters = Double(minZ) + pt.y * Double(cellSize)
                    let lat = origin.latitude  + (-southMeters) / metersPerDegLat
                    let lon = origin.longitude + eastMeters     / metersPerDegLon
                    geoPoints.append((lat: lat, lon: lon))
                }
                guard geoPoints.count >= 2 else { continue }

                let isMajor = interval > 0
                    ? Int(contour.elevation / interval) % 5 == 0
                    : false

                contourLines.append(ContourLine(
                    elevation: contour.elevation,
                    points: geoPoints,
                    isMajor: isMajor
                ))
            }

            guard !contourLines.isEmpty else { return nil }

            // 4. Build a ContourOverlay covering the scanned bounding region
            let latDelta = (Double(rows) * Double(cellSize)) / metersPerDegLat * 2
            let lonDelta = (Double(cols) * Double(cellSize)) / metersPerDegLon * 2
            let region = MKCoordinateRegion(
                center: origin,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
            let overlay = ContourOverlay(region: region, contourInterval: interval)
            overlay.load(contourLines)
            return overlay
        }.value
    }

    // MARK: - SRTM Path

    private func generateFromSRTM(
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        resolution: Int,
        interval: Double
    ) async -> ContourOverlay? {
        let degrees = radiusKm / 111.32
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: degrees * 2, longitudeDelta: degrees * 2)
        )
        let overlay = ContourOverlay(region: region, contourInterval: interval)
        await Task.detached(priority: .userInitiated) {
            overlay.generateContours(resolution: resolution)
        }.value
        guard !overlay.contourLines.isEmpty else { return nil }
        return overlay
    }

    // MARK: - DEM Helpers

    private func fillHoles(grid: inout [[Double]], rows: Int, cols: Int) {
        var changed = true
        var pass = 0
        while changed && pass < 10 {
            changed = false
            pass += 1
            for r in 0..<rows {
                for c in 0..<cols {
                    guard grid[r][c].isNaN else { continue }
                    let neighbors = [
                        r > 0      ? grid[r-1][c] : Double.nan,
                        r < rows-1 ? grid[r+1][c] : Double.nan,
                        c > 0      ? grid[r][c-1] : Double.nan,
                        c < cols-1 ? grid[r][c+1] : Double.nan
                    ].filter { !$0.isNaN }
                    if let avg = neighbors.isEmpty ? nil : neighbors.reduce(0, +) / Double(neighbors.count) {
                        grid[r][c] = avg
                        changed = true
                    }
                }
            }
        }
        // Remaining NaN → 0
        for r in 0..<rows {
            for c in 0..<cols {
                if grid[r][c].isNaN { grid[r][c] = 0 }
            }
        }
    }
}
