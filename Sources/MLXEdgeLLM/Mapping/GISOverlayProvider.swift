// GISOverlayProvider.swift — Bridges KmlHandler and ShapefileHandler to SwiftUI Map
// Converts KML/Shapefile geometries into map-renderable overlay data

import Foundation
import CoreLocation
import SwiftUI
import MapKit

// MARK: - GIS Map Overlay

enum GISMapOverlay: Identifiable {
    case polygon(id: UUID, name: String, coordinates: [CLLocationCoordinate2D], color: Color)
    case polyline(id: UUID, name: String, coordinates: [CLLocationCoordinate2D], color: Color)
    case point(id: UUID, name: String, coordinate: CLLocationCoordinate2D)

    var id: UUID {
        switch self {
        case .polygon(let id, _, _, _): return id
        case .polyline(let id, _, _, _): return id
        case .point(let id, _, _): return id
        }
    }
}

// MARK: - GIS Overlay Provider

@MainActor
final class GISOverlayProvider: ObservableObject {
    static let shared = GISOverlayProvider()

    @Published var overlays: [GISMapOverlay] = []
    @Published var loadedFiles: [String] = []

    private init() {}

    // MARK: - Load KML

    func loadKML(from url: URL) async {
        let handler = KmlHandler()
        do {
            try await handler.readKml(from: url)
        } catch {
            print("[GISOverlayProvider] Failed to load KML: \(error)")
            return
        }

        // Convert polygons
        for polygon in handler.polygons {
            overlays.append(.polygon(
                id: UUID(),
                name: polygon.name,
                coordinates: polygon.coordinates,
                color: .blue.opacity(0.3)
            ))
        }

        // Convert paths
        for path in handler.paths {
            overlays.append(.polyline(
                id: UUID(),
                name: path.name,
                coordinates: path.coordinates,
                color: .orange
            ))
        }

        // Convert placemarks
        for placemark in handler.placemarks {
            overlays.append(.point(
                id: UUID(),
                name: placemark.name,
                coordinate: placemark.coordinates
            ))
        }

        loadedFiles.append(url.lastPathComponent)
    }

    // MARK: - Load Shapefile

    func loadShapefile(shp: URL, dbf: URL, prj: URL) {
        let handler = ShapefileHandler(shapefilePath: shp, dbfFilePath: dbf, prjFilePath: prj)
        guard let features = try? handler.readShapefile() else { return }

        for feature in features {
            let name = (feature.attributes["NAME"] as? String) ?? "Feature"

            switch feature.geometry {
            case .polygon(let coords):
                overlays.append(.polygon(
                    id: UUID(),
                    name: name,
                    coordinates: coords,
                    color: .green.opacity(0.3)
                ))
            case .line(let coords):
                overlays.append(.polyline(
                    id: UUID(),
                    name: name,
                    coordinates: coords,
                    color: .yellow
                ))
            case .point(let coord):
                overlays.append(.point(
                    id: UUID(),
                    name: name,
                    coordinate: coord
                ))
            }
        }

        loadedFiles.append(shp.lastPathComponent)
    }

    // MARK: - Scan Documents for GIS files

    func scanForGISFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }

        for file in files {
            let ext = file.pathExtension.lowercased()
            if ext == "kml" || ext == "kmz" {
                if !loadedFiles.contains(file.lastPathComponent) {
                    Task { await loadKML(from: file) }
                }
            }
        }
    }

    func clear() {
        overlays = []
        loadedFiles = []
    }
}
