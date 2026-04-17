// SceneTag.swift — Persistent scan record with threats, covers, and tactical assessment
// Serialized as JSON alongside scan data in Documents/LiDARScans/<scanId>/scene_tag.json

import Foundation
import CoreLocation
import simd

struct SceneTag: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let location: CodableCoordinate?
    let pointCount: Int
    let meshRef: String?
    let pointsRef: String?
    var riskScore: Float?
    var threats: [TaggedThreat]
    var covers: [TaggedCover]
    var assessment: String?
    var streamingMapRef: String?          // filename of voxel_map.bin in scan dir (LingBot-Map)

    struct TaggedThreat: Codable, Identifiable {
        let id: UUID
        let className: String
        let confidence: Float
        let position: CodablePoint3D?
        let distance: Float?
        let category: String
        let level: Int

        init(className: String, confidence: Float, position: CodablePoint3D?, distance: Float?, category: String, level: Int) {
            self.id = UUID()
            self.className = className
            self.confidence = confidence
            self.position = position
            self.distance = distance
            self.category = category
            self.level = level
        }
    }

    struct TaggedCover: Codable, Identifiable {
        let id: UUID
        let center: CodablePoint3D
        let type: String
        let protection: Float

        init(center: CodablePoint3D, type: String, protection: Float) {
            self.id = UUID()
            self.center = center
            self.type = type
            self.protection = protection
        }
    }
}

// MARK: - CodableCoordinate Extensions (primary definition in ValidActions.swift)

extension CodableCoordinate {
    init(_ coord: CLLocationCoordinate2D) {
        self.init(latitude: coord.latitude, longitude: coord.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        clLocation
    }
}

struct CodablePoint3D: Codable {
    let x: Float
    let y: Float
    let z: Float

    init(_ point: SIMD3<Float>) {
        self.x = point.x
        self.y = point.y
        self.z = point.z
    }

    var simd: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}

// MARK: - Factory

extension SceneTag {
    static func from(
        result: LiDARScanResult,
        detections: [YOLODetection],
        coverPositions: [CoverPosition],
        scanDir: URL,
        streamingMapRef: String? = nil
    ) -> SceneTag {
        let threats = detections.map { det in
            TaggedThreat(
                className: det.className,
                confidence: det.confidence,
                position: det.position3D.map { CodablePoint3D($0) },
                distance: det.distance,
                category: det.tacticalCategory.rawValue,
                level: det.tacticalLevel().rawValue
            )
        }

        let covers = coverPositions.map { cover in
            TaggedCover(
                center: CodablePoint3D(cover.center),
                type: cover.type.rawValue,
                protection: cover.protection
            )
        }

        let hasUSDZ = FileManager.default.fileExists(
            atPath: scanDir.appendingPathComponent("scan.usdz").path
        )
        let hasPoints = FileManager.default.fileExists(
            atPath: scanDir.appendingPathComponent("points.bin").path
        )

        let hasVoxelMap = streamingMapRef != nil ||
            FileManager.default.fileExists(atPath: scanDir.appendingPathComponent("voxel_map.bin").path)

        return SceneTag(
            id: result.id,
            timestamp: result.timestamp,
            location: result.location.map { CodableCoordinate($0) },
            pointCount: result.pointCount,
            meshRef: hasUSDZ ? "scan.usdz" : nil,
            pointsRef: hasPoints ? "points.bin" : nil,
            riskScore: result.tacticalAnalysis?.riskScore,
            threats: threats,
            covers: covers,
            assessment: nil,
            streamingMapRef: streamingMapRef ?? (hasVoxelMap ? "voxel_map.bin" : nil)
        )
    }
}
