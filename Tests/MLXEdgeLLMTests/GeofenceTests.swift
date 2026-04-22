// GeofenceTests.swift — Pure-logic coverage for Geofence.contains +
// distanceToBoundary. Focuses on the NASA ICAROUS / PolyCARP pattern: a
// miscoded point-in-polygon is a real safety hazard for keep-in/keep-out
// zones, so these tests pin the containment algorithm to known values.

import XCTest
import CoreLocation
@testable import ZeroDark

final class GeofenceTests: XCTestCase {

    // MARK: - Circle

    func test_circle_containsCenter() {
        let center = CodableCoordinate(latitude: 37.7793, longitude: -122.4192)
        let fence = Geofence(name: "SF", type: "keep-in",
                             geometry: .circle(center: center, radiusMeters: 500))
        XCTAssertTrue(fence.contains(center))
    }

    func test_circle_excludesFarPoint() {
        let center = CodableCoordinate(latitude: 37.7793, longitude: -122.4192)
        let farAway = CodableCoordinate(latitude: 33.9416, longitude: -118.4085) // LAX
        let fence = Geofence(name: "SF", type: "keep-in",
                             geometry: .circle(center: center, radiusMeters: 5_000))
        XCTAssertFalse(fence.contains(farAway))
    }

    func test_circle_distanceToBoundary_negativeInside() {
        let center = CodableCoordinate(latitude: 0, longitude: 0)
        let fence = Geofence(name: "z", type: "keep-in",
                             geometry: .circle(center: center, radiusMeters: 1_000))
        // ~0 distance from center → -radius
        let d = fence.distanceToBoundary(center)
        XCTAssertLessThan(d, 0, "center should be deep inside")
        XCTAssertEqual(d, -1_000, accuracy: 5)
    }

    // MARK: - Polygon (ray casting)

    func test_polygon_squareContainsCenter() {
        let square: [CodableCoordinate] = [
            .init(latitude: 0, longitude: 0),
            .init(latitude: 0, longitude: 1),
            .init(latitude: 1, longitude: 1),
            .init(latitude: 1, longitude: 0)
        ]
        let fence = Geofence(name: "sq", type: "keep-in", geometry: .polygon(coordinates: square))
        let middle = CodableCoordinate(latitude: 0.5, longitude: 0.5)
        XCTAssertTrue(fence.contains(middle))
    }

    func test_polygon_squareExcludesExterior() {
        let square: [CodableCoordinate] = [
            .init(latitude: 0, longitude: 0),
            .init(latitude: 0, longitude: 1),
            .init(latitude: 1, longitude: 1),
            .init(latitude: 1, longitude: 0)
        ]
        let fence = Geofence(name: "sq", type: "keep-in", geometry: .polygon(coordinates: square))
        let outside = CodableCoordinate(latitude: 2, longitude: 2)
        XCTAssertFalse(fence.contains(outside))
    }

    func test_polygon_concave_handlesCorrectly() {
        // L-shape — concave polygon. The point (0.5, 0.5) is outside the L's cutout.
        //    (0,0)   (0,2)
        //       +---+
        //       |   |
        //       |   +---+ (1,3)
        //       |       |
        //       +-------+ (2,3)
        //     (2,0)
        let lShape: [CodableCoordinate] = [
            .init(latitude: 0, longitude: 0),
            .init(latitude: 0, longitude: 2),
            .init(latitude: 1, longitude: 2),
            .init(latitude: 1, longitude: 3),
            .init(latitude: 2, longitude: 3),
            .init(latitude: 2, longitude: 0)
        ]
        let fence = Geofence(name: "L", type: "keep-in", geometry: .polygon(coordinates: lShape))
        // Point in the arm — inside
        XCTAssertTrue(fence.contains(.init(latitude: 1.5, longitude: 2.5)))
        // Point in the notch — outside
        XCTAssertFalse(fence.contains(.init(latitude: 0.5, longitude: 2.5)))
    }

    // MARK: - Codable round-trip

    func test_geofence_codable_roundtrip_circle() throws {
        let fence = Geofence(
            name: "rt",
            type: "alert",
            geometry: .circle(center: .init(latitude: 1, longitude: 2), radiusMeters: 100)
        )
        let data = try JSONEncoder().encode(fence)
        let back = try JSONDecoder().decode(Geofence.self, from: data)
        XCTAssertEqual(back.name, fence.name)
        XCTAssertEqual(back.type, fence.type)
        if case .circle(_, let r) = back.geometry {
            XCTAssertEqual(r, 100)
        } else {
            XCTFail("expected circle geometry")
        }
    }

    func test_geofence_codable_roundtrip_polygon() throws {
        let poly: [CodableCoordinate] = [
            .init(latitude: 0, longitude: 0),
            .init(latitude: 0, longitude: 1),
            .init(latitude: 1, longitude: 1)
        ]
        let fence = Geofence(name: "tri", type: "keep-out", geometry: .polygon(coordinates: poly))
        let data = try JSONEncoder().encode(fence)
        let back = try JSONDecoder().decode(Geofence.self, from: data)
        if case .polygon(let coords) = back.geometry {
            XCTAssertEqual(coords.count, 3)
        } else {
            XCTFail("expected polygon geometry")
        }
    }
}
