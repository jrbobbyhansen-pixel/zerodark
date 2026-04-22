// MGRSGridLinesTests.swift — Coverage for the PR-B6 extraction.
//
// The audit-plan required extracted helpers to be unit-testable without
// SwiftUI or MapKit runtime. These tests pin the spacing ladder and verify
// that gridline counts match what the visible span demands.

import XCTest
import MapKit
import CoreLocation
@testable import ZeroDark

final class MGRSGridLinesTests: XCTestCase {

    // MARK: - Spacing ladder

    func test_spacing_globalView() {
        let region = MKCoordinateRegion(
            center: .init(latitude: 0, longitude: 0),
            span: .init(latitudeDelta: 30, longitudeDelta: 30)
        )
        XCTAssertEqual(MGRSGridLines.spacing(for: region), 6.0)
    }

    func test_spacing_regionalView() {
        let region = MKCoordinateRegion(
            center: .init(latitude: 0, longitude: 0),
            span: .init(latitudeDelta: 5, longitudeDelta: 5)
        )
        XCTAssertEqual(MGRSGridLines.spacing(for: region), 1.0)
    }

    func test_spacing_cityView() {
        let region = MKCoordinateRegion(
            center: .init(latitude: 0, longitude: 0),
            span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        XCTAssertEqual(MGRSGridLines.spacing(for: region), 0.1)
    }

    func test_spacing_tacticalView() {
        let region = MKCoordinateRegion(
            center: .init(latitude: 0, longitude: 0),
            span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        XCTAssertEqual(MGRSGridLines.spacing(for: region), 0.01)
    }

    // MARK: - Polyline geometry

    func test_gridLines_produceBothHorizontalAndVertical() {
        let region = MKCoordinateRegion(
            center: .init(latitude: 35, longitude: -120),
            span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        let lines = MGRSGridLines.gridLines(for: region)
        // Every line is exactly two endpoints (a polyline segment).
        for line in lines {
            XCTAssertEqual(line.count, 2)
        }

        // Some lines are vertical (constant lon); some horizontal (constant lat).
        let verticals   = lines.filter { $0[0].longitude == $0[1].longitude }
        let horizontals = lines.filter { $0[0].latitude  == $0[1].latitude  }
        XCTAssertGreaterThan(verticals.count, 0)
        XCTAssertGreaterThan(horizontals.count, 0)
    }

    func test_gridLines_coverRegion_withSpacingTolerance() {
        // Gridlines are snapped to the spacing ladder (floor-rounded), so
        // their endpoints may sit up to one spacing unit outside the visible
        // region on any side. The overlay still covers the full viewport —
        // MapKit clips to the visible rect.
        let region = MKCoordinateRegion(
            center: .init(latitude: 40, longitude: -100),
            span: .init(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        let lines = MGRSGridLines.gridLines(for: region)
        let spacing = MGRSGridLines.spacing(for: region)
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        for line in lines {
            for pt in line {
                XCTAssertGreaterThanOrEqual(pt.latitude,  minLat - spacing - 1e-6)
                XCTAssertLessThanOrEqual(pt.latitude,     maxLat + spacing + 1e-6)
                XCTAssertGreaterThanOrEqual(pt.longitude, minLon - spacing - 1e-6)
                XCTAssertLessThanOrEqual(pt.longitude,    maxLon + spacing + 1e-6)
            }
        }
        XCTAssertGreaterThan(lines.count, 0)
    }

    func test_gridLineCount_matchesSpacing() {
        // At 0.5° span and 0.1° spacing we expect 6 verticals (at -120.4, -120.3, …, -119.9 + 1) and 6 horizontals, roughly.
        let region = MKCoordinateRegion(
            center: .init(latitude: 35, longitude: -120),
            span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        let lines = MGRSGridLines.gridLines(for: region)
        // Vertical line count: ceil(span / spacing) + 1. Tolerate ±1 for
        // floor-rounding at boundaries.
        let verticals = lines.filter { $0[0].longitude == $0[1].longitude }
        let horizontals = lines.filter { $0[0].latitude == $0[1].latitude }
        XCTAssertTrue((5...7).contains(verticals.count),
                      "expected ~6 verticals, got \(verticals.count)")
        XCTAssertTrue((5...7).contains(horizontals.count),
                      "expected ~6 horizontals, got \(horizontals.count)")
    }
}
