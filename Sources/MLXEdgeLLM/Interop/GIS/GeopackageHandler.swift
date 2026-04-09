import Foundation
import SQLite

// MARK: - GeopackageHandler

class GeopackageHandler {
    private let db: Connection
    
    init?(url: URL) {
        do {
            db = try Connection(url.path)
        } catch {
            print("Failed to open database: \(error)")
            return nil
        }
    }
    
    func readFeatures(from layerName: String) throws -> [Feature] {
        let features = Table(layerName)
        let query = features.select(*)
        var featureList: [Feature] = []
        
        for row in try db.prepare(query) {
            let feature = Feature(
                id: row[features["id"]],
                geometry: row[features["geometry"]],
                properties: row[features["properties"]]
            )
            featureList.append(feature)
        }
        
        return featureList
    }
    
    func writeFeature(_ feature: Feature, to layerName: String) throws {
        let features = Table(layerName)
        let insert = features.insert(
            features["id"] <- feature.id,
            features["geometry"] <- feature.geometry,
            features["properties"] <- feature.properties
        )
        try db.run(insert)
    }
}

// MARK: - Feature

struct Feature {
    let id: Int64
    let geometry: String
    let properties: String
}

// MARK: - Tile

struct Tile {
    let z: Int
    let x: Int
    let y: Int
    let data: Data
}

// MARK: - Attachment

struct Attachment {
    let id: Int64
    let featureId: Int64
    let data: Data
}

// MARK: - Layer

struct Layer {
    let name: String
    let type: String
    let features: [Feature]
    let tiles: [Tile]
    let attachments: [Attachment]
}