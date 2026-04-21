// NavigationTests.swift — Unit tests for Navigation/FieldOps v6.1 components

import XCTest
@testable import ZeroDark

final class NavigationTests: XCTestCase {

    // MARK: - W1: EKF / Dead Reckoning / ZUPT

    func testNavTrailPointCodable() throws {
        let point = NavTrailPoint(
            coordinate: .init(latitude: 30.2672, longitude: -97.7431),
            altitude: 150.0,
            timestamp: 1000.0,
            uncertainty: 5.0
        )

        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(NavTrailPoint.self, from: data)

        XCTAssertEqual(decoded.latitude, point.latitude, accuracy: 1e-10)
        XCTAssertEqual(decoded.longitude, point.longitude, accuracy: 1e-10)
        XCTAssertEqual(decoded.altitude, point.altitude, accuracy: 1e-10)
        XCTAssertEqual(decoded.uncertainty, point.uncertainty, accuracy: 1e-10)
    }

    func testNavStateEquality() {
        var state1 = NavState()
        state1.heading = 90.0
        state1.speed = 1.5

        var state2 = NavState()
        state2.heading = 90.0
        state2.speed = 1.5

        XCTAssertEqual(state1, state2)

        state2.heading = 91.0
        XCTAssertNotEqual(state1, state2)
    }

    func testNavPoseConstruction() {
        let coord = CLLocationCoordinate2D(latitude: 30.0, longitude: -97.0)
        let pose = NavPose(coordinate: coord, heading: 180.0, speed: 2.5)

        XCTAssertEqual(pose.coordinate.latitude, 30.0, accuracy: 1e-10)
        XCTAssertEqual(pose.heading, 180.0)
        XCTAssertEqual(pose.speed, 2.5)
    }

    func testCelestialFallbackModes() {
        XCTAssertEqual(CelestialFallback.none.rawValue, "none")
        XCTAssertEqual(CelestialFallback.sunOnly.rawValue, "sunOnly")
        XCTAssertEqual(CelestialFallback.magFallback.rawValue, "magFallback")
        XCTAssertEqual(CelestialFallback.gyroOnly.rawValue, "gyroOnly")
    }

    func testActivityLevels() {
        XCTAssertEqual(ActivityLevel.allCases.count, 5)
        XCTAssertTrue(ActivityLevel.allCases.contains(.rest))
        XCTAssertTrue(ActivityLevel.allCases.contains(.extreme))
    }

    // MARK: - W2: LOS / Viewshed

    func testElevationProfilePointStructure() {
        let point = ElevationProfilePoint(
            distance: 500.0,
            terrainElevation: 200.0,
            losHeight: 210.0,
            isBlocked: false
        )
        XCTAssertEqual(point.distance, 500.0)
        XCTAssertFalse(point.isBlocked)
    }

    func testViewshedResultStructure() {
        let coord = CLLocationCoordinate2D(latitude: 30.0, longitude: -97.0)
        let visibility = [Float](repeating: 1.0, count: 360 * 200)
        let result = ViewshedResult(
            observer: coord,
            radius: 2000,
            resolution: 360,
            samplesPerRadial: 200,
            visibility: visibility,
            computeTimeMs: 50.0
        )

        XCTAssertEqual(result.resolution, 360)
        XCTAssertEqual(result.samplesPerRadial, 200)
        XCTAssertEqual(result.visibility.count, 72000)
        XCTAssertEqual(result.computeTimeMs, 50.0)
    }

    func testCelestialOverlayData() {
        let overlay = CelestialOverlayData(
            sunAzimuth: 180.0,
            sunAltitude: 45.0,
            moonAzimuth: nil,
            moonAltitude: nil,
            detectedStarPositions: [(x: 100.0, y: 200.0)],
            timestamp: Date()
        )

        XCTAssertEqual(overlay.sunAzimuth, 180.0)
        XCTAssertEqual(overlay.sunAltitude, 45.0)
        XCTAssertNil(overlay.moonAzimuth)
    }

    // MARK: - W3: Services

    func testNavLogEntryCodable() throws {
        let trail = [
            NavTrailPoint(coordinate: .init(latitude: 30.0, longitude: -97.0), altitude: 100, timestamp: 0, uncertainty: 5),
            NavTrailPoint(coordinate: .init(latitude: 30.001, longitude: -97.001), altitude: 105, timestamp: 10, uncertainty: 4)
        ]

        let entry = NavLogEntry(
            id: UUID(),
            timestamp: Date(),
            trail: trail,
            viewshedData: nil,
            batteryTrend: 0.1,
            totalDistance: 157.0,
            duration: 600,
            zuptCount: 25,
            canopyPercentage: 0.3
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(NavLogEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.trail.count, 2)
        XCTAssertEqual(decoded.zuptCount, 25)
        XCTAssertEqual(decoded.canopyPercentage, 0.3, accuracy: 1e-10)
    }

    func testViewshedCompression() {
        // Create test visibility data
        var visibility = [Float](repeating: 0, count: 1000)
        for i in stride(from: 0, to: 1000, by: 2) {
            visibility[i] = 1.0
        }

        // Compress
        guard let compressed = NavLogStore.compressViewshed(visibility) else {
            XCTFail("Compression failed")
            return
        }

        // Compressed should be smaller than original
        let originalSize = visibility.count * MemoryLayout<Float>.stride
        XCTAssertLessThan(compressed.count, originalSize)

        // Decompress
        guard let decompressed = NavLogStore.decompressViewshed(compressed, expectedCount: 1000) else {
            XCTFail("Decompression failed")
            return
        }

        XCTAssertEqual(decompressed.count, visibility.count)
        for i in 0..<visibility.count {
            XCTAssertEqual(decompressed[i], visibility[i], accuracy: 1e-6)
        }
    }

    func testDroneTelemetryCodable() throws {
        let telemetry = DroneTelemetry(
            id: "drone001",
            latitude: 30.2672,
            longitude: -97.7431,
            altitudeAGL: 50.0,
            batteryPercent: 85,
            heading: 270.0,
            speed: 12.5,
            status: .flying,
            timestamp: Date()
        )

        let data = try JSONEncoder().encode(telemetry)
        let decoded = try JSONDecoder().decode(DroneTelemetry.self, from: data)

        XCTAssertEqual(decoded.id, "drone001")
        XCTAssertEqual(decoded.status, .flying)
        XCTAssertEqual(decoded.altitudeAGL, 50.0)
        XCTAssertEqual(decoded.batteryPercent, 85)
    }

    func testDroneStatusRawValues() {
        XCTAssertEqual(DroneStatus.idle.rawValue, 0)
        XCTAssertEqual(DroneStatus.flying.rawValue, 1)
        XCTAssertEqual(DroneStatus.returning.rawValue, 2)
        XCTAssertEqual(DroneStatus.landing.rawValue, 3)
        XCTAssertEqual(DroneStatus.emergency.rawValue, 4)
    }

    func testHydrationCalculation() {
        let forecaster = WeatherForecaster()

        // Rest in cool weather
        let coolRest = forecaster.calculateHydration(tempC: 15, activityLevel: .rest, durationHours: 1)
        XCTAssertGreaterThan(coolRest, 0)
        XCTAssertLessThan(coolRest, 500)

        // Heavy activity in heat
        let hotHeavy = forecaster.calculateHydration(tempC: 35, activityLevel: .heavy, durationHours: 1)
        XCTAssertGreaterThan(hotHeavy, coolRest)
        XCTAssertGreaterThan(hotHeavy, 1000)  // Should recommend >1L/hr

        // Extreme heat extreme activity
        let extreme = forecaster.calculateHydration(tempC: 40, activityLevel: .extreme, durationHours: 2)
        XCTAssertGreaterThan(extreme, hotHeavy)
    }

    func testPressureAltitude() {
        let forecaster = WeatherForecaster()

        // Standard atmosphere at sea level
        let seaLevel = forecaster.pressureAltitude(pressureHPa: 1013.25)
        XCTAssertEqual(seaLevel, 0, accuracy: 1.0)

        // Lower pressure = higher altitude
        let higher = forecaster.pressureAltitude(pressureHPa: 900.0)
        XCTAssertGreaterThan(higher, 0)
        XCTAssertGreaterThan(higher, 500)  // ~1000m

        // Higher pressure = negative altitude (below sea level datum)
        let lower = forecaster.pressureAltitude(pressureHPa: 1050.0)
        XCTAssertLessThan(lower, 0)
    }
}
