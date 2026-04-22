// DeepLinkRouterTests.swift — Coverage for PR-C4 URL-scheme parsing.

import XCTest
import CoreLocation
@testable import ZeroDark

final class DeepLinkRouterTests: XCTestCase {

    func test_foreignScheme_isNone() {
        let url = URL(string: "https://example.com/map")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .none)
    }

    func test_unknownHost_isNone() {
        let url = URL(string: "zerodark://quokka")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .none)
    }

    func test_map_withFullCoordinates() {
        let url = URL(string: "zerodark://map?lat=35.2&lon=-118.5&zoom=12")!
        let result = DeepLinkRouter.parse(url)
        guard case let .openMap(center, zoom) = result else {
            return XCTFail("expected .openMap, got \(result)")
        }
        XCTAssertEqual(center?.latitude, 35.2)
        XCTAssertEqual(center?.longitude, -118.5)
        XCTAssertEqual(zoom, 12)
    }

    func test_map_withoutCoordinates_returnsNilCenter() {
        let url = URL(string: "zerodark://map")!
        let result = DeepLinkRouter.parse(url)
        guard case let .openMap(center, zoom) = result else {
            return XCTFail("expected .openMap")
        }
        XCTAssertNil(center)
        XCTAssertNil(zoom)
    }

    func test_lidarScan_withValidUUID() {
        let id = UUID()
        let url = URL(string: "zerodark://lidar/scan/\(id.uuidString)")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .openLiDARScan(id: id))
    }

    func test_lidarScan_withInvalidUUID_isNone() {
        let url = URL(string: "zerodark://lidar/scan/not-a-uuid")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .none)
    }

    func test_meshPeer_callsign() {
        let url = URL(string: "zerodark://mesh/peer/BRAVO-7")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .openMeshPeer(callsign: "BRAVO-7"))
    }

    func test_meshPeer_missingCallsign_isNone() {
        let url = URL(string: "zerodark://mesh/peer/")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .none)
    }

    func test_ops_topLevel() {
        let url = URL(string: "zerodark://ops")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .openOps)
    }

    func test_intel_withMode() {
        let url = URL(string: "zerodark://intel?mode=knowledge")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .openIntel(mode: "knowledge"))
    }

    func test_intel_noMode_returnsNilMode() {
        let url = URL(string: "zerodark://intel")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .openIntel(mode: nil))
    }

    func test_nav_topLevel() {
        let url = URL(string: "zerodark://nav")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .openNav)
    }

    func test_caseInsensitiveScheme() {
        let url = URL(string: "ZERODARK://ops")!
        XCTAssertEqual(DeepLinkRouter.parse(url), .openOps)
    }
}
