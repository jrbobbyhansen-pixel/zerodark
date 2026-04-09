// MeshRelayTests.swift — Tests for MeshRelay, OpSec geofence deny, protobuf parsing
// BUILD_SPEC v6.2 test coverage

import XCTest
import CoreLocation
@testable import MLXEdgeLLM

final class MeshRelayTests: XCTestCase {

    // MARK: - Protobuf Helpers

    func testEncodeDecodeVarint() {
        let values: [UInt64] = [0, 1, 127, 128, 300, 16384, 0xFFFFFFFF, 0x7FFFFFFFFFFFFFFF]
        for value in values {
            let encoded = pbEncodeVarint(value)
            let bytes = [UInt8](encoded)
            let decoded = pbReadVarint(bytes, offset: 0)
            XCTAssertNotNil(decoded, "Failed to decode varint for value \(value)")
            XCTAssertEqual(decoded!.0, value, "Varint roundtrip failed for \(value)")
        }
    }

    func testReadFieldHeader() {
        // Field tag=1, wireType=0 (varint) → byte = (1 << 3) | 0 = 0x08
        let bytes: [UInt8] = [0x08]
        let result = pbReadFieldHeader(bytes, offset: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.tag, 1)
        XCTAssertEqual(result!.wireType, 0)
        XCTAssertEqual(result!.headerLen, 1)
    }

    func testReadFieldHeaderLengthDelimited() {
        // Field tag=2, wireType=2 (length-delimited) → byte = (2 << 3) | 2 = 0x12
        let bytes: [UInt8] = [0x12]
        let result = pbReadFieldHeader(bytes, offset: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.tag, 2)
        XCTAssertEqual(result!.wireType, 2)
    }

    func testEncodeStringField() {
        let data = pbEncodeStringField(tag: 1, value: "hello")
        let bytes = [UInt8](data)
        // tag=1, wireType=2 → 0x0A, length=5 → 0x05, then "hello"
        XCTAssertEqual(bytes[0], 0x0A)
        XCTAssertEqual(bytes[1], 5)
        XCTAssertEqual(String(bytes: Array(bytes[2...]), encoding: .utf8), "hello")
    }

    func testEncodeVarintField() {
        let data = pbEncodeVarintField(tag: 1, value: 42)
        let bytes = [UInt8](data)
        // tag=1, wireType=0 → 0x08, value=42 → 0x2A
        XCTAssertEqual(bytes[0], 0x08)
        XCTAssertEqual(bytes[1], 42)
    }

    // MARK: - Protobuf Position Parsing

    func testParseProtobufPosition() {
        // Construct a minimal protobuf with position data
        // Position: lat=30.0, lon=-97.0 → latI=300000000, lonI=-970000000
        let latI = Int32(30.0 * 1e7)
        let lonI = Int32(-97.0 * 1e7)

        // Build position payload: field 1 = lat (varint), field 2 = lon (varint)
        var posPayload = Data()
        posPayload.append(contentsOf: pbEncodeVarintField(tag: 1, value: UInt64(bitPattern: Int64(latI))))
        posPayload.append(contentsOf: pbEncodeVarintField(tag: 2, value: UInt64(bitPattern: Int64(lonI))))

        // Build data message: field 1 = portnum 1 (POSITION_APP), field 2 = payload
        var dataMsg = Data()
        dataMsg.append(contentsOf: pbEncodeVarintField(tag: 1, value: 1)) // portnum = POSITION_APP
        dataMsg.append(contentsOf: pbEncodeBytesField(tag: 2, value: posPayload))

        // Build mesh packet: field 1 = from nodeId, field 6 = decoded data
        var meshPacket = Data()
        meshPacket.append(contentsOf: pbEncodeVarintField(tag: 1, value: 0x12345678))
        meshPacket.append(contentsOf: pbEncodeBytesField(tag: 6, value: dataMsg))

        // Build fromRadio: field 3 = mesh packet
        var fromRadio = Data()
        fromRadio.append(contentsOf: pbEncodeBytesField(tag: 3, value: meshPacket))

        // Parse
        let relay = MeshRelay.shared
        let peers = relay.parseProtobuf(fromRadio)

        XCTAssertNotNil(peers)
        XCTAssertEqual(peers!.count, 1)

        let peer = peers!.first!
        XCTAssertEqual(peer.id, "12345678")
        XCTAssertEqual(peer.location!.latitude, 30.0, accuracy: 0.0001)
        XCTAssertEqual(peer.location!.longitude, -97.0, accuracy: 0.0001)
    }

    // MARK: - TAK CoT Parsing

    func testParseTAKCoTToPeer() {
        let cotXML = """
        <?xml version='1.0' encoding='UTF-8' standalone='yes'?>
        <event version="2.0" uid="test-uid-123" type="a-f-G" time="2026-04-07T00:00:00.000Z" start="2026-04-07T00:00:00.000Z" stale="2026-04-07T00:05:00.000Z" how="m-g">
          <point lat="30.26750000" lon="-97.74310000" hae="9999999" ce="9999999" le="9999999"/>
          <detail>
            <contact callsign="ALPHA-1"/>
            <status battery="85"/>
          </detail>
        </event>
        """

        let relay = MeshRelay.shared
        let peer = relay.parseTAKCoT(cotXML.data(using: .utf8)!)

        XCTAssertNotNil(peer)
        XCTAssertEqual(peer!.id, "test-uid-123")
        XCTAssertEqual(peer!.name, "ALPHA-1")
        XCTAssertEqual(peer!.batteryLevel, 85)
        XCTAssertEqual(peer!.location!.latitude, 30.2675, accuracy: 0.001)
        XCTAssertEqual(peer!.location!.longitude, -97.7431, accuracy: 0.001)
        XCTAssertEqual(peer!.status, .online)
    }

    func testParseTAKCoTSOSType() {
        let cotXML = """
        <?xml version='1.0' encoding='UTF-8' standalone='yes'?>
        <event version="2.0" uid="sos-123" type="b-a-o-tbl-sos" time="2026-04-07T00:00:00.000Z" start="2026-04-07T00:00:00.000Z" stale="2026-04-07T00:05:00.000Z" how="m-g">
          <point lat="30.0" lon="-97.0" hae="9999999" ce="9999999" le="9999999"/>
        </event>
        """

        let relay = MeshRelay.shared
        let peer = relay.parseTAKCoT(cotXML.data(using: .utf8)!)

        XCTAssertNotNil(peer)
        XCTAssertEqual(peer!.status, .sos)
    }

    // MARK: - OpSec Geofence Check

    func testOpSecCheckAllowInZone() {
        let manager = GeofenceManager.shared

        // Clear existing and add a keep-in geofence centered at Austin
        let austinCenter = CodableCoordinate(latitude: 30.2672, longitude: -97.7431)
        let geofence = Geofence(name: "AO", type: "keep-in", geometry: .circle(center: austinCenter, radiusMeters: 50000))
        manager.geofences = [geofence]

        let peer = ZDPeer(
            id: "test-in",
            name: "InZone",
            lastSeen: Date(),
            location: CLLocationCoordinate2D(latitude: 30.27, longitude: -97.74),
            batteryLevel: 80,
            status: .online
        )

        let relay = MeshRelay.shared
        XCTAssertTrue(relay.opSecCheck(peer: peer), "Peer inside keep-in zone should be allowed")

        // Cleanup
        manager.geofences = []
    }

    func testOpSecCheckDenyOutOfZone() {
        let manager = GeofenceManager.shared

        let austinCenter = CodableCoordinate(latitude: 30.2672, longitude: -97.7431)
        let geofence = Geofence(name: "AO", type: "keep-in", geometry: .circle(center: austinCenter, radiusMeters: 1000))
        manager.geofences = [geofence]

        // Peer far outside the zone (Houston)
        let peer = ZDPeer(
            id: "test-out",
            name: "OutOfZone",
            lastSeen: Date(),
            location: CLLocationCoordinate2D(latitude: 29.7604, longitude: -95.3698),
            batteryLevel: 50,
            status: .online
        )

        let relay = MeshRelay.shared
        XCTAssertFalse(relay.opSecCheck(peer: peer), "Peer outside keep-in zone should be denied")

        manager.geofences = []
    }

    func testOpSecCheckKeepOut() {
        let manager = GeofenceManager.shared

        let restrictedCenter = CodableCoordinate(latitude: 30.2672, longitude: -97.7431)
        let geofence = Geofence(name: "Restricted", type: "keep-out", geometry: .circle(center: restrictedCenter, radiusMeters: 50000))
        manager.geofences = [geofence]

        // Peer inside keep-out zone
        let peer = ZDPeer(
            id: "test-keepout",
            name: "InRestricted",
            lastSeen: Date(),
            location: CLLocationCoordinate2D(latitude: 30.27, longitude: -97.74),
            batteryLevel: 90,
            status: .online
        )

        let relay = MeshRelay.shared
        XCTAssertFalse(relay.opSecCheck(peer: peer), "Peer inside keep-out zone should be denied")

        manager.geofences = []
    }

    func testOpSecCheckNoGeofences() {
        let manager = GeofenceManager.shared
        manager.geofences = []

        let peer = ZDPeer(
            id: "test-nofence",
            name: "AnyPeer",
            lastSeen: Date(),
            location: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            batteryLevel: 100,
            status: .online
        )

        let relay = MeshRelay.shared
        XCTAssertTrue(relay.opSecCheck(peer: peer), "No geofences should allow all peers")
    }

    func testOpSecCheckNilLocation() {
        let manager = GeofenceManager.shared
        let center = CodableCoordinate(latitude: 30.0, longitude: -97.0)
        manager.geofences = [Geofence(name: "AO", type: "keep-in", geometry: .circle(center: center, radiusMeters: 1000))]

        let peer = ZDPeer(
            id: "test-nil",
            name: "NoLocation",
            lastSeen: Date(),
            location: nil,
            batteryLevel: 50,
            status: .online
        )

        let relay = MeshRelay.shared
        XCTAssertFalse(relay.opSecCheck(peer: peer), "Peer with nil location should be denied when geofences active")

        manager.geofences = []
    }

    // MARK: - CoT → Protobuf Roundtrip

    func testCoTToProtobufRoundtrip() {
        let event = CoTEvent(
            uid: "roundtrip-123",
            type: "a-f-G",
            how: "m-g",
            lat: 30.2672,
            lon: -97.7431,
            detail: CoTDetail(
                contact: CoTContact(callsign: "BRAVO-2", endpoint: nil),
                status: CoTStatus(battery: 75)
            )
        )

        let relay = MeshRelay.shared
        let protobufData = relay.cotToProtobuf(event)

        XCTAssertFalse(protobufData.isEmpty, "Protobuf encoding should produce data")
        XCTAssertTrue(protobufData.count < 200, "Protobuf should be compact (got \(protobufData.count) bytes)")

        // Verify the protobuf contains expected field tags
        let bytes = [UInt8](protobufData)
        var offset = 0
        var foundUID = false
        var foundLat = false

        while offset < bytes.count {
            guard let (tag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen

            if tag == 1 && wireType == 2 { foundUID = true }
            if tag == 2 && wireType == 0 { foundLat = true }

            if let skip = pbSkipField(bytes, offset: offset, wireType: wireType) {
                offset += skip
            } else { break }
        }

        XCTAssertTrue(foundUID, "Protobuf should contain UID field (tag 1)")
        XCTAssertTrue(foundLat, "Protobuf should contain lat field (tag 2)")
    }

    // MARK: - Performance

    func testRelay50PeersUnder100ms() {
        let manager = GeofenceManager.shared
        let center = CodableCoordinate(latitude: 30.2672, longitude: -97.7431)
        manager.geofences = [
            Geofence(name: "AO", type: "keep-in", geometry: .circle(center: center, radiusMeters: 100000)),
            Geofence(name: "Restricted", type: "keep-out", geometry: .circle(
                center: CodableCoordinate(latitude: 31.0, longitude: -97.0), radiusMeters: 5000
            ))
        ]

        // Generate 50 peers
        let peers = (0..<50).map { i in
            ZDPeer(
                id: "perf-\(i)",
                name: "Peer-\(i)",
                lastSeen: Date(),
                location: CLLocationCoordinate2D(
                    latitude: 30.2672 + Double(i) * 0.001,
                    longitude: -97.7431 + Double(i) * 0.001
                ),
                batteryLevel: 50 + (i % 50),
                status: .online
            )
        }

        let relay = MeshRelay.shared

        measure {
            for peer in peers {
                _ = relay.opSecCheck(peer: peer)
            }
        }

        // Verify correctness
        let startTime = Date()
        for peer in peers {
            _ = relay.opSecCheck(peer: peer)
        }
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 0.1, "50 peer OpSec checks should complete in under 100ms (took \(elapsed * 1000)ms)")

        manager.geofences = []
    }

    // MARK: - GeofenceManager Relay Methods

    func testGeofenceManagerShouldAllowRelayNilLocation() {
        let manager = GeofenceManager.shared
        let center = CodableCoordinate(latitude: 30.0, longitude: -97.0)
        manager.geofences = [Geofence(name: "Test", type: "keep-in", geometry: .circle(center: center, radiusMeters: 1000))]

        XCTAssertFalse(manager.shouldAllowRelay(to: nil), "Nil location should be denied")

        manager.geofences = []
    }

    func testGeofenceManagerIsOutOfZone() {
        let manager = GeofenceManager.shared
        let center = CodableCoordinate(latitude: 30.0, longitude: -97.0)
        manager.geofences = [Geofence(name: "AO", type: "keep-in", geometry: .circle(center: center, radiusMeters: 1000))]

        let inZone = CodableCoordinate(latitude: 30.0, longitude: -97.0)
        XCTAssertFalse(manager.isOutOfZone(coordinate: inZone))

        let outZone = CodableCoordinate(latitude: 35.0, longitude: -90.0)
        XCTAssertTrue(manager.isOutOfZone(coordinate: outZone))

        manager.geofences = []
    }
}
