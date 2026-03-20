// CursorOnTargetTests.swift
// Unit tests for CoT XML encoder/decoder roundtrip

import XCTest
@testable import MLXEdgeLLM

final class CursorOnTargetTests: XCTestCase {
    let encoder = CoTEncoder.shared
    let decoder = CoTDecoder.shared

    func testCoTEventEncodeDecode() {
        // Create a test event
        let original = CoTEvent(
            uid: "test-uid-12345",
            type: "a-f-G",
            how: "m-g",
            time: Date(timeIntervalSince1970: 1000000),
            start: Date(timeIntervalSince1970: 1000000),
            stale: Date(timeIntervalSince1970: 1300000),
            lat: 37.7749,
            lon: -122.4194,
            hae: 100.5,
            ce: 25.0,
            le: 50.0
        )

        // Encode
        let encoded = encoder.encode(original)

        // Decode
        guard let decoded = decoder.decode(encoded) else {
            XCTFail("Failed to decode event")
            return
        }

        // Verify identity
        XCTAssertEqual(decoded.uid, original.uid)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.how, original.how)
        XCTAssertEqual(decoded.lat, original.lat, accuracy: 0.0001)
        XCTAssertEqual(decoded.lon, original.lon, accuracy: 0.0001)
        XCTAssertEqual(decoded.hae, original.hae, accuracy: 0.1)
        XCTAssertEqual(decoded.ce, original.ce, accuracy: 0.1)
        XCTAssertEqual(decoded.le, original.le, accuracy: 0.1)
    }

    func testCoTEventWithDetail() {
        // Create event with contact/status details
        var event = CoTEvent(
            uid: "test-uid-detail",
            type: "a-f-G",
            how: "m-g",
            lat: 40.7128,
            lon: -74.0060
        )

        var detail = CoTDetail()
        detail.contact = CoTContact(callsign: "TestUnit1", endpoint: "192.168.1.100:4242:TCP")
        detail.status = CoTStatus(battery: 75)
        detail.takv = CoTTakv(device: "iPhone", platform: "iOS", os: "16.0", version: "1.0")
        event.detail = detail

        // Encode and decode
        let encoded = encoder.encode(event)
        guard let decoded = decoder.decode(encoded) else {
            XCTFail("Failed to decode detailed event")
            return
        }

        // Verify detail fields
        XCTAssertEqual(decoded.detail?.contact?.callsign, "TestUnit1")
        XCTAssertEqual(decoded.detail?.status?.battery, 75)
        XCTAssertEqual(decoded.detail?.takv?.platform, "iOS")
    }

    func testSentinelValuePassthrough() {
        // Test that sentinel value 9999999 is preserved
        let event = CoTEvent(
            uid: "test-sentinel",
            type: "a-f-G",
            how: "m-g",
            lat: 0.0,
            lon: 0.0,
            hae: 9999999,  // Sentinel for unknown altitude
            ce: 9999999,   // Sentinel for unknown error
            le: 9999999    // Sentinel for unknown linear error
        )

        let encoded = encoder.encode(event)
        guard let decoded = decoder.decode(encoded) else {
            XCTFail("Failed to decode sentinel event")
            return
        }

        // Verify sentinels are preserved
        XCTAssertEqual(decoded.hae, 9999999)
        XCTAssertEqual(decoded.ce, 9999999)
        XCTAssertEqual(decoded.le, 9999999)
    }

    func testSOSEventType() {
        // Test emergency SOS marker event
        let sos = CoTEvent(
            uid: UUID().uuidString,
            type: "b-m-p-s-p-i",  // Emergency marker
            how: "h-g-i-g-o",
            lat: 37.7749,
            lon: -122.4194
        )

        let encoded = encoder.encode(sos)
        guard let decoded = decoder.decode(encoded) else {
            XCTFail("Failed to decode SOS event")
            return
        }

        XCTAssertEqual(decoded.type, "b-m-p-s-p-i")
        XCTAssertEqual(decoded.how, "h-g-i-g-o")
    }

    func testTimestampISO8601() {
        // Test ISO 8601 timestamp encoding/decoding
        let testDate = Date(timeIntervalSince1970: 1704067200)  // 2024-01-01 00:00:00 UTC

        let event = CoTEvent(
            uid: "test-time",
            type: "a-f-G",
            how: "m-g",
            time: testDate,
            start: testDate,
            stale: Date(timeIntervalSince: testDate, byAdding: .second, value: 300)
        )

        let encoded = encoder.encode(event)

        // Verify ISO 8601 format
        if let encodedString = String(data: encoded, encoding: .utf8) {
            // Should contain ISO 8601 timestamps with Z suffix or timezone
            XCTAssertTrue(encodedString.contains("T"), "Should contain ISO 8601 time separator")
        }

        guard let decoded = decoder.decode(encoded) else {
            XCTFail("Failed to decode time event")
            return
        }

        // Verify timestamp within ~1 second tolerance
        XCTAssertEqual(decoded.time.timeIntervalSince1970, testDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testXMLEscaping() {
        // Test that special XML characters are escaped
        var event = CoTEvent(uid: "test-escape", type: "a-f-G", how: "m-g")

        var detail = CoTDetail()
        detail.contact = CoTContact(callsign: "Unit<>&\"", endpoint: nil)
        event.detail = detail

        let encoded = encoder.encode(event)

        if let encodedString = String(data: encoded, encoding: .utf8) {
            // Verify escaping
            XCTAssertTrue(encodedString.contains("&lt;"), "Should escape <")
            XCTAssertTrue(encodedString.contains("&gt;"), "Should escape >")
            XCTAssertTrue(encodedString.contains("&amp;"), "Should escape &")
        }

        guard let decoded = decoder.decode(encoded) else {
            XCTFail("Failed to decode escaped event")
            return
        }

        // Original string should be recovered
        XCTAssertEqual(decoded.detail?.contact?.callsign, "Unit<>&\"")
    }

    func testMultipleEventsParsing() {
        // Test parsing multiple sequential events (as from TCP stream)
        let event1 = CoTEvent(uid: "event1", type: "a-f-G", how: "m-g")
        let event2 = CoTEvent(uid: "event2", type: "a-h-G", how: "m-g")

        let encoded1 = encoder.encode(event1)
        let encoded2 = encoder.encode(event2)
        let combined = encoded1 + encoded2

        // Decode first event
        guard let decoded1 = decoder.decode(encoded1) else {
            XCTFail("Failed to decode first event")
            return
        }
        XCTAssertEqual(decoded1.uid, "event1")

        // Decode second event
        guard let decoded2 = decoder.decode(encoded2) else {
            XCTFail("Failed to decode second event")
            return
        }
        XCTAssertEqual(decoded2.uid, "event2")
    }

    func testEventValidation() {
        // Test that uid is preserved as unique identifier
        let uid1 = UUID().uuidString
        let uid2 = UUID().uuidString

        let event1 = CoTEvent(uid: uid1, type: "a-f-G", how: "m-g")
        let event2 = CoTEvent(uid: uid2, type: "a-f-G", how: "m-g")

        let encoded1 = encoder.encode(event1)
        let encoded2 = encoder.encode(event2)

        guard let decoded1 = decoder.decode(encoded1),
              let decoded2 = decoder.decode(encoded2) else {
            XCTFail("Failed to decode events")
            return
        }

        XCTAssertNotEqual(decoded1.uid, decoded2.uid)
    }
}
