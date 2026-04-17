// NavState.swift — Unified navigation state for cross-tab sync
// Published by AppState, consumed by NavTabView and Map/Intel overlays

import Foundation
import CoreLocation
import Combine

// MARK: - NavTrailPoint (3D breadcrumb with metadata)

struct NavTrailPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: TimeInterval
    let uncertainty: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, altitude: Double, timestamp: TimeInterval, uncertainty: Double) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.uncertainty = uncertainty
    }
}

// MARK: - NavPose (fused EKF output snapshot)

struct NavPose: Equatable {
    let coordinate: CLLocationCoordinate2D
    let heading: Double
    let speed: Double

    static func == (lhs: NavPose, rhs: NavPose) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.heading == rhs.heading &&
        lhs.speed == rhs.speed
    }
}

// MARK: - NavState (cross-tab published state)

struct NavState: Equatable {
    var position: CLLocationCoordinate2D?
    var altitude: Double = 0
    var heading: Double = 0
    var speed: Double = 0
    var ekfUncertainty: Double = 0
    var deadReckoningActive: Bool = false
    var drConfidence: Double = 0
    var celestialHeading: Double?
    var batteryTrend: Double = 0
    var batteryMinutesRemaining: Double = 0
    var viewshedTimestamp: Date?
    var canopyDetected: Bool = false
    var zuptCount: Int = 0

    static func == (lhs: NavState, rhs: NavState) -> Bool {
        lhs.position?.latitude == rhs.position?.latitude &&
        lhs.position?.longitude == rhs.position?.longitude &&
        lhs.altitude == rhs.altitude &&
        lhs.heading == rhs.heading &&
        lhs.speed == rhs.speed &&
        lhs.ekfUncertainty == rhs.ekfUncertainty &&
        lhs.deadReckoningActive == rhs.deadReckoningActive &&
        lhs.drConfidence == rhs.drConfidence &&
        lhs.celestialHeading == rhs.celestialHeading &&
        lhs.batteryTrend == rhs.batteryTrend &&
        lhs.batteryMinutesRemaining == rhs.batteryMinutesRemaining &&
        lhs.viewshedTimestamp == rhs.viewshedTimestamp &&
        lhs.canopyDetected == rhs.canopyDetected &&
        lhs.zuptCount == rhs.zuptCount
    }
}

// MARK: - NavEvent (discrete navigation events for event bus)

enum NavEvent {
    case positionUpdated(CLLocationCoordinate2D)
    case viewshedComputed(ViewshedResult)
    case drDriftWarning(meters: Double)
    case batteryLow(minutesRemaining: Double)
    case geofenceKeyRotated(fenceId: UUID)
}

// MARK: - ViewshedResult

struct ViewshedResult {
    let observer: CLLocationCoordinate2D
    let radius: Double
    let resolution: Int
    let samplesPerRadial: Int
    let visibility: [Float]  // resolution * samplesPerRadial (1.0=visible, 0.0=blocked)
    let computeTimeMs: Double
}

// MARK: - ElevationProfilePoint

struct ElevationProfilePoint {
    let distance: Double         // meters from observer
    let terrainElevation: Double // meters above sea level
    let losHeight: Double        // line-of-sight height at this distance
    let isBlocked: Bool
}

// MARK: - CelestialOverlayData

struct CelestialOverlayData: Equatable {
    let sunAzimuth: Double
    let sunAltitude: Double
    let moonAzimuth: Double?
    let moonAltitude: Double?
    let detectedStarPositions: [(x: Double, y: Double)]
    let timestamp: Date

    static func == (lhs: CelestialOverlayData, rhs: CelestialOverlayData) -> Bool {
        lhs.sunAzimuth == rhs.sunAzimuth &&
        lhs.sunAltitude == rhs.sunAltitude &&
        lhs.timestamp == rhs.timestamp
    }
}

// MARK: - CelestialFallback

enum CelestialFallback: String {
    case none
    case sunOnly
    case magFallback
    case gyroOnly
}

// ActivityLevel removed — defined elsewhere
