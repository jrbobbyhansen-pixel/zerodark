// MilitaryGridOverlay.swift — MGRS grid overlay rendered via CoreGraphics
// Draws grid lines + labels on MKTileOverlay tiles at appropriate zoom levels
// No external dependencies — uses MGRSConverter from Navigation/

import MapKit
import CoreLocation
import UIKit

// MARK: - Grid Type Selection

enum MilitaryGridType: String, CaseIterable {
    case none = "None"
    case mgrs = "MGRS"
}

// MARK: - MGRS Grid Tile Overlay

final class MGRSGridTileOverlay: MKTileOverlay {

    override init(urlTemplate: String? = nil) {
        super.init(urlTemplate: urlTemplate)
        self.canReplaceMapContent = false
        self.tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        // Compute the geographic bounds of this tile
        let n = pow(2.0, Double(path.z))
        let lonLeft = Double(path.x) / n * 360.0 - 180.0
        let lonRight = Double(path.x + 1) / n * 360.0 - 180.0
        let latTop = atan(sinh(.pi * (1 - 2 * Double(path.y) / n))) * 180.0 / .pi
        let latBottom = atan(sinh(.pi * (1 - 2 * Double(path.y + 1) / n))) * 180.0 / .pi

        // Determine grid spacing based on zoom level
        let gridSpacingDeg: Double
        let gridLabel: String
        if path.z >= 14 {
            gridSpacingDeg = 0.01   // ~1km at mid-latitudes
            gridLabel = "1km"
        } else if path.z >= 11 {
            gridSpacingDeg = 0.1    // ~10km
            gridLabel = "10km"
        } else if path.z >= 7 {
            gridSpacingDeg = 1.0    // ~100km (1° grid)
            gridLabel = "100km"
        } else {
            // Too zoomed out for useful grid
            result(nil, nil)
            return
        }

        // Render grid tile
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        let image = renderer.pngData { ctx in
            let gc = ctx.cgContext
            let tileWidth = 256.0
            let tileHeight = 256.0

            // Grid line style
            gc.setStrokeColor(UIColor(red: 0, green: 0.8, blue: 0.8, alpha: 0.6).cgColor)
            gc.setLineWidth(path.z >= 14 ? 1.0 : 0.5)

            // Draw vertical grid lines (constant longitude)
            let startLon = (lonLeft / gridSpacingDeg).rounded(.down) * gridSpacingDeg
            var lon = startLon
            while lon <= lonRight + gridSpacingDeg {
                let x = (lon - lonLeft) / (lonRight - lonLeft) * tileWidth
                if x >= -1 && x <= tileWidth + 1 {
                    gc.move(to: CGPoint(x: x, y: 0))
                    gc.addLine(to: CGPoint(x: x, y: tileHeight))
                }
                lon += gridSpacingDeg
            }
            gc.strokePath()

            // Draw horizontal grid lines (constant latitude)
            let startLat = (latBottom / gridSpacingDeg).rounded(.down) * gridSpacingDeg
            var lat = startLat
            while lat <= latTop + gridSpacingDeg {
                let y = (latTop - lat) / (latTop - latBottom) * tileHeight
                if y >= -1 && y <= tileHeight + 1 {
                    gc.move(to: CGPoint(x: 0, y: y))
                    gc.addLine(to: CGPoint(x: tileWidth, y: y))
                }
                lat += gridSpacingDeg
            }
            gc.strokePath()

            // Draw MGRS labels at grid intersections (only at high zoom)
            if path.z >= 11 {
                let font = UIFont.systemFont(ofSize: path.z >= 14 ? 9 : 7, weight: .medium)
                let textColor = UIColor(red: 0, green: 0.9, blue: 0.9, alpha: 0.8)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

                lat = startLat + gridSpacingDeg
                while lat <= latTop {
                    lon = startLon + gridSpacingDeg
                    while lon <= lonRight {
                        let x = (lon - lonLeft) / (lonRight - lonLeft) * tileWidth
                        let y = (latTop - lat) / (latTop - latBottom) * tileHeight

                        if x > 5 && x < tileWidth - 40 && y > 5 && y < tileHeight - 15 {
                            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            let mgrs = MGRSConverter.toMGRS(coordinate: coord, precision: path.z >= 14 ? 4 : 3)
                            // Show condensed: last parts only (e.g., "PU 1234 5678")
                            let condensed = condenseMGRS(mgrs)
                            let nsStr = condensed as NSString
                            nsStr.draw(at: CGPoint(x: x + 3, y: y + 2), withAttributes: attrs)
                        }
                        lon += gridSpacingDeg
                    }
                    lat += gridSpacingDeg
                }
            }
        }

        result(image, nil)
    }

    private func condenseMGRS(_ mgrs: String) -> String {
        // Full MGRS: "14RPU1234567890" → show "PU 12345 67890" (drop zone+band)
        let cleaned = mgrs.replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 5 else { return mgrs }

        // Find where letters start after zone digits
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex && cleaned[idx].isNumber { idx = cleaned.index(after: idx) }
        guard idx < cleaned.endIndex else { return mgrs }
        idx = cleaned.index(after: idx) // Skip band letter

        let remaining = String(cleaned[idx...])
        guard remaining.count >= 2 else { return mgrs }

        let squareID = String(remaining.prefix(2))
        let digits = String(remaining.dropFirst(2))
        if digits.count >= 2 {
            let half = digits.count / 2
            return "\(squareID) \(digits.prefix(half)) \(digits.suffix(half))"
        }
        return "\(squareID) \(digits)"
    }
}

// MARK: - NGA Coordinate Helpers

struct NGACoordinates {
    static func toMGRS(_ coordinate: CLLocationCoordinate2D, precision: Int = 5) -> String {
        MGRSConverter.toMGRS(coordinate: coordinate, precision: precision)
    }

    static func fromMGRS(_ mgrsString: String) -> CLLocationCoordinate2D? {
        MGRSConverter.parseMGRS(mgrsString)
    }
}
