// MilitaryGridOverlay.swift — MGRS and GARS grid overlays.
//
// Previously the tile overlays returned dummy file:// URLs and toGARS /
// fromGARS / fromMGRS all returned "placeholder" strings or nil. Now both
// tile overlays are real MKTileOverlay subclasses that render grid lines on
// the fly as PNG tiles from the tile's geographic bounds. GARS conversion is
// a straightforward implementation of the 30-arcmin cell scheme (with 15-min
// quadrants and 5-min keypads). fromMGRS delegates to the existing
// MGRSConverter.parseMGRS extension landed in spec 013's WaypointManager.

import MapKit
import UIKit
import CoreLocation

// MARK: - Grid Type Selection

enum MilitaryGridType: String, CaseIterable {
    case none = "None"
    case mgrs = "MGRS"
    case gars = "GARS"
}

// MARK: - Tile rendering base

/// Shared drawing utilities for grid-line tiles.
private enum GridTileRenderer {
    static func tileImage(
        size: CGSize,
        bounds: MKMapRect,
        zoom: Int,
        drawLines: (CGContext, MKMapRect, CGSize) -> Void
    ) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage() }

        // Transparent tile; just draw strokes.
        ctx.clear(CGRect(origin: .zero, size: size))

        // Antialias strokes for readability over satellite / vector basemaps.
        ctx.setLineCap(.round)
        ctx.setShouldAntialias(true)

        drawLines(ctx, bounds, size)
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    /// Map a lat/lon to a point inside a tile given the tile's map rect + image size.
    static func point(
        for coordinate: CLLocationCoordinate2D,
        in rect: MKMapRect,
        imageSize: CGSize
    ) -> CGPoint {
        let point = MKMapPoint(coordinate)
        let x = (point.x - rect.origin.x) / rect.size.width * imageSize.width
        let y = (point.y - rect.origin.y) / rect.size.height * imageSize.height
        return CGPoint(x: x, y: y)
    }
}

// MARK: - MGRS Grid Tile Overlay

final class MGRSGridTileOverlay: MKTileOverlay {
    /// Drawing color for grid lines.
    var gridColor: UIColor = UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.75)
    /// Label color for zone IDs.
    var labelColor: UIColor = UIColor.white.withAlphaComponent(0.9)

    override init(urlTemplate URLTemplate: String?) {
        super.init(urlTemplate: URLTemplate)
        self.canReplaceMapContent = false
        self.minimumZ = 4
        self.maximumZ = 17
    }

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, (any Error)?) -> Void) {
        let image = render(path: path)
        guard let data = image.pngData() else {
            result(nil, nil); return
        }
        result(data, nil)
    }

    private func render(path: MKTileOverlayPath) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let rect = tileMapRect(x: path.x, y: path.y, z: path.z)

        return GridTileRenderer.tileImage(size: size, bounds: rect, zoom: path.z) { ctx, bounds, imageSize in
            ctx.setStrokeColor(self.gridColor.cgColor)

            // Line density depends on zoom. Use UTM 100km grid at low zoom,
            // degrade to 10km / 1km as zoom increases. Below z4 skip entirely.
            let stepMeters: Double = {
                switch path.z {
                case ..<6: return 100_000  // 100 km
                case ..<9: return 10_000   // 10 km
                case ..<12: return 1_000   // 1 km
                default:    return 100     // 100 m
                }
            }()

            ctx.setLineWidth(path.z < 9 ? 0.7 : 0.5)

            // Convert the tile's MKMapRect into lat/lon bounds.
            let sw = MKMapPoint(x: bounds.origin.x, y: bounds.origin.y + bounds.size.height).coordinate
            let ne = MKMapPoint(x: bounds.origin.x + bounds.size.width, y: bounds.origin.y).coordinate

            // Degrees per step, rough conversion using midpoint latitude.
            let midLat = (sw.latitude + ne.latitude) / 2
            let mPerDegLat = 111_320.0
            let mPerDegLon = 111_320.0 * cos(midLat * .pi / 180)
            let stepDegLat = stepMeters / mPerDegLat
            let stepDegLon = stepMeters / mPerDegLon

            // Latitude lines (horizontal)
            var lat = ceil(sw.latitude / stepDegLat) * stepDegLat
            while lat <= ne.latitude {
                let p1 = GridTileRenderer.point(
                    for: CLLocationCoordinate2D(latitude: lat, longitude: sw.longitude),
                    in: bounds, imageSize: imageSize)
                let p2 = GridTileRenderer.point(
                    for: CLLocationCoordinate2D(latitude: lat, longitude: ne.longitude),
                    in: bounds, imageSize: imageSize)
                ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
                lat += stepDegLat
            }

            // Longitude lines (vertical)
            var lon = ceil(sw.longitude / stepDegLon) * stepDegLon
            while lon <= ne.longitude {
                let p1 = GridTileRenderer.point(
                    for: CLLocationCoordinate2D(latitude: sw.latitude, longitude: lon),
                    in: bounds, imageSize: imageSize)
                let p2 = GridTileRenderer.point(
                    for: CLLocationCoordinate2D(latitude: ne.latitude, longitude: lon),
                    in: bounds, imageSize: imageSize)
                ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
                lon += stepDegLon
            }

            // Corner label at low zoom: MGRS string of the tile SW corner.
            if path.z <= 10 {
                let label = MGRSConverter.toMGRS(coordinate: sw, precision: 0) as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: self.labelColor
                ]
                label.draw(at: CGPoint(x: 4, y: imageSize.height - 14), withAttributes: attrs)
            }
        }
    }

    /// MKMapRect bounding box for an XYZ tile at zoom Z (web-mercator standard).
    private func tileMapRect(x: Int, y: Int, z: Int) -> MKMapRect {
        let n = Double(1 << z)
        let width = MKMapSize.world.width / n
        let height = MKMapSize.world.height / n
        return MKMapRect(x: Double(x) * width, y: Double(y) * height, width: width, height: height)
    }
}

// MARK: - GARS Grid Tile Overlay

final class GARSGridTileOverlay: MKTileOverlay {
    var gridColor: UIColor = UIColor(red: 1.0, green: 0.843, blue: 0.0, alpha: 0.75)

    override init(urlTemplate URLTemplate: String?) {
        super.init(urlTemplate: URLTemplate)
        self.canReplaceMapContent = false
        self.minimumZ = 3
        self.maximumZ = 14
    }

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, (any Error)?) -> Void) {
        let size = CGSize(width: 256, height: 256)
        let rect = tileMapRect(x: path.x, y: path.y, z: path.z)

        let image = GridTileRenderer.tileImage(size: size, bounds: rect, zoom: path.z) { ctx, bounds, imageSize in
            ctx.setStrokeColor(self.gridColor.cgColor)
            ctx.setLineWidth(0.6)

            // GARS primary cells = 30-arcmin. Subdivide to 15 min at z≥8 and
            // 5 min at z≥12.
            let stepDeg: Double = {
                switch path.z {
                case ..<8:  return 0.5          // 30 min
                case ..<12: return 0.25         // 15 min
                default:    return 5.0 / 60.0   // 5 min
                }
            }()

            let sw = MKMapPoint(x: bounds.origin.x, y: bounds.origin.y + bounds.size.height).coordinate
            let ne = MKMapPoint(x: bounds.origin.x + bounds.size.width, y: bounds.origin.y).coordinate

            var lat = (floor(sw.latitude / stepDeg) + 1) * stepDeg
            while lat <= ne.latitude {
                let p1 = GridTileRenderer.point(for: .init(latitude: lat, longitude: sw.longitude),
                                                 in: bounds, imageSize: imageSize)
                let p2 = GridTileRenderer.point(for: .init(latitude: lat, longitude: ne.longitude),
                                                 in: bounds, imageSize: imageSize)
                ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
                lat += stepDeg
            }

            var lon = (floor(sw.longitude / stepDeg) + 1) * stepDeg
            while lon <= ne.longitude {
                let p1 = GridTileRenderer.point(for: .init(latitude: sw.latitude, longitude: lon),
                                                 in: bounds, imageSize: imageSize)
                let p2 = GridTileRenderer.point(for: .init(latitude: ne.latitude, longitude: lon),
                                                 in: bounds, imageSize: imageSize)
                ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
                lon += stepDeg
            }
        }

        if let data = image.pngData() { result(data, nil) } else { result(nil, nil) }
    }

    private func tileMapRect(x: Int, y: Int, z: Int) -> MKMapRect {
        let n = Double(1 << z)
        let width = MKMapSize.world.width / n
        let height = MKMapSize.world.height / n
        return MKMapRect(x: Double(x) * width, y: Double(y) * height, width: width, height: height)
    }
}

// MARK: - NGA Coordinate Helpers

enum NGACoordinates {

    /// Convert coordinate → MGRS (delegates to existing MGRSConverter).
    static func toMGRS(_ coordinate: CLLocationCoordinate2D, precision: Int = 5) -> String {
        MGRSConverter.toMGRS(coordinate: coordinate, precision: precision)
    }

    /// Convert coordinate → GARS string per DoD GARS spec:
    ///   - Longitude band: 001–720 (each 30 min, starting at 180°W)
    ///   - Latitude band:  AA–QZ (each 30 min, starting at 90°S, skipping I and O)
    ///   - 15-min quadrant: 1 NW, 2 NE, 3 SW, 4 SE (within the 30-min cell)
    ///   - 5-min keypad: 1–9 (within the 15-min quadrant)
    /// Example: "006KC34" at zoom-out precision (30 min),
    ///          "006KC3" adds 15-min quadrant,
    ///          "006KC34" adds 5-min keypad.
    static func toGARS(_ coordinate: CLLocationCoordinate2D, precision: Precision = .fiveMin) -> String {
        let lon = coordinate.longitude
        let lat = coordinate.latitude

        // Clamp bounds to valid GARS range
        guard (-90.0..<90.0).contains(lat), (-180.0..<180.0).contains(lon) else { return "INVALID" }

        // 30-min cells
        let lonIdx = Int(floor((lon + 180) * 2)) + 1     // 1…720
        let latIdx = Int(floor((lat + 90) * 2))           // 0…359

        // Latitude letters: 24 letters × 15 pairs = 360 cells. Skip I and O.
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
        let firstIdx = latIdx / 24
        let secondIdx = latIdx % 24
        guard firstIdx < letters.count, secondIdx < letters.count else { return "INVALID" }
        let first = letters[letters.index(letters.startIndex, offsetBy: firstIdx)]
        let second = letters[letters.index(letters.startIndex, offsetBy: secondIdx)]

        let band30 = String(format: "%03d%@%@", lonIdx, String(first), String(second))
        if precision == .thirtyMin { return band30 }

        // 15-min quadrant within the 30-min cell.
        let lonIn30 = (lon + 180) * 2 - Double(lonIdx - 1)   // 0..1
        let latIn30 = (lat + 90) * 2 - Double(latIdx)        // 0..1
        let west  = lonIn30 < 0.5
        let north = latIn30 >= 0.5
        let quadrant: Int = west && north ? 1 : (!west && north ? 2 : (west && !north ? 3 : 4))
        let band15 = band30 + String(quadrant)
        if precision == .fifteenMin { return band15 }

        // 5-min keypad within the 15-min quadrant (3×3 grid, rows top-to-bottom).
        let lonIn15 = (lonIn30 - (west ? 0 : 0.5)) * 2    // 0..1
        let latIn15 = (latIn30 - (north ? 0.5 : 0)) * 2   // 0..1
        let col = min(2, Int(lonIn15 * 3))
        let row = 2 - min(2, Int(latIn15 * 3))
        let keypad = row * 3 + col + 1
        return band15 + String(keypad)
    }

    /// Parse MGRS string → coordinate (delegates to parseMGRS extension).
    static func fromMGRS(_ mgrs: String) -> CLLocationCoordinate2D? {
        MGRSConverter.parseMGRS(mgrs)
    }

    /// Parse GARS string (any precision) → coordinate at the cell centroid.
    static func fromGARS(_ g: String) -> CLLocationCoordinate2D? {
        let s = g.uppercased().replacingOccurrences(of: " ", with: "")
        // Minimum "NNNLL" = 5 chars; full "NNNLLQK" = 7 chars.
        guard s.count >= 5 else { return nil }
        guard let lonIdx = Int(s.prefix(3)) else { return nil }
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let idx5 = s.index(s.startIndex, offsetBy: 3)
        let idx6 = s.index(s.startIndex, offsetBy: 4)
        guard let firstIdx = letters.firstIndex(of: s[idx5]),
              let secondIdx = letters.firstIndex(of: s[idx6]) else { return nil }
        let latIdx = firstIdx * 24 + secondIdx

        // 30-min cell centroid
        var lonCentre = (Double(lonIdx - 1) / 2) - 180 + 0.25
        var latCentre = (Double(latIdx) / 2) - 90 + 0.25

        // Optional 15-min quadrant
        if s.count >= 6, let q = Int(String(s[s.index(s.startIndex, offsetBy: 5)])) {
            let west  = (q == 1 || q == 3)
            let north = (q == 1 || q == 2)
            lonCentre += (west  ? -0.125 : 0.125)
            latCentre += (north ?  0.125 : -0.125)
        }

        // Optional 5-min keypad (1..9, row top-to-bottom)
        if s.count >= 7, let k = Int(String(s[s.index(s.startIndex, offsetBy: 6)])), (1...9).contains(k) {
            let col = (k - 1) % 3
            let row = (k - 1) / 3
            let cellSize = 0.25 / 3    // 5 min = 1/12 deg
            lonCentre += Double(col - 1) * cellSize
            latCentre -= Double(row - 1) * cellSize
        }

        return CLLocationCoordinate2D(latitude: latCentre, longitude: lonCentre)
    }

    enum Precision { case thirtyMin, fifteenMin, fiveMin }
}
