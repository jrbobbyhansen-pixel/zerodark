import Foundation
import CoreLocation

// MARK: - GeoJSON Handler

class GeojsonHandler {
    
    // MARK: - Types
    
    enum GeometryType: String, Codable {
        case point = "Point"
        case multiPoint = "MultiPoint"
        case lineString = "LineString"
        case multiLineString = "MultiLineString"
        case polygon = "Polygon"
        case multiPolygon = "MultiPolygon"
        case geometryCollection = "GeometryCollection"
    }
    
    struct Geometry: Codable {
        let type: GeometryType
        let coordinates: [[CLLocationCoordinate2D]]
    }
    
    struct Feature: Codable {
        let type: String = "Feature"
        let geometry: Geometry
        let properties: [String: Any]
    }
    
    struct FeatureCollection: Codable {
        let type: String = "FeatureCollection"
        let features: [Feature]
    }
    
    // MARK: - Methods
    
    func readGeoJSON(from url: URL) async throws -> FeatureCollection {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FeatureCollection.self, from: data)
    }
    
    func writeGeoJSON(_ featureCollection: FeatureCollection, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(featureCollection)
        try data.write(to: url)
    }
    
    // MARK: - Coordinate Precision Handling
    
    func roundCoordinates(_ coordinates: [[CLLocationCoordinate2D]], precision: Int) -> [[CLLocationCoordinate2D]] {
        return coordinates.map { coordinateArray in
            coordinateArray.map { coordinate in
                CLLocationCoordinate2D(latitude: round(coordinate.latitude * pow(10, Double(precision))) / pow(10, Double(precision)),
                                      longitude: round(coordinate.longitude * pow(10, Double(precision))) / pow(10, Double(precision)))
            }
        }
    }
    
    // MARK: - Streaming for Large Files
    
    func streamGeoJSON(from url: URL) async throws -> AsyncThrowingStream<Feature, Error> {
        let fileHandle = try FileHandle(forReadingFrom: url)
        let decoder = JSONDecoder()
        
        return AsyncThrowingStream { continuation in
            defer {
                continuation.finish()
                fileHandle.closeFile()
            }
            
            let stream = InputStream(url: url)
            stream.delegate = self
            stream.schedule(in: .current, forMode: .default)
            stream.open()
        }
    }
}

// MARK: - InputStream Delegate

extension GeojsonHandler: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            // Handle streaming data here
            break
        case .endEncountered:
            // Handle end of stream
            break
        case .errorOccurred:
            // Handle error
            break
        default:
            break
        }
    }
}