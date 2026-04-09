import Foundation

// MARK: - GPX Handler

class GpxHandler {
    
    // MARK: - Properties
    
    private let decoder = XMLDecoder()
    private let encoder = XMLEncoder()
    
    // MARK: - Public Methods
    
    func readGPX(from url: URL) throws -> GPX {
        let data = try Data(contentsOf: url)
        return try decoder.decode(GPX.self, from: data)
    }
    
    func writeGPX(_ gpx: GPX, to url: URL) throws {
        let data = try encoder.encode(gpx)
        try data.write(to: url)
    }
}

// MARK: - GPX Model

struct GPX: Codable {
    let version: String
    let creator: String
    let waypoints: [GpxWaypoint]
    let routes: [Route]
    let tracks: [Track]
    let metadata: Metadata?
    
    enum CodingKeys: String, CodingKey {
        case version = "version"
        case creator = "creator"
        case waypoints = "wpt"
        case routes = "rte"
        case tracks = "trk"
        case metadata = "metadata"
    }
}

struct GpxWaypoint: Codable {
    let latitude: Double
    let longitude: Double
    let name: String?
    let elevation: Double?
    let time: Date?
    let extensions: Extensions?
    
    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
        case name = "name"
        case elevation = "ele"
        case time = "time"
        case extensions = "extensions"
    }
}

struct Route: Codable {
    let name: String?
    let points: [GpxWaypoint]
    let extensions: Extensions?
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case points = "rtept"
        case extensions = "extensions"
    }
}

struct Track: Codable {
    let name: String?
    let segments: [TrackSegment]
    let extensions: Extensions?
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case segments = "trkseg"
        case extensions = "extensions"
    }
}

struct TrackSegment: Codable {
    let points: [GpxWaypoint]
    
    enum CodingKeys: String, CodingKey {
        case points = "trkpt"
    }
}

struct Metadata: Codable {
    let name: String?
    let description: String?
    let author: String?
    let time: Date?
    let keywords: String?
    extensions: Extensions?
    
    enum CodingKeys: String, CodingKey {
        case name = "name"
        case description = "desc"
        case author = "author"
        case time = "time"
        case keywords = "keywords"
        case extensions = "extensions"
    }
}

struct Extensions: Codable {
    // Placeholder for any additional custom data
    let customData: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case customData = "customData"
    }
}