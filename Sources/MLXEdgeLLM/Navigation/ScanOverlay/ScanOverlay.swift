// ScanOverlay.swift — Architectural / tactical overlay primitives placed on a completed LiDAR scan.
//
// Coordinate system: SCAN-LOCAL. Positions are in the same frame Terrain3DSceneBuilder
// uses AFTER centering the point cloud to origin (see Terrain3dViewer.swift:126–129).
// NOT GPS. NOT ARKit world. This is intentionally separate from PointCloudAnnotator
// (which is GPS-anchored and global-scoped).

import Foundation
import simd

// MARK: - Kind

enum ScanOverlayKind: String, Codable, CaseIterable {
    // Architectural primitives (Pascal-editor style)
    case wall
    case door
    case window
    case zone
    // Tactical markers
    case hazard
    case cover
    case entry
    case objective

    var displayName: String {
        switch self {
        case .wall:      return "Wall"
        case .door:      return "Door"
        case .window:    return "Window"
        case .zone:      return "Zone"
        case .hazard:    return "Hazard"
        case .cover:     return "Cover"
        case .entry:     return "Entry"
        case .objective: return "Objective"
        }
    }

    var icon: String {
        switch self {
        case .wall:      return "rectangle.portrait"
        case .door:      return "door.left.hand.closed"
        case .window:    return "window.ceiling"
        case .zone:      return "square.dashed"
        case .hazard:    return "exclamationmark.triangle.fill"
        case .cover:     return "shield.lefthalf.filled"
        case .entry:     return "arrow.down.forward.circle.fill"
        case .objective: return "flag.fill"
        }
    }

    /// How many tap points finalize the overlay.
    /// Wall = 2 taps (start, end). Zone = 3+ taps closed explicitly by user. Others = 1 tap.
    var requiredPoints: Int {
        switch self {
        case .wall:       return 2
        case .zone:       return 3
        default:          return 1
        }
    }

    var isArchitectural: Bool {
        switch self {
        case .wall, .door, .window, .zone: return true
        case .hazard, .cover, .entry, .objective: return false
        }
    }
}

// MARK: - Codable SIMD3 wrapper

/// SIMD3<Float> is not Codable out of the box. Serialize as 3-element Float array.
struct CodablePoint3: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float

    init(_ v: SIMD3<Float>) {
        self.x = v.x; self.y = v.y; self.z = v.z
    }

    init(x: Float, y: Float, z: Float) {
        self.x = x; self.y = y; self.z = z
    }

    var simd: SIMD3<Float> { SIMD3(x, y, z) }
}

// MARK: - ScanOverlay

struct ScanOverlay: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ScanOverlayKind
    /// Scan-local points. 1 entry for markers / door / window; 2 for wall; ≥3 for zone.
    var points: [CodablePoint3]
    /// Y-axis rotation in radians (used for doors/windows that sit on a wall).
    var rotationY: Float
    var label: String
    var notes: String
    var createdAt: Date
    var createdBy: String

    init(
        id: UUID = UUID(),
        kind: ScanOverlayKind,
        points: [SIMD3<Float>],
        rotationY: Float = 0,
        label: String = "",
        notes: String = "",
        createdAt: Date = .init(),
        createdBy: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.points = points.map(CodablePoint3.init)
        self.rotationY = rotationY
        self.label = label
        self.notes = notes
        self.createdAt = createdAt
        self.createdBy = createdBy
    }

    /// Convenience: first anchor point as SIMD3.
    var anchor: SIMD3<Float> { points.first?.simd ?? .zero }

    /// Convenience: SIMD points array (allocates).
    var simdPoints: [SIMD3<Float>] { points.map(\.simd) }
}

// MARK: - Mesh Broadcast Payload

/// Wire format for transmitting overlays over the mesh. One payload carries the full
/// set of overlays for a single scan so a late-joining peer can catch up with one message.
struct OverlayBroadcastPayload: Codable {
    let scanID: UUID
    let overlays: [ScanOverlay]
    let senderCallsign: String
    let timestamp: Date
}
