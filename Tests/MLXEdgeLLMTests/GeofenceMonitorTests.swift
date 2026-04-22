// GeofenceMonitorTests.swift — Coverage for PR-C10 hysteresis dead-band.
//
// Tests the pure `filterWithHysteresis` pathway. Does not touch
// CLLocationManager — that needs a real device authorization flow.

import XCTest
import CoreLocation
@testable import ZeroDark

@MainActor
final class GeofenceMonitorTests: XCTestCase {

    override func setUp() async throws {
        GeofenceMonitor.shared.resetHysteresis()
        GeofenceMonitor.shared.hysteresisMeters = 10.0
    }

    private func makeViolation(id: UUID = UUID(),
                               name: String = "KeepOut",
                               type: String = "entry") -> GeofenceViolation {
        GeofenceViolation(
            geofenceID: id,
            geofenceName: name,
            timestamp: Date(),
            coordinate: .init(latitude: 0, longitude: 0),
            violationType: type
        )
    }

    func test_firstViolation_alwaysSurfaced() {
        let v = makeViolation()
        let here = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        let out = GeofenceMonitor.shared.filterWithHysteresis([v], here: here)
        XCTAssertEqual(out.count, 1)
    }

    func test_secondViolation_withinDeadband_isSuppressed() {
        let v = makeViolation()
        let here = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        _ = GeofenceMonitor.shared.filterWithHysteresis([v], here: here)

        // Second location ~2m away — inside the 10m dead-band.
        let jitter = CLLocationCoordinate2D(latitude: 40.000018, longitude: -100)
        let out = GeofenceMonitor.shared.filterWithHysteresis([v], here: jitter)
        XCTAssertTrue(out.isEmpty)
    }

    func test_violation_outsideDeadband_surfacesAgain() {
        let v = makeViolation()
        let here = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        _ = GeofenceMonitor.shared.filterWithHysteresis([v], here: here)

        // Second location ~110m north — outside the 10m dead-band.
        let farther = CLLocationCoordinate2D(latitude: 40.001, longitude: -100)
        let out = GeofenceMonitor.shared.filterWithHysteresis([v], here: farther)
        XCTAssertEqual(out.count, 1)
    }

    func test_differentFence_notSuppressedByAnother() {
        let a = makeViolation(id: UUID(), name: "fenceA")
        let b = makeViolation(id: UUID(), name: "fenceB")
        let here = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        _ = GeofenceMonitor.shared.filterWithHysteresis([a], here: here)
        let out = GeofenceMonitor.shared.filterWithHysteresis([b], here: here)
        XCTAssertEqual(out.count, 1, "second fence should not be suppressed by first")
    }

    func test_differentViolationType_sameFence_notSuppressed() {
        let id = UUID()
        let entry = makeViolation(id: id, type: "entry")
        let exit = makeViolation(id: id, type: "exit")
        let here = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        _ = GeofenceMonitor.shared.filterWithHysteresis([entry], here: here)
        let out = GeofenceMonitor.shared.filterWithHysteresis([exit], here: here)
        XCTAssertEqual(out.count, 1, "exit and entry are distinct events for hysteresis")
    }

    func test_resetHysteresis_reopensEverything() {
        let v = makeViolation()
        let here = CLLocationCoordinate2D(latitude: 40, longitude: -100)
        _ = GeofenceMonitor.shared.filterWithHysteresis([v], here: here)
        GeofenceMonitor.shared.resetHysteresis()
        let out = GeofenceMonitor.shared.filterWithHysteresis([v], here: here)
        XCTAssertEqual(out.count, 1)
    }
}
