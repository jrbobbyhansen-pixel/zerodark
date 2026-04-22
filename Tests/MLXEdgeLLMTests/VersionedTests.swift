// VersionedTests.swift — Coverage for PR-C2 schema-versioning envelope.

import XCTest
@testable import ZeroDark

// A tiny demo payload that's local to the test file so we don't couple
// to any production model's evolving shape.
private struct DemoV2: SchemaMigratable {
    static let currentSchemaVersion = 2
    var name: String
    var tag: String

    static func migrate(_ envelope: Versioned<DemoV2>) throws -> DemoV2 {
        switch envelope.schemaVersion {
        case 1, 2:
            return envelope.payload
        case let v where v > currentSchemaVersion:
            throw SchemaMigrationError.futureVersion(saw: v, understand: currentSchemaVersion)
        default:
            throw SchemaMigrationError.unknownVersion(envelope.schemaVersion)
        }
    }
}

final class VersionedTests: XCTestCase {

    func test_encode_decode_roundTrip_atCurrentVersion() throws {
        let original = DemoV2(name: "alpha", tag: "bravo")
        let data = try original.encoded()
        let back = try DemoV2.decoded(from: data)
        XCTAssertEqual(back.name, "alpha")
        XCTAssertEqual(back.tag, "bravo")
    }

    func test_encoded_envelope_carriesCurrentSchemaVersion() throws {
        let original = DemoV2(name: "x", tag: "y")
        let data = try original.encoded()
        let envelope = try JSONDecoder().decode(Versioned<DemoV2>.self, from: data)
        XCTAssertEqual(envelope.schemaVersion, DemoV2.currentSchemaVersion)
    }

    func test_decoding_futureVersion_refuses() throws {
        // Synthesize a payload from the "future" — a version higher than
        // the current binary understands. Migrator must refuse.
        let envelope = Versioned<DemoV2>(
            schemaVersion: 99,
            payload: DemoV2(name: "from-future", tag: "oops")
        )
        let data = try JSONEncoder().encode(envelope)
        XCTAssertThrowsError(try DemoV2.decoded(from: data)) { error in
            guard case SchemaMigrationError.futureVersion(let saw, let understand) =
                    error as? SchemaMigrationError ?? .unknownVersion(-1) else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(saw, 99)
            XCTAssertEqual(understand, DemoV2.currentSchemaVersion)
        }
    }

    func test_envelope_isAdditive_nonBreaking_for_unversionedPath() throws {
        // Plain JSONDecoder still works on the raw DemoV2 payload (no
        // envelope). Ensures migrating a model to SchemaMigratable
        // doesn't break the existing non-versioned decode site until it
        // also switches over.
        struct RawPayload: Codable { var name: String; var tag: String }
        let raw = RawPayload(name: "plain", tag: "data")
        let data = try JSONEncoder().encode(raw)
        let back = try JSONDecoder().decode(RawPayload.self, from: data)
        XCTAssertEqual(back.name, "plain")
    }
}
