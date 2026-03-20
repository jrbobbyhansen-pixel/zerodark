// GeoPackageService.swift — GeoPackage import service (placeholder for NGA geopackage-ios)

import Foundation
import CoreLocation
import Observation

// MARK: - GeoPackage Feature Model

struct GPKGFeature: Identifiable, Sendable {
    let id: String
    let name: String
    let geometryType: GeometryType
    let coordinates: [CLLocationCoordinate2D]
    let properties: [String: String]

    enum GeometryType: String, Sendable {
        case point = "Point"
        case lineString = "LineString"
        case polygon = "Polygon"
        case multiPoint = "MultiPoint"
        case unknown = "Unknown"
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

    private let geoPackageDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("GeoPackages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - File Management

    /// List available GeoPackage files in Documents/GeoPackages/
    func listAvailableFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: geoPackageDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return [] }

        return files.filter { $0.pathExtension.lowercased() == "gpkg" }
    }

    // MARK: - Import

    /// Import a GeoPackage file (placeholder implementation)
    func importGeoPackage(from url: URL) async throws {
        isImporting = true
        errorMessage = nil

        defer { isImporting = false }

        // Copy to app's Documents/GeoPackages if needed
        let destURL = geoPackageDir.appendingPathComponent(url.lastPathComponent)

        if url != destURL {
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: url, to: destURL)
        }

        self.currentFileName = url.lastPathComponent

        // Placeholder: simulate loading layers
        // In production: use geopackage-ios library
        // let gp = try GPKGGeoPackageManager().open(destURL)
        // let featureTables = gp.featureTables() as? [String]

        var layers: [GPKGLayer] = []

        // Simulate one layer
        layers.append(GPKGLayer(
            id: "features",
            name: url.lastPathComponent.replacingOccurrences(of: ".gpkg", with: ""),
            featureCount: 5,
            geometryType: .point
        ))

        importedLayers = layers
    }

    /// Get features from a specific layer (placeholder)
    func getFeatures(from layerName: String) -> [GPKGFeature] {
        // In production: iterate GPKGGeoPackage feature rows
        // For now, return empty
        return []
    }

    /// Close current GeoPackage
    func closeGeoPackage() {
        importedLayers = []
        currentFileName = nil
    }
}
