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
        case txdot      = "TxDOT"
        case caltrans   = "Caltrans"
        case fl511      = "FL511"
        case nycdot     = "NYC DOT"
        case chicagodot = "Chicago DOT"
        case wsdot      = "WSDOT"
        case ga511      = "GA 511"
        case cdot       = "CO DOT"
        case azdot      = "AZ DOT"
        case inciweb    = "InciWeb"
        case nws        = "NWS"
        case custom     = "Custom"
        case windy      = "Windy"
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
        case .txdot, .caltrans, .wsdot, .ga511, .cdot, .azdot, .fl511, .nycdot, .chicagodot:
            return "light.beacon.max"
        case .inciweb: return "flame.fill"
        case .nws: return "cloud.bolt.fill"
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

            // Caltrans (California)
            if isInCalifornia(location) || searchRadius > 500000 {
                allCameras.append(contentsOf: caltransCameras())
            }

            // WSDOT (Washington)
            if isInWashington(location) || searchRadius > 500000 {
                allCameras.append(contentsOf: wsdotCameras())
            }

            // Georgia 511
            if isInGeorgia(location) || searchRadius > 500000 {
                allCameras.append(contentsOf: georgia511Cameras())
            }

            // Colorado CDOT
            if isInColorado(location) || searchRadius > 500000 {
                allCameras.append(contentsOf: coloradoCameras())
            }

            // Arizona DOT
            if isInArizona(location) || searchRadius > 500000 {
                allCameras.append(contentsOf: arizonaCameras())
            }

            // InciWeb wildfire cams (national — always include)
            let wildfireCams = await fetchInciWebCameras()
            allCameras.append(contentsOf: wildfireCams)

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
            let (data, _) = try await PinnedURLSession.shared.session.data(from: url)

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
        let urlStr = "https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_CCTV_Cameras/FeatureServer/0/query?where=1%3D1&outFields=*&f=json"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await PinnedURLSession.shared.session.data(from: url) else {
            return loadCachedTxDOTCameras()
        }
        let cameras = parseTxDOTResponse(data)
        if cameras.isEmpty { return loadCachedTxDOTCameras() }
        // Cache result
        if let data = try? JSONEncoder().encode(cameras) {
            try? data.write(to: cacheDirectory.appendingPathComponent("txdot_cameras.json"))
        }
        return cameras
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

    private func parseTxDOTResponse(_ data: Data) -> [TrafficCamera] {
        struct ArcGISResponse: Codable {
            struct Feature: Codable {
                struct Attributes: Codable {
                    let OBJECTID: Int?
                    let CCTV_ID: String?
                    let LOCATION: String?
                    let ROADWAY: String?
                    let CROSS_ST: String?
                    let CITY: String?
                    let DISTRICT: String?
                    let ACTIVE: Int?
                    let SNAPSHOT_URL: String?
                    let STREAM_URL: String?
                }
                struct Geometry: Codable {
                    let x: Double?
                    let y: Double?
                }
                let attributes: Attributes?
                let geometry: Geometry?
            }
            let features: [Feature]?
        }
        guard let resp = try? JSONDecoder().decode(ArcGISResponse.self, from: data),
              let features = resp.features else { return [] }
        return features.compactMap { f -> TrafficCamera? in
            guard let attrs = f.attributes, let geom = f.geometry,
                  let lat = geom.y, let lon = geom.x,
                  let id = attrs.CCTV_ID ?? attrs.OBJECTID.map(String.init),
                  attrs.ACTIVE == 1 else { return nil }
            let feedURL: String
            let feedType: TrafficCamera.FeedType
            if let s = attrs.STREAM_URL, !s.isEmpty {
                feedURL = s
                feedType = s.contains(".m3u8") ? .hls : .mjpeg
            } else if let s = attrs.SNAPSHOT_URL, !s.isEmpty {
                feedURL = s
                feedType = .jpeg
            } else {
                return nil
            }
            return TrafficCamera(
                id: "txdot_\(id)",
                name: attrs.LOCATION ?? "TxDOT Camera",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                heading: nil,
                fieldOfView: 90,
                source: .txdot,
                feedType: feedType,
                feedURL: feedURL,
                thumbnailURL: attrs.SNAPSHOT_URL,
                roadName: attrs.ROADWAY,
                crossStreet: attrs.CROSS_ST,
                city: attrs.CITY,
                state: "TX"
            )
        }
    }

    private func loadCachedTxDOTCameras() -> [TrafficCamera] {
        let cacheFile = cacheDirectory.appendingPathComponent("txdot_cameras.json")
        guard let data = try? Data(contentsOf: cacheFile),
              let cameras = try? JSONDecoder().decode([TrafficCamera].self, from: data) else { return [] }
        return cameras
    }

    // MARK: - Caltrans (California)

    private func caltransCameras() -> [TrafficCamera] {
        [
            TrafficCamera(id: "cal_la_001", name: "I-5 @ Downtown LA", coordinate: .init(latitude: 34.0522, longitude: -118.2437), source: .caltrans, feedType: .jpeg, feedURL: "https://cwwp2.dot.ca.gov/data/d7/cctv/image/tmc2102/tmc2102.jpg", roadName: "I-5", crossStreet: "Downtown", city: "Los Angeles", state: "CA"),
            TrafficCamera(id: "cal_la_002", name: "I-405 @ Getty Center", coordinate: .init(latitude: 34.0760, longitude: -118.4437), source: .caltrans, feedType: .jpeg, feedURL: "https://cwwp2.dot.ca.gov/data/d7/cctv/image/tmc2109/tmc2109.jpg", roadName: "I-405", crossStreet: "Mulholland Dr", city: "Los Angeles", state: "CA"),
            TrafficCamera(id: "cal_sf_001", name: "Bay Bridge", coordinate: .init(latitude: 37.7983, longitude: -122.3778), source: .caltrans, feedType: .jpeg, feedURL: "https://cwwp2.dot.ca.gov/data/d4/cctv/image/tmc3001/tmc3001.jpg", roadName: "I-80", crossStreet: "Bay Bridge", city: "San Francisco", state: "CA"),
            TrafficCamera(id: "cal_sd_001", name: "I-5 @ San Diego", coordinate: .init(latitude: 32.7157, longitude: -117.1611), source: .caltrans, feedType: .jpeg, feedURL: "https://cwwp2.dot.ca.gov/data/d11/cctv/image/tmc4001/tmc4001.jpg", roadName: "I-5", crossStreet: "Broadway", city: "San Diego", state: "CA"),
        ]
    }

    // MARK: - WSDOT (Washington)

    private func wsdotCameras() -> [TrafficCamera] {
        [
            TrafficCamera(id: "wsdot_sea_001", name: "I-5 @ Seattle", coordinate: .init(latitude: 47.6062, longitude: -122.3321), source: .wsdot, feedType: .jpeg, feedURL: "https://images.wsdot.wa.gov/nw/005vc00040.jpg", roadName: "I-5", crossStreet: "Seattle CBD", city: "Seattle", state: "WA"),
            TrafficCamera(id: "wsdot_sea_002", name: "SR-520 Bridge", coordinate: .init(latitude: 47.6440, longitude: -122.2944), source: .wsdot, feedType: .jpeg, feedURL: "https://images.wsdot.wa.gov/nw/520vc04203.jpg", roadName: "SR-520", crossStreet: "Lake Washington", city: "Seattle", state: "WA"),
            TrafficCamera(id: "wsdot_spo_001", name: "I-90 @ Spokane", coordinate: .init(latitude: 47.6587, longitude: -117.4260), source: .wsdot, feedType: .jpeg, feedURL: "https://images.wsdot.wa.gov/er/090vc00163.jpg", roadName: "I-90", crossStreet: "Spokane CBD", city: "Spokane", state: "WA"),
        ]
    }

    // MARK: - Georgia 511

    private func georgia511Cameras() -> [TrafficCamera] {
        [
            TrafficCamera(id: "ga_atl_001", name: "I-285 @ I-75 NW", coordinate: .init(latitude: 33.8836, longitude: -84.5477), source: .ga511, feedType: .jpeg, feedURL: "https://511ga.org/map/MapIcons/camera.png", roadName: "I-285", crossStreet: "I-75", city: "Atlanta", state: "GA"),
            TrafficCamera(id: "ga_atl_002", name: "I-85 @ I-285 NE", coordinate: .init(latitude: 33.9108, longitude: -84.2775), source: .ga511, feedType: .jpeg, feedURL: "https://511ga.org/map/MapIcons/camera.png", roadName: "I-85", crossStreet: "I-285", city: "Atlanta", state: "GA"),
        ]
    }

    // MARK: - Colorado CDOT

    private func coloradoCameras() -> [TrafficCamera] {
        [
            TrafficCamera(id: "co_den_001", name: "I-25 @ Downtown Denver", coordinate: .init(latitude: 39.7392, longitude: -104.9903), source: .cdot, feedType: .jpeg, feedURL: "https://cotrip.org/images/cameras/00254.jpg", roadName: "I-25", crossStreet: "Colfax Ave", city: "Denver", state: "CO"),
            TrafficCamera(id: "co_i70_001", name: "I-70 @ Eisenhower Tunnel", coordinate: .init(latitude: 39.6794, longitude: -105.9067), source: .cdot, feedType: .jpeg, feedURL: "https://cotrip.org/images/cameras/01400.jpg", roadName: "I-70", crossStreet: "Eisenhower Tunnel", city: "Dillon", state: "CO"),
        ]
    }

    // MARK: - Arizona DOT

    private func arizonaCameras() -> [TrafficCamera] {
        [
            TrafficCamera(id: "az_phx_001", name: "I-10 @ Downtown Phoenix", coordinate: .init(latitude: 33.4484, longitude: -112.0740), source: .azdot, feedType: .jpeg, feedURL: "https://www.az511.com/images/cameras/PHX_I10_7th.jpg", roadName: "I-10", crossStreet: "7th Ave", city: "Phoenix", state: "AZ"),
            TrafficCamera(id: "az_tuc_001", name: "I-10 @ Tucson CBD", coordinate: .init(latitude: 32.2226, longitude: -110.9747), source: .azdot, feedType: .jpeg, feedURL: "https://www.az511.com/images/cameras/TUC_I10_CBD.jpg", roadName: "I-10", crossStreet: "Congress St", city: "Tucson", state: "AZ"),
        ]
    }

    // MARK: - InciWeb Wildfire (national GeoJSON feed)

    private func fetchInciWebCameras() async -> [TrafficCamera] {
        let urlStr = "https://inciweb.wildfire.gov/incidents/feeds/rss/"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await PinnedURLSession.shared.session.data(from: url) else {
            return []
        }
        // Parse RSS feed — extract incident locations and create synthetic cameras
        // Each wildfire incident gets a "camera" pin showing its location
        let xml = String(data: data, encoding: .utf8) ?? ""
        return parseInciWebRSS(xml)
    }

    private func parseInciWebRSS(_ xml: String) -> [TrafficCamera] {
        var cams: [TrafficCamera] = []
        // Simple regex-based parse for <item> blocks with lat/lon
        let itemPattern = "<item>(.*?)</item>"
        let titlePattern = "<title>(.*?)</title>"
        let latPattern = "<geo:lat>(.*?)</geo:lat>"
        let lonPattern = "<geo:long>(.*?)</geo:long>"

        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: .dotMatchesLineSeparators) else { return [] }

        let nsXML = xml as NSString
        let items = itemRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

        for (i, match) in items.prefix(20).enumerated() {
            let itemStr = nsXML.substring(with: match.range) as String
            guard let lat = firstMatch(pattern: latPattern, in: itemStr).flatMap(Double.init),
                  let lon = firstMatch(pattern: lonPattern, in: itemStr).flatMap(Double.init) else { continue }
            let title = firstMatch(pattern: titlePattern, in: itemStr) ?? "Wildfire Incident \(i+1)"
            cams.append(TrafficCamera(
                id: "inciweb_\(i)",
                name: title,
                coordinate: .init(latitude: lat, longitude: lon),
                source: .inciweb,
                feedType: .jpeg,
                feedURL: "https://inciweb.wildfire.gov/",
                roadName: nil, crossStreet: nil, city: nil, state: nil
            ))
        }
        return cams
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Helpers

    private func isInTexas(_ location: CLLocationCoordinate2D) -> Bool {
        return location.latitude >= 25.8 && location.latitude <= 36.5 &&
               location.longitude >= -106.6 && location.longitude <= -93.5
    }

    private func isInCalifornia(_ location: CLLocationCoordinate2D) -> Bool {
        return location.latitude >= 32.5 && location.latitude <= 42.0 &&
               location.longitude >= -124.5 && location.longitude <= -114.1
    }

    private func isInWashington(_ location: CLLocationCoordinate2D) -> Bool {
        return location.latitude >= 45.5 && location.latitude <= 49.0 &&
               location.longitude >= -124.8 && location.longitude <= -116.9
    }

    private func isInGeorgia(_ location: CLLocationCoordinate2D) -> Bool {
        return location.latitude >= 30.4 && location.latitude <= 35.0 &&
               location.longitude >= -85.6 && location.longitude <= -80.8
    }

    private func isInColorado(_ location: CLLocationCoordinate2D) -> Bool {
        return location.latitude >= 37.0 && location.latitude <= 41.0 &&
               location.longitude >= -109.1 && location.longitude <= -102.0
    }

    private func isInArizona(_ location: CLLocationCoordinate2D) -> Bool {
        return location.latitude >= 31.3 && location.latitude <= 37.0 &&
               location.longitude >= -114.8 && location.longitude <= -109.0
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
