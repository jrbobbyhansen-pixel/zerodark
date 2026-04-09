// MilitaryGridOverlay.swift – MGRS and GARS grid overlays using NGA libraries

import MapKit
import CoreLocation

// MARK: - Grid Type Selection

enum MilitaryGridType: String, CaseIterable {
    case none = "None"
    case mgrs = "MGRS"
    case gars = "GARS"
}

// MARK: - MGRS Grid Tile Overlay (Placeholder for NGA mgrs-ios)

final class MGRSGridTileOverlay: NSObject {
    public var canReplaceMapContent: Bool = false

    public init(urlTemplate: String = "") {
        super.init()
    }

    func url(forTilePath path: MKTileOverlayPath) -> URL {
        // Placeholder: in production, uses mgrs-ios library to generate tiles
        // MGRSTiles.drawTile(grids: ..., tile: ...) → UIImage → PNG
        return URL(fileURLWithPath: "mgrs_tile_\(path.z)_\(path.x)_\(path.y).png")
    }
}

// MARK: - GARS Grid Tile Overlay (Placeholder for NGA gars-ios)

final class GARSGridTileOverlay: NSObject {
    public var canReplaceMapContent: Bool = false

    public init(urlTemplate: String = "") {
        super.init()
    }

    func url(forTilePath path: MKTileOverlayPath) -> URL {
        // Placeholder: in production, uses gars-ios library
        return URL(fileURLWithPath: "gars_tile_\(path.z)_\(path.x)_\(path.y).png")
    }
}

// MARK: - NGA Coordinate Helpers

struct NGACoordinates {

    /// Convert coordinate to MGRS string (placeholder – uses MGRSConverter for now)
    static func toMGRS(_ coordinate: CLLocationCoordinate2D, precision: Int = 5) -> String {
        return MGRSConverter.toMGRS(coordinate: coordinate, precision: precision)
    }

    /// Convert coordinate to GARS string (placeholder)
    static func toGARS(_ coordinate: CLLocationCoordinate2D) -> String {
        // In production: GARS.from(GARSPoint(...)).coordinate()
        return "GARS placeholder"
    }

    /// Parse MGRS string to coordinate (placeholder)
    static func fromMGRS(_ mgrsString: String) -> CLLocationCoordinate2D? {
        // In production: MGRS.parse(...).toPoint()
        return nil
    }

    /// Parse GARS string to coordinate (placeholder)
    static func fromGARS(_ garsString: String) -> CLLocationCoordinate2D? {
        // In production: GARS.parse(...).toPoint()
        return nil
    }
}
