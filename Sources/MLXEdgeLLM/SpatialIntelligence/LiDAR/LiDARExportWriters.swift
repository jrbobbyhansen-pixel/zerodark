// LiDARExportWriters.swift — 3D export helpers extracted from
// SpatialIntelligence/LiDAR/LiDARCaptureEngine.swift (PR-B7).
//
// The engine is 2240 LOC. The audit flagged its size as a maintainability
// hazard. The PLY-binary and USDZ writers below were the most self-contained
// chunks — they depend only on their input parameters, so pulling them into
// a dedicated file removes ~115 LOC from the engine without touching any of
// its private @Published state.
//
// Public surface: two async functions (binary point cloud, USDZ mesh) plus
// one pure helper (ARMeshAnchor → SCNNode). All live in an enum namespace
// so call sites read like `LiDARExportWriters.savePointsBinary(…)`.

import Foundation
import ARKit
import SceneKit
import simd
import UIKit

public enum LiDARExportWriters {

    /// Save a point cloud as a binary blob: 4-byte little-endian count
    /// followed by N × 12-byte SIMD3<Float> positions. This format is
    /// ~100× faster to write than ASCII PLY for the common use of dumping
    /// a scan to disk for later re-opening in-app.
    ///
    /// Writes in 85 000-point chunks with a Task.yield() between chunks
    /// so the UI stays responsive during large exports.
    public static func savePointsBinary(
        _ points: [SIMD3<Float>],
        to url: URL
    ) async throws {
        guard !points.isEmpty else { return }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var count = UInt32(points.count)
        handle.write(Data(bytes: &count, count: 4))
        let chunkSize = 85_000
        for chunkStart in stride(from: 0, to: points.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, points.count)
            var data = Data(capacity: (chunkEnd - chunkStart) * 12)
            for point in points[chunkStart..<chunkEnd] {
                var p = point
                data.append(Data(bytes: &p, count: 12))
            }
            handle.write(data)
            await Task.yield()
        }
        try handle.close()
    }

    /// Convert AR mesh anchors into a single SCNScene and write it out as
    /// USDZ at `url`. No-op on empty input; throws on I/O or conversion
    /// failure. Callers can pass the resulting URL directly to a share
    /// sheet for AirDrop / Files export.
    public static func exportMeshToUSDZAsync(
        _ anchors: [ARMeshAnchor],
        to url: URL
    ) async throws {
        guard !anchors.isEmpty else { return }
        let scene = SCNScene()
        for anchor in anchors {
            if let node = scnNodeFromMeshAnchor(anchor) {
                scene.rootNode.addChildNode(node)
            }
        }
        guard !scene.rootNode.childNodes.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            scene.write(to: url, options: nil, delegate: nil) { progress, error, _ in
                if let error {
                    continuation.resume(throwing: error)
                } else if progress >= 1.0 {
                    continuation.resume()
                }
            }
        }
    }

    /// Convert a single ARMeshAnchor into an SCNNode with world-space
    /// vertex positions + triangle indices. Returns nil if the anchor has
    /// no vertices.
    public static func scnNodeFromMeshAnchor(_ anchor: ARMeshAnchor) -> SCNNode? {
        let geometry = anchor.geometry
        let vertexCount = geometry.vertices.count
        guard vertexCount > 0 else { return nil }

        // Extract vertices, transform to world coordinates.
        var positions: [SCNVector3] = []
        positions.reserveCapacity(vertexCount)
        let vertexBuffer = geometry.vertices.buffer.contents()
        let vertexStride = geometry.vertices.stride
        let vertexOffset = geometry.vertices.offset
        for i in 0..<vertexCount {
            let ptr = vertexBuffer.advanced(by: vertexOffset + i * vertexStride)
                .bindMemory(to: SIMD3<Float>.self, capacity: 1)
            let local = ptr.pointee
            let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            positions.append(SCNVector3(world.x, world.y, world.z))
        }

        // Extract face indices.
        let faceCount = geometry.faces.count
        var indices: [UInt32] = []
        if faceCount > 0 {
            indices.reserveCapacity(faceCount * 3)
            let indexBuffer = geometry.faces.buffer.contents()
            let bytesPerIndex = geometry.faces.bytesPerIndex
            for i in 0..<(faceCount * 3) {
                let ptr = indexBuffer.advanced(by: i * bytesPerIndex)
                if bytesPerIndex == 4 {
                    indices.append(ptr.bindMemory(to: UInt32.self, capacity: 1).pointee)
                } else if bytesPerIndex == 2 {
                    indices.append(UInt32(ptr.bindMemory(to: UInt16.self, capacity: 1).pointee))
                }
            }
        }

        // Extract per-vertex normals and rotate them into world space using
        // the anchor's rotation (upper-left 3×3 of the transform). Without
        // normals SceneKit cannot shade the mesh — it renders as a flat,
        // unlit silhouette, which is the root cause of the "gray blob" scan
        // renderings. ARMeshGeometry always supplies one normal per vertex.
        var normalSource: SCNGeometrySource?
        if anchor.geometry.normals.count == vertexCount {
            var worldNormals: [SCNVector3] = []
            worldNormals.reserveCapacity(vertexCount)
            let normals = anchor.geometry.normals
            let normalBuffer = normals.buffer.contents()
            let normalStride = normals.stride
            let normalOffset = normals.offset
            let t = anchor.transform
            let rotation = simd_float3x3(
                SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
            )
            for i in 0..<vertexCount {
                let ptr = normalBuffer.advanced(by: normalOffset + i * normalStride)
                    .bindMemory(to: SIMD3<Float>.self, capacity: 1)
                let world = simd_normalize(rotation * ptr.pointee)
                worldNormals.append(SCNVector3(world.x, world.y, world.z))
            }
            normalSource = SCNGeometrySource(normals: worldNormals)
        }

        // Assemble SCNGeometry with a lit, physically-based material so the
        // model reads as a real surface in the in-app gallery (whose 3-point
        // lighting now has normals to work with) and in external USDZ viewers.
        let positionSource = SCNGeometrySource(vertices: positions)
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: faceCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        var sources = [positionSource]
        if let normalSource { sources.append(normalSource) }
        let scnGeometry = SCNGeometry(sources: sources, elements: [element])

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.80, alpha: 1.0)
        material.metalness.contents = 0.0
        material.roughness.contents = 0.85
        material.isDoubleSided = true
        scnGeometry.materials = [material]

        return SCNNode(geometry: scnGeometry)
    }
}
