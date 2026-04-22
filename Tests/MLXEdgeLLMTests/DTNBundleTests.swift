// DTNBundleTests.swift — Coverage for the PR-C11 dead-letter additions
// on the DTNBundle value type. The Buffer itself is MainActor + relies
// on Documents I/O, so deeper integration tests would need a temp dir;
// these tests stay at the value-semantics layer.

import XCTest
@testable import ZeroDark

final class DTNBundleTests: XCTestCase {

    func test_newBundle_notDeadLettered() {
        let b = DTNBundle(destination: "peer1", payload: Data("hello".utf8))
        XCTAssertFalse(b.isDeadLettered)
        XCTAssertNil(b.deadLetteredAt)
        XCTAssertNil(b.deadLetterReason)
    }

    func test_setDeadLetter_flagsOn() {
        var b = DTNBundle(destination: "peer1", payload: Data())
        b.deadLetteredAt = Date()
        b.deadLetterReason = "retry_exhausted"
        XCTAssertTrue(b.isDeadLettered)
        XCTAssertEqual(b.deadLetterReason, "retry_exhausted")
    }

    func test_delivered_notDeadLettered() {
        var b = DTNBundle(destination: "peer1", payload: Data())
        b.deliveredAt = Date()
        XCTAssertTrue(b.isDelivered)
        XCTAssertFalse(b.isDeadLettered)
    }

    func test_codable_roundtrip_preservesDeadLetterFields() throws {
        var original = DTNBundle(destination: "peer1", payload: Data("x".utf8))
        original.deadLetteredAt = Date(timeIntervalSince1970: 1_700_000_000)
        original.deadLetterReason = "expired"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DTNBundle.self, from: data)

        XCTAssertTrue(decoded.isDeadLettered)
        XCTAssertEqual(decoded.deadLetterReason, "expired")
        let ts = decoded.deadLetteredAt?.timeIntervalSince1970 ?? 0
        XCTAssertEqual(ts, 1_700_000_000, accuracy: 1)
    }

    func test_isExpired_timeDriven() {
        let b = DTNBundle(destination: "peer", payload: Data(), priority: .normal, ttl: -1)
        XCTAssertTrue(b.isExpired)
    }
}
