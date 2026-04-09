import Foundation
import SwiftUI
import CoreLocation

// MARK: - KmlHandler

class KmlHandler: ObservableObject {
    @Published var placemarks: [Placemark] = []
    @Published var paths: [Path] = []
    @Published var polygons: [Polygon] = []
    @Published var overlays: [Overlay] = []
    @Published var networkLinks: [NetworkLink] = []

    func readKml(from url: URL) async throws {
        let data = try Data(contentsOf: url)
        let parser = KmlParser(data: data)
        let kml = try parser.parse()
        
        placemarks = kml.placemarks
        paths = kml.paths
        polygons = kml.polygons
        overlays = kml.overlays
        networkLinks = kml.networkLinks
    }

    func writeKml(to url: URL) async throws {
        let kml = Kml(placemarks: placemarks, paths: paths, polygons: polygons, overlays: overlays, networkLinks: networkLinks)
        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(kml)
        try data.write(to: url)
    }
}

// MARK: - KmlParser

class KmlParser {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> Kml {
        let decoder = XMLDecoder()
        return try decoder.decode(Kml.self, from: data)
    }
}

// MARK: - Kml

struct Kml: Codable {
    let placemarks: [Placemark]
    let paths: [Path]
    let polygons: [Polygon]
    let overlays: [Overlay]
    let networkLinks: [NetworkLink]
}

// MARK: - Placemark

struct Placemark: Codable {
    let name: String
    let coordinates: CLLocationCoordinate2D
}

// MARK: - Path

struct Path: Codable {
    let name: String
    let coordinates: [CLLocationCoordinate2D]
}

// MARK: - Polygon

struct Polygon: Codable {
    let name: String
    let coordinates: [CLLocationCoordinate2D]
}

// MARK: - Overlay

struct Overlay: Codable {
    let name: String
    let bounds: (CLLocationCoordinate2D, CLLocationCoordinate2D)
}

// MARK: - NetworkLink

struct NetworkLink: Codable {
    let name: String
    let url: URL
    let cachePolicy: URLRequest.CachePolicy
}

// MARK: - CLLocationCoordinate2D

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}