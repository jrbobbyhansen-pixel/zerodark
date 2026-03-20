// TelemetryObject.swift — NASA Open MCT telemetry objects with time-series data

import Foundation

/// Telemetry value types (for polymorphic storage)
public enum TelemetryValue: Codable, Equatable {
    case double(Double)
    case int(Int)
    case string(String)
    case bool(Bool)

    enum CodingKeys: String, CodingKey {
        case doubleValue, intValue, stringValue, boolValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let val = try container.decodeIfPresent(Double.self, forKey: .doubleValue) {
            self = .double(val)
        } else if let val = try container.decodeIfPresent(Int.self, forKey: .intValue) {
            self = .int(val)
        } else if let val = try container.decodeIfPresent(String.self, forKey: .stringValue) {
            self = .string(val)
        } else if let val = try container.decodeIfPresent(Bool.self, forKey: .boolValue) {
            self = .bool(val)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown TelemetryValue")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .double(let val): try container.encode(val, forKey: .doubleValue)
        case .int(let val): try container.encode(val, forKey: .intValue)
        case .string(let val): try container.encode(val, forKey: .stringValue)
        case .bool(let val): try container.encode(val, forKey: .boolValue)
        }
    }
}

/// A single telemetry datum
public struct TelemetryDatum: Identifiable, Codable {
    public let id = UUID()
    public let timestamp: Date
    public let value: TelemetryValue

    public init(timestamp: Date, value: TelemetryValue) {
        self.timestamp = timestamp
        self.value = value
    }
}

/// Telemetry object types (MCT pattern)
public enum TelemetryObjectType: String, Codable, CaseIterable {
    case position
    case battery
    case mesh
    case team
    case weather
    case threat

    public var displayName: String {
        switch self {
        case .position: return "Position"
        case .battery: return "Battery"
        case .mesh: return "Mesh Status"
        case .team: return "Team Count"
        case .weather: return "Weather"
        case .threat: return "Threat Level"
        }
    }

    public var icon: String {
        switch self {
        case .position: return "location.fill"
        case .battery: return "battery.100"
        case .mesh: return "network"
        case .team: return "person.2.fill"
        case .weather: return "cloud.fill"
        case .threat: return "exclamationmark.triangle.fill"
        }
    }
}

/// A telemetry object (stateful container)
public struct TelemetryObject: Identifiable, Codable {
    public let id: UUID
    public let type: TelemetryObjectType
    public var data: [TelemetryDatum]
    public let createdAt: Date
    public var updatedAt: Date

    public init(type: TelemetryObjectType) {
        self.id = UUID()
        self.type = type
        self.data = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Add a datum and maintain max size (1000 points)
    public mutating func add(_ datum: TelemetryDatum) {
        data.append(datum)
        updatedAt = Date()
        if data.count > 1000 {
            data.removeFirst(data.count - 1000)
        }
    }

    /// Latest value
    public var latestValue: TelemetryValue? {
        data.last?.value
    }
}
