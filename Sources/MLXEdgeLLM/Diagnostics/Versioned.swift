// Versioned.swift — Schema-versioning envelope for persisted Codable models.
//
// Roadmap PR-C2. Models serialized to disk (IncidentLogEntry,
// NavTrailPoint, DroneTelemetry, CasualtyCard, ScanOverlay,
// TacticalWaypoint, etc.) currently ship without a schema version.
// Adding a field to any of them silently breaks the decoder on old
// user data — the optimistic `try? JSONDecoder().decode(...)` calls
// scattered across the codebase fail open and return empty arrays,
// wiping the operator's persisted work.
//
// `Versioned<T>` wraps a payload with a monotonic schema version and
// lets the call site migrate older payloads forward before decode.
// Use it when introducing new fields to already-persisted models.
//
// Usage:
//     let envelope = try JSONDecoder().decode(
//         Versioned<IncidentLogEntry>.self, from: data
//     )
//     let current = try IncidentLogEntry.migrate(envelope)
//
// Until a model opts in, existing data keeps working via the plain
// `.decode(IncidentLogEntry.self, from: data)` path — Versioned is
// additive.

import Foundation

/// Immutable envelope that pairs a schema-version integer with a
/// Codable payload. `schemaVersion` is monotonic — bump it every time
/// a migration is required.
public struct Versioned<T: Codable>: Codable {
    public var schemaVersion: Int
    public var payload: T

    public init(schemaVersion: Int, payload: T) {
        self.schemaVersion = schemaVersion
        self.payload = payload
    }
}

/// Migration protocol. Types opt in to schema-aware decoding by
/// declaring their current version and writing a forward-only migrator.
/// Implementations should NEVER downgrade — if we see a version higher
/// than we understand, refuse to decode rather than silently losing
/// fields.
public protocol SchemaMigratable: Codable {
    /// The schema version this binary understands.
    static var currentSchemaVersion: Int { get }

    /// Migrate a Versioned envelope whose version is ≤ current into the
    /// latest shape. Throw `SchemaMigrationError.futureVersion` when
    /// the envelope is from a newer binary (forward-only rule).
    static func migrate(_ envelope: Versioned<Self>) throws -> Self
}

public enum SchemaMigrationError: Error, LocalizedError, Equatable {
    case futureVersion(saw: Int, understand: Int)
    case unknownVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .futureVersion(let saw, let known):
            return "Persisted data is schema v\(saw); this build understands up to v\(known). Refusing to decode to avoid field loss."
        case .unknownVersion(let v):
            return "Unknown schema version \(v)."
        }
    }
}

public extension SchemaMigratable {
    /// Convenience: encode `self` as a `Versioned<Self>` envelope at
    /// the current schema version.
    func encoded() throws -> Data {
        let envelope = Versioned(schemaVersion: Self.currentSchemaVersion, payload: self)
        return try JSONEncoder().encode(envelope)
    }

    /// Convenience: decode a `Versioned<Self>` envelope and migrate it
    /// forward to the current shape.
    static func decoded(from data: Data) throws -> Self {
        let envelope = try JSONDecoder().decode(Versioned<Self>.self, from: data)
        return try Self.migrate(envelope)
    }
}
