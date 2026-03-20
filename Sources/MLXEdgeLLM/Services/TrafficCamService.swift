// TrafficCamService.swift — Live Traffic Camera Integration

import Foundation
import CoreLocation
import Combine
import MapKit
import AVKit

// MARK: - Camera Model

struct TrafficCamera: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let heading: Double?           // Camera pointing direction (0-360, nil = unknown)
    let fieldOfView: Double?       // FOV in degrees (typically 60-120)
    let source: CameraSource
    let feedType: FeedType
    let feedURL: String
    let thumbnailURL: String?
    let lastUpdated: Date?
    let isActive: Bool

    // Metadata
    let roadName: String?
    let crossStreet: String?
    let city: String?
    let state: String?

    enum CameraSource: String, Codable {
        case txdot = "TxDOT"
        case caltrans = "Caltrans"
        case fl511 = "FL511"
        case nycdot = "NYC DOT"
        case chicagodot = "Chicago DOT"
        case custom = "Custom"
        case windy = "Windy"
    }

    enum FeedType: String, Codable {
        case jpeg           // Static image, refresh periodically
        case mjpeg          // Motion JPEG stream
        case hls            // HLS video stream (.m3u8)
        case rtsp           // RTSP stream (needs VLCKit)
    }

    // Computed
    var displayName: String {
        if let road = roadName, let cross = crossStreet {
            return "\(road) @ \(cross)"
        }
        return name
    }

    var sourceIcon: String {
        switch source {
        case .txdot: return "mappin.and.ellipse"
        case .caltrans, .fl511, .nycdot, .chicagodot: return "light.beacon.max"
        case .windy: return "cloud.sun"
        case .custom: return "video.fill"
        }
    }

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrafficCamera, rhs: TrafficCamera) -> Bool {
        lhs.id == rhs.id
    }

    // Codable for CLLocationCoordinate2D
    enum CodingKeys: String, CodingKey {
        case id, name, heading, fieldOfView, source, feedType, feedURL
        case thumbnailURL, lastUpdated, isActive
        case roadName, crossStreet, city, state
        case latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lon = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        heading = try container.decodeIfPresent(Double.self, forKey: .heading)
        fieldOfView = try container.decodeIfPresent(Double.self, forKey: .fieldOfView)
        source = try container.decode(CameraSource.self, forKey: .source)
        feedType = try container.decode(FeedType.self, forKey: .feedType)
        feedURL = try container.decode(String.self, forKey: .feedURL)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        roadName = try container.decodeIfPresent(String.self, forKey: .roadName)
        crossStreet = try container.decodeIfPresent(String.self, forKey: .crossStreet)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encodeIfPresent(heading, forKey: .heading)
        try container.encodeIfPresent(fieldOfView, forKey: .fieldOfView)
        try container.encode(source, forKey: .source)
        try container.encode(feedType, forKey: .feedType)
        try container.encode(feedURL, forKey: .feedURL)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(roadName, forKey: .roadName)
        try container.encodeIfPresent(crossStreet, forKey: .crossStreet)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(state, forKey: .state)
    }

    init(id: String, name: String, coordinate: CLLocationCoordinate2D, heading: Double? = nil,
         fieldOfView: Double? = nil, source: CameraSource, feedType: FeedType, feedURL: String,
         thumbnailURL: String? = nil, roadName: String? = nil, crossStreet: String? = nil,
         city: String? = nil, state: String? = nil) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.heading = heading
        self.fieldOfView = fieldOfView ?? 90
        self.source = source
        self.feedType = feedType
        self.feedURL = feedURL
        self.thumbnailURL = thumbnailURL
        self.lastUpdated = Date()
        self.isActive = true
        self.roadName = roadName
        self.crossStreet = crossStreet
        self.city = city
        self.state = state
    }
}

// MARK: - Traffic Cam Service

@MainActor
final class TrafficCamService: ObservableObject {
    static let shared = TrafficCamService()

    // MARK: Published State
    @Published var cameras: [TrafficCamera] = []
    @Published var nearbyCameras: [TrafficCamera] = []
    @Published var favoriteCameras: [TrafficCamera] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var selectedCamera: TrafficCamera?

    // MARK: Configuration
    var searchRadius: Double = 50000  // 50km default
    var maxCamerasToShow: Int = 100

    // MARK: Private
    private let cacheDirectory: URL
    private var loadedSources: Set<TrafficCamera.CameraSource> = []
    private var imageCache: [String: Data] = [:]  // Last frame cache

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = docs.appendingPathComponent("CameraCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        loadFavorites()
        loadCachedCameras()
    }

    // MARK: - Public API

    /// Fetch cameras near a location
    func fetchNearbyCameras(location: CLLocationCoordinate2D, radius: Double? = nil) async {
        isLoading = true
        lastError = nil

        let searchRadius = radius ?? self.searchRadius

        do {
            // Fetch from all enabled sources
            var allCameras: [TrafficCamera] = []

            // TxDOT (Texas)
            if isInTexas(location) || searchRadius > 500000 {
                let txCams = await fetchTxDOTCameras()
                allCameras.append(contentsOf: txCams)
            }

            // Filter by distance
            let nearby = allCameras.filter { cam in
                let distance = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    .distance(from: CLLocation(latitude: cam.coordinate.latitude, longitude: cam.coordinate.longitude))
                return distance <= searchRadius
            }
            .sorted { cam1, cam2 in
                let d1 = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    .distance(from: CLLocation(latitude: cam1.coordinate.latitude, longitude: cam1.coordinate.longitude))
                let d2 = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    .distance(from: CLLocation(latitude: cam2.coordinate.latitude, longitude: cam2.coordinate.longitude))
                return d1 < d2
            }
            .prefix(maxCamerasToShow)

            nearbyCameras = Array(nearby)
            cameras = allCameras

            // Cache for offline
            saveCamerasToCache(allCameras)

        }

        isLoading = false
    }

    /// Get cameras visible in a map region
    func camerasInRegion(_ region: MKCoordinateRegion) -> [TrafficCamera] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        return cameras.filter { cam in
            cam.coordinate.latitude >= minLat &&
            cam.coordinate.latitude <= maxLat &&
            cam.coordinate.longitude >= minLon &&
            cam.coordinate.longitude <= maxLon
        }
    }

    /// Fetch latest frame for a JPEG camera
    func fetchFrame(for camera: TrafficCamera) async -> Data? {
        guard camera.feedType == .jpeg else { return nil }

        guard let url = URL(string: camera.feedURL) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            // Cache the frame
            imageCache[camera.id] = data
            saveFrameToCache(camera.id, data: data)

            return data
        } catch {
            // Return cached frame if available
            return cachedFrame(for: camera.id)
        }
    }

    /// Get cached frame (for offline)
    func cachedFrame(for cameraId: String) -> Data? {
        if let cached = imageCache[cameraId] {
            return cached
        }

        let cacheFile = cacheDirectory.appendingPathComponent("\(cameraId).jpg")
        return try? Data(contentsOf: cacheFile)
    }

    // MARK: - Favorites

    func addFavorite(_ camera: TrafficCamera) {
        if !favoriteCameras.contains(camera) {
            favoriteCameras.append(camera)
            saveFavorites()
        }
    }

    func removeFavorite(_ camera: TrafficCamera) {
        favoriteCameras.removeAll { $0.id == camera.id }
        saveFavorites()
    }

    func isFavorite(_ camera: TrafficCamera) -> Bool {
        favoriteCameras.contains { $0.id == camera.id }
    }

    // MARK: - TxDOT Integration

    private func fetchTxDOTCameras() async -> [TrafficCamera] {
        // Return hardcoded TxDOT cameras
        return txdotSanAntonioCameras()
    }

    private func txdotSanAntonioCameras() -> [TrafficCamera] {
        [
            TrafficCamera(
                id: "txdot_sat_001",
                name: "I-10 @ Loop 410",
                coordinate: CLLocationCoordinate2D(latitude: 29.4867, longitude: -98.5256),
                heading: 45,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/SAT/SAT_I10_Loop410.jpg",
                roadName: "I-10",
                crossStreet: "Loop 410",
                city: "San Antonio",
                state: "TX"
            ),
            TrafficCamera(
                id: "txdot_sat_002",
                name: "I-35 @ Downtown",
                coordinate: CLLocationCoordinate2D(latitude: 29.4241, longitude: -98.4936),
                heading: 180,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/SAT/SAT_I35_Downtown.jpg",
                roadName: "I-35",
                crossStreet: "Commerce St",
                city: "San Antonio",
                state: "TX"
            ),
            TrafficCamera(
                id: "txdot_sat_003",
                name: "US-281 @ Loop 1604",
                coordinate: CLLocationCoordinate2D(latitude: 29.5789, longitude: -98.4567),
                heading: 270,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/SAT/SAT_US281_Loop1604.jpg",
                roadName: "US-281",
                crossStreet: "Loop 1604",
                city: "San Antonio",
                state: "TX"
            ),
            TrafficCamera(
                id: "txdot_aus_001",
                name: "I-35 @ US-183",
                coordinate: CLLocationCoordinate2D(latitude: 30.3322, longitude: -97.7137),
                heading: 0,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/AUS/AUS_I35_US183.jpg",
                roadName: "I-35",
                crossStreet: "US-183",
                city: "Austin",
                state: "TX"
            ),
            TrafficCamera(
                id: "txdot_aus_002",
                name: "MoPac @ 360",
                coordinate: CLLocationCoordinate2D(latitude: 30.3589, longitude: -97.8011),
                heading: 90,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/AUS/AUS_MoPac_360.jpg",
                roadName: "MoPac",
                crossStreet: "Loop 360",
                city: "Austin",
                state: "TX"
            ),
            TrafficCamera(
                id: "txdot_hou_001",
                name: "I-10 @ I-610",
                coordinate: CLLocationCoordinate2D(latitude: 29.7749, longitude: -95.4194),
                heading: 135,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/HOU/HOU_I10_I610.jpg",
                roadName: "I-10",
                crossStreet: "I-610",
                city: "Houston",
                state: "TX"
            ),
            TrafficCamera(
                id: "txdot_hou_002",
                name: "I-45 @ Downtown",
                coordinate: CLLocationCoordinate2D(latitude: 29.7589, longitude: -95.3599),
                heading: 315,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/HOU/HOU_I45_Downtown.jpg",
                roadName: "I-45",
                crossStreet: "Allen Pkwy",
                city: "Houston",
                state: "TX"
            ),
            TrafficCamera(
                id: "txdot_dal_001",
                name: "I-35E @ I-30",
                coordinate: CLLocationCoordinate2D(latitude: 32.7789, longitude: -96.7967),
                heading: 225,
                fieldOfView: 90,
                source: .txdot,
                feedType: .jpeg,
                feedURL: "https://its.txdot.gov/ITS_WEB/FrontEnd/snapshots/DAL/DAL_I35E_I30.jpg",
                roadName: "I-35E",
                crossStreet: "I-30",
                city: "Dallas",
                state: "TX"
            )
        ]
    }

    // MARK: - Helpers

    private func isInTexas(_ location: CLLocationCoordinate2D) -> Bool {
        // Rough Texas bounding box
        return location.latitude >= 25.8 && location.latitude <= 36.5 &&
               location.longitude >= -106.6 && location.longitude <= -93.5
    }

    // MARK: - Caching

    private func saveCamerasToCache(_ cameras: [TrafficCamera]) {
        let cacheFile = cacheDirectory.appendingPathComponent("cameras.json")
        if let data = try? JSONEncoder().encode(cameras) {
            try? data.write(to: cacheFile)
        }
    }

    private func loadCachedCameras() {
        let cacheFile = cacheDirectory.appendingPathComponent("cameras.json")
        if let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode([TrafficCamera].self, from: data) {
            cameras = cached
        }
    }

    private func saveFrameToCache(_ cameraId: String, data: Data) {
        let cacheFile = cacheDirectory.appendingPathComponent("\(cameraId).jpg")
        try? data.write(to: cacheFile)
    }

    private func saveFavorites() {
        let favFile = cacheDirectory.appendingPathComponent("favorites.json")
        if let data = try? JSONEncoder().encode(favoriteCameras) {
            try? data.write(to: favFile)
        }
    }

    private func loadFavorites() {
        let favFile = cacheDirectory.appendingPathComponent("favorites.json")
        if let data = try? Data(contentsOf: favFile),
           let favs = try? JSONDecoder().decode([TrafficCamera].self, from: data) {
            favoriteCameras = favs
        }
    }
}
