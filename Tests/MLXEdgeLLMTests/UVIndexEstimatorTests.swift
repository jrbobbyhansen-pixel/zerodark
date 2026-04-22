// UVIndexEstimatorTests.swift — Coverage for PR-C8 UV estimator.

import XCTest
@testable import ZeroDark

final class UVIndexEstimatorTests: XCTestCase {

    // MARK: - Edge elevations

    func test_sunBelowHorizon_isZero() {
        let e = UVIndexEstimator.estimate(solarElevationDegrees: -10)
        XCTAssertEqual(e.index, 0)
        XCTAssertEqual(e.category, .low)
    }

    func test_sunAtHorizon_isZero() {
        let e = UVIndexEstimator.estimate(solarElevationDegrees: 0)
        XCTAssertEqual(e.index, 0)
    }

    func test_sunOverhead_isExtreme() {
        // 90° elevation, clear sky → peak UV (13 after rounding the 12.5×1).
        let e = UVIndexEstimator.estimate(solarElevationDegrees: 90)
        XCTAssertGreaterThanOrEqual(e.index, 12)
        XCTAssertLessThanOrEqual(e.index, 14)
        XCTAssertEqual(e.category, .extreme)
    }

    // MARK: - Intermediate angles

    func test_sun30Degrees_moderate() {
        // sin(30°) = 0.5 → raw UV = 12.5 × 0.5 = 6.25 → index ≈ 6 → high
        let e = UVIndexEstimator.estimate(solarElevationDegrees: 30)
        XCTAssertEqual(e.index, 6)
        XCTAssertEqual(e.category, .high)
    }

    func test_sun10Degrees_low() {
        let e = UVIndexEstimator.estimate(solarElevationDegrees: 10)
        XCTAssertLessThan(e.index, 3)
        XCTAssertEqual(e.category, .low)
    }

    // MARK: - Cloud-cover attenuation

    func test_cloudCover_reducesIndex() {
        let clear  = UVIndexEstimator.estimate(solarElevationDegrees: 60, cloudCover: 0).index
        let cloudy = UVIndexEstimator.estimate(solarElevationDegrees: 60, cloudCover: 1).index
        XCTAssertGreaterThan(clear, cloudy)
    }

    func test_cloudCover_clampedTo0_1() {
        // Passing 5.0 should be clamped to 1.0 — same result as 1.0.
        let a = UVIndexEstimator.estimate(solarElevationDegrees: 45, cloudCover: 1.0).index
        let b = UVIndexEstimator.estimate(solarElevationDegrees: 45, cloudCover: 5.0).index
        XCTAssertEqual(a, b)

        // Passing -3 should clamp to 0 — same result as 0.
        let c = UVIndexEstimator.estimate(solarElevationDegrees: 45, cloudCover: 0).index
        let d = UVIndexEstimator.estimate(solarElevationDegrees: 45, cloudCover: -3).index
        XCTAssertEqual(c, d)
    }

    // MARK: - Category boundaries

    func test_category_boundaries() {
        XCTAssertEqual(UVIndexEstimator.category(for: 0),  .low)
        XCTAssertEqual(UVIndexEstimator.category(for: 2),  .low)
        XCTAssertEqual(UVIndexEstimator.category(for: 3),  .moderate)
        XCTAssertEqual(UVIndexEstimator.category(for: 5),  .moderate)
        XCTAssertEqual(UVIndexEstimator.category(for: 6),  .high)
        XCTAssertEqual(UVIndexEstimator.category(for: 7),  .high)
        XCTAssertEqual(UVIndexEstimator.category(for: 8),  .veryHigh)
        XCTAssertEqual(UVIndexEstimator.category(for: 10), .veryHigh)
        XCTAssertEqual(UVIndexEstimator.category(for: 11), .extreme)
        XCTAssertEqual(UVIndexEstimator.category(for: 14), .extreme)
    }

    func test_category_displayNames_allPresent() {
        for cat in [UVIndexEstimate.Category.low, .moderate, .high, .veryHigh, .extreme] {
            XCTAssertFalse(cat.displayName.isEmpty)
            XCTAssertFalse(cat.burnRiskHint.isEmpty)
        }
    }
}
