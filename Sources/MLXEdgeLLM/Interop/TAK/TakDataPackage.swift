import Foundation
import SwiftUI
import CoreLocation
import ZIPFoundation

// MARK: - TAK Data Package Handler

class TakDataPackage: ObservableObject {
    @Published var markers: [Marker] = []
    @Published var routes: [Route] = []
    @Published var overlays: [Overlay] = []
    
    func loadPackage(from url: URL) throws {
        let archive = Archive(url: url, accessMode: .read)
        try archive.extract(into: url.deletingLastPathComponent())
        
        let markersFile = url.deletingLastPathComponent().appendingPathComponent("markers.json")
        let routesFile = url.deletingLastPathComponent().appendingPathComponent("routes.json")
        let overlaysFile = url.deletingLastPathComponent().appendingPathComponent("overlays.json")
        
        if let markersData = try? Data(contentsOf: markersFile) {
            markers = try JSONDecoder().decode([Marker].self, from: markersData)
        }
        
        if let routesData = try? Data(contentsOf: routesFile) {
            routes = try JSONDecoder().decode([Route].self, from: routesData)
        }
        
        if let overlaysData = try? Data(contentsOf: overlaysFile) {
            overlays = try JSONDecoder().decode([Overlay].self, from: overlaysData)
        }
    }
    
    func savePackage(to url: URL) throws {
        let tempDir = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let markersFile = tempDir.appendingPathComponent("markers.json")
        let routesFile = tempDir.appendingPathComponent("routes.json")
        let overlaysFile = tempDir.appendingPathComponent("overlays.json")
        
        let markersData = try JSONEncoder().encode(markers)
        let routesData = try JSONEncoder().encode(routes)
        let overlaysData = try JSONEncoder().encode(overlays)
        
        try markersData.write(to: markersFile)
        try routesData.write(to: routesFile)
        try overlaysData.write(to: overlaysFile)
        
        let archive = Archive(url: url, accessMode: .create)
        try archive.addItems(at: [markersFile, routesFile, overlaysFile])
        
        try FileManager.default.removeItem(at: tempDir)
    }
}

// MARK: - Models

struct Marker: Codable, Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct Route: Codable, Identifiable {
    let id: UUID
    let name: String
    let coordinates: [CLLocationCoordinate2D]
}

struct Overlay: Codable, Identifiable {
    let id: UUID
    let name: String
    let image: Data
}