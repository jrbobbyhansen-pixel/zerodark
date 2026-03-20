// MeasurementTypes.swift — Measurement data models

import Foundation
import simd

// MARK: - Measurement Types

enum MeasurementType: String, Codable, CaseIterable {
    case distance = "Distance"
    case area = "Area"
    case height = "Height"

    var icon: String {
        switch self {
        case .distance: return "ruler"
        case .area: return "square.dashed"
        case .height: return "arrow.up.and.down"
        }
    }
}

enum MeasurementUnit: String, Codable, CaseIterable {
    case metric = "Metric"
    case imperial = "Imperial"
}

// MARK: - Codable SIMD3 wrapper

struct CodableSIMD3: Codable {
    let x: Float
    let y: Float
    let z: Float

    var simd: SIMD3<Float> {
        SIMD3(x, y, z)
    }

    init(_ simd: SIMD3<Float>) {
        self.x = simd.x
        self.y = simd.y
        self.z = simd.z
    }

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

// MARK: - Measurement Annotation

struct MeasurementAnnotation: Identifiable, Codable {
    let id: UUID
    let type: MeasurementType
    let points: [CodableSIMD3]  // 2 points for distance/height, 3+ for area
    let timestamp: Date
    var label: String?

    // Computed measurement value (meters or sq meters)
    var rawValue: Float {
        switch type {
        case .distance:
            guard points.count >= 2 else { return 0 }
            return simd_distance(points[0].simd, points[1].simd)

        case .height:
            guard points.count >= 2 else { return 0 }
            return abs(points[1].simd.y - points[0].simd.y)

        case .area:
            guard points.count >= 3 else { return 0 }
            return calculatePolygonArea(points.map { $0.simd })
        }
    }

    // Formatted display string
    func displayValue(unit: MeasurementUnit) -> String {
        switch type {
        case .distance, .height:
            if unit == .metric {
                return String(format: "%.2f m", rawValue)
            } else {
                let feet = rawValue * 3.28084
                return String(format: "%.2f ft", feet)
            }

        case .area:
            if unit == .metric {
                return String(format: "%.2f m²", rawValue)
            } else {
                let sqft = rawValue * 10.7639
                return String(format: "%.2f ft²", sqft)
            }
        }
    }

    // Calculate polygon area using Shoelace formula (projected to XZ plane)
    private func calculatePolygonArea(_ verts: [SIMD3<Float>]) -> Float {
        guard verts.count >= 3 else { return 0 }

        var area: Float = 0
        let n = verts.count

        for i in 0..<n {
            let j = (i + 1) % n
            // Using X and Z coordinates (horizontal plane)
            area += verts[i].x * verts[j].z
            area -= verts[j].x * verts[i].z
        }

        return abs(area) / 2.0
    }
}

// MARK: - Scan Annotations Container

struct ScanAnnotations: Codable {
    var measurements: [MeasurementAnnotation]
    var lastModified: Date

    init() {
        self.measurements = []
        self.lastModified = Date()
    }
}
