import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TakOfflineCache

class TakOfflineCache: ObservableObject {
    @Published private(set) var markers: [Marker] = []
    @Published private(set) var routes: [Route] = []
    @Published private(set) var imagery: [Imagery] = []
    
    private let storageManager: StorageManager
    private let expirationPolicy: ExpirationPolicy
    
    init(storageManager: StorageManager, expirationPolicy: ExpirationPolicy) {
        self.storageManager = storageManager
        self.expirationPolicy = expirationPolicy
        loadCachedData()
    }
    
    func syncData(markers: [Marker], routes: [Route], imagery: [Imagery]) {
        Task {
            await storageManager.save(markers: markers, routes: routes, imagery: imagery)
            self.markers = markers
            self.routes = routes
            self.imagery = imagery
        }
    }
    
    func removeExpiredData() {
        Task {
            let expiredMarkers = markers.filter { expirationPolicy.isExpired($0) }
            let expiredRoutes = routes.filter { expirationPolicy.isExpired($0) }
            let expiredImagery = imagery.filter { expirationPolicy.isExpired($0) }
            
            await storageManager.remove(expiredMarkers: expiredMarkers, expiredRoutes: expiredRoutes, expiredImagery: expiredImagery)
            
            markers.removeAll { expiredMarkers.contains($0) }
            routes.removeAll { expiredRoutes.contains($0) }
            imagery.removeAll { expiredImagery.contains($0) }
        }
    }
    
    private func loadCachedData() {
        Task {
            let (cachedMarkers, cachedRoutes, cachedImagery) = await storageManager.load()
            markers = cachedMarkers
            routes = cachedRoutes
            imagery = cachedImagery
        }
    }
}

// MARK: - Models

struct Marker: Identifiable {
    let id: UUID
    let location: CLLocationCoordinate2D
    let title: String
    let timestamp: Date
}

struct Route: Identifiable {
    let id: UUID
    let waypoints: [CLLocationCoordinate2D]
    let timestamp: Date
}

struct Imagery: Identifiable {
    let id: UUID
    let image: Data
    let location: CLLocationCoordinate2D
    let timestamp: Date
}

// MARK: - StorageManager

actor StorageManager {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    func save(markers: [Marker], routes: [Route], imagery: [Imagery]) async {
        await save(markers: markers, to: "markers.json")
        await save(routes: routes, to: "routes.json")
        await save(imagery: imagery, to: "imagery.json")
    }
    
    func load() async -> ([Marker], [Route], [Imagery]) {
        let markers = await load(from: "markers.json")
        let routes = await load(from: "routes.json")
        let imagery = await load(from: "imagery.json")
        return (markers, routes, imagery)
    }
    
    func remove(expiredMarkers: [Marker], expiredRoutes: [Route], expiredImagery: [Imagery]) async {
        await remove(expiredMarkers, from: "markers.json")
        await remove(expiredRoutes, from: "routes.json")
        await remove(expiredImagery, from: "imagery.json")
    }
    
    private func save<T: Codable>(items: [T], to filename: String) async {
        let url = cacheDirectory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(items)
            try await fileManager.write(contentsOf: url, data: data)
        } catch {
            print("Failed to save \(filename): \(error)")
        }
    }
    
    private func load<T: Codable>(from filename: String) async -> [T] {
        let url = cacheDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try await fileManager.contentsOf(url)
            return try decoder.decode([T].self, from: data)
        } catch {
            print("Failed to load \(filename): \(error)")
            return []
        }
    }
    
    private func remove<T: Codable>(_ items: [T], from filename: String) async {
        let url = cacheDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try await fileManager.contentsOf(url)
            var existingItems = try decoder.decode([T].self, from: data)
            existingItems.removeAll { items.contains($0) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let newData = try encoder.encode(existingItems)
            try await fileManager.write(contentsOf: url, data: newData)
        } catch {
            print("Failed to remove items from \(filename): \(error)")
        }
    }
}

// MARK: - ExpirationPolicy

protocol ExpirationPolicy {
    func isExpired(_ item: Marker) -> Bool
    func isExpired(_ item: Route) -> Bool
    func isExpired(_ item: Imagery) -> Bool
}

struct DefaultExpirationPolicy: ExpirationPolicy {
    let markerExpiration: TimeInterval
    let routeExpiration: TimeInterval
    let imageryExpiration: TimeInterval
    
    init(markerExpiration: TimeInterval = 24 * 60 * 60, // 1 day
         routeExpiration: TimeInterval = 7 * 24 * 60 * 60, // 7 days
         imageryExpiration: TimeInterval = 30 * 24 * 60 * 60) { // 30 days
        
        self.markerExpiration = markerExpiration
        self.routeExpiration = routeExpiration
        self.imageryExpiration = imageryExpiration
    }
    
    func isExpired(_ marker: Marker) -> Bool {
        return marker.timestamp.addingTimeInterval(markerExpiration) < Date()
    }
    
    func isExpired(_ route: Route) -> Bool {
        return route.timestamp.addingTimeInterval(routeExpiration) < Date()
    }
    
    func isExpired(_ imagery: Imagery) -> Bool {
        return imagery.timestamp.addingTimeInterval(imageryExpiration) < Date()
    }
}