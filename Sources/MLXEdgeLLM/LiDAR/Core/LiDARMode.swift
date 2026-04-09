// LiDARMode.swift — Display mode enum for LiDAR tab AR view
// Controls which pipeline stages and overlays are active

import Foundation

/// Controls the LiDAR AR view rendering and pipeline behavior.
/// - `.depth`: Depth map coloring only — lightest battery usage
/// - `.mesh`: Wireframe mesh overlay — moderate usage
/// - `.full`: All overlays + YOLO detection + haptic feedback
enum LiDARMode: String, CaseIterable, Identifiable {
    case depth
    case mesh
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .depth: return "Depth"
        case .mesh: return "Mesh"
        case .full: return "Full"
        }
    }

    var icon: String {
        switch self {
        case .depth: return "square.3.layers.3d.down.left"
        case .mesh: return "square.3.layers.3d"
        case .full: return "cube.transparent"
        }
    }

    var enablesYOLO: Bool { self == .full }
    var enablesHaptics: Bool { self == .full }
    var showsMesh: Bool { self == .mesh || self == .full }
    var showsDepth: Bool { true }
}
