// MeshExporter.swift — Export ARMeshAnchor geometry to PLY, OBJ, and USDZ
// Real implementations using vertex/face buffer extraction from ARKit mesh

import Foundation
import ARKit
import SceneKit

// MARK: - Mesh Exporter

final class MeshExporter {

    enum Format: String, CaseIterable {
        case ply  = "PLY"
        case obj  = "OBJ"
        case usdz = "USDZ"

        var fileExtension: String {
            switch self {
            case .ply:  return "ply"
            case .obj:  return "obj"
            case .usdz: return "usdz"
            }
        }
    }

    enum ExportError: LocalizedError {
        case noMeshData
        case writeFailed(String)
        case sceneExportFailed

        var errorDescription: String? {
            switch self {
            case .noMeshData: return "No mesh data to export"
            case .writeFailed(let msg): return "Write failed: \(msg)"
            case .sceneExportFailed: return "USDZ scene export failed"
            }
        }
    }

    // MARK: - Export from ARMeshAnchors

    /// Export mesh anchors to file in the specified format
    func export(anchors: [ARMeshAnchor], format: Format, to url: URL) async throws {
        guard !anchors.isEmpty else { throw ExportError.noMeshData }

        switch format {
        case .ply:  try exportToPLY(anchors: anchors, url: url)
        case .obj:  try exportToOBJ(anchors: anchors, url: url)
        case .usdz: try await exportToUSDZ(anchors: anchors, url: url)
        }
    }

    /// Export all formats to a directory, returns URLs of created files
    func exportAll(anchors: [ARMeshAnchor], directory: URL, baseName: String) async throws -> [URL] {
        var urls: [URL] = []
        for format in Format.allCases {
            let url = directory.appendingPathComponent("\(baseName).\(format.fileExtension)")
            try await export(anchors: anchors, format: format, to: url)
            urls.append(url)
        }
        return urls
    }

    // MARK: - PLY Export (ASCII)

    private func exportToPLY(anchors: [ARMeshAnchor], url: URL) throws {
        var totalVertices: [(SIMD3<Float>)] = []
        var totalFaces: [(Int, Int, Int)] = []
        var vertexOffset = 0

        for anchor in anchors {
            let (vertices, faces) = extractMesh(from: anchor)
            totalVertices.append(contentsOf: vertices)
            totalFaces.append(contentsOf: faces.map { ($0.0 + vertexOffset, $0.1 + vertexOffset, $0.2 + vertexOffset) })
            vertexOffset += vertices.count
        }

        guard !totalVertices.isEmpty else { throw ExportError.noMeshData }

        var ply = "ply\n"
        ply += "format ascii 1.0\n"
        ply += "element vertex \(totalVertices.count)\n"
        ply += "property float x\n"
        ply += "property float y\n"
        ply += "property float z\n"
        ply += "element face \(totalFaces.count)\n"
        ply += "property list uchar int vertex_indices\n"
        ply += "end_header\n"

        for v in totalVertices {
            ply += String(format: "%.6f %.6f %.6f\n", v.x, v.y, v.z)
        }
        for f in totalFaces {
            ply += "3 \(f.0) \(f.1) \(f.2)\n"
        }

        try ply.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - OBJ Export

    private func exportToOBJ(anchors: [ARMeshAnchor], url: URL) throws {
        var totalVertices: [SIMD3<Float>] = []
        var totalFaces: [(Int, Int, Int)] = []
        var vertexOffset = 0

        for anchor in anchors {
            let (vertices, faces) = extractMesh(from: anchor)
            totalVertices.append(contentsOf: vertices)
            // OBJ faces are 1-indexed
            totalFaces.append(contentsOf: faces.map { ($0.0 + vertexOffset + 1, $0.1 + vertexOffset + 1, $0.2 + vertexOffset + 1) })
            vertexOffset += vertices.count
        }

        guard !totalVertices.isEmpty else { throw ExportError.noMeshData }

        var obj = "# ZeroDark LiDAR Scan Export\n"
        obj += "# Vertices: \(totalVertices.count)\n"
        obj += "# Faces: \(totalFaces.count)\n\n"

        for v in totalVertices {
            obj += String(format: "v %.6f %.6f %.6f\n", v.x, v.y, v.z)
        }
        obj += "\n"
        for f in totalFaces {
            obj += "f \(f.0) \(f.1) \(f.2)\n"
        }

        try obj.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - USDZ Export (via SceneKit)

    private func exportToUSDZ(anchors: [ARMeshAnchor], url: URL) async throws {
        let scene = SCNScene()

        for anchor in anchors {
            guard let node = scnNodeFromAnchor(anchor) else { continue }
            scene.rootNode.addChildNode(node)
        }

        guard !scene.rootNode.childNodes.isEmpty else { throw ExportError.noMeshData }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            scene.write(to: url, options: nil, delegate: nil) { progress, error, _ in
                if let error { continuation.resume(throwing: error) }
                else if progress >= 1.0 { continuation.resume() }
            }
        }
    }

    private func scnNodeFromAnchor(_ anchor: ARMeshAnchor) -> SCNNode? {
        let (vertices, faces) = extractMesh(from: anchor)
        guard !vertices.isEmpty, !faces.isEmpty else { return nil }

        let vertexSource = SCNGeometrySource(
            data: Data(bytes: vertices, count: vertices.count * MemoryLayout<SIMD3<Float>>.stride),
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        var indices: [UInt32] = []
        for f in faces {
            indices.append(contentsOf: [UInt32(f.0), UInt32(f.1), UInt32(f.2)])
        }

        let element = SCNGeometryElement(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size),
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.gray
        geometry.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: geometry)
        node.simdTransform = anchor.transform
        return node
    }

    // MARK: - ARMeshAnchor Vertex/Face Extraction

    /// Extract world-space vertices and triangle faces from an ARMeshAnchor
    private func extractMesh(from anchor: ARMeshAnchor) -> ([SIMD3<Float>], [(Int, Int, Int)]) {
        let geometry = anchor.geometry
        let transform = anchor.transform

        // Extract vertices and transform to world space
        let vertexBuffer = geometry.vertices
        let vertexCount = vertexBuffer.count
        let vertexStride = vertexBuffer.stride
        let vertexPointer = vertexBuffer.buffer.contents()

        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vertexCount)

        for i in 0..<vertexCount {
            let offset = i * vertexStride
            let localVertex = vertexPointer.advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            // Transform to world space
            let worldPos = transform * SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1.0)
            vertices.append(SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z))
        }

        // Extract face indices
        let faceBuffer = geometry.faces
        let faceCount = faceBuffer.count
        let bytesPerIndex = faceBuffer.bytesPerIndex
        let facePointer = faceBuffer.buffer.contents()

        var faces: [(Int, Int, Int)] = []
        faces.reserveCapacity(faceCount)

        for i in 0..<faceCount {
            let offset = i * 3 * bytesPerIndex
            let i0: Int, i1: Int, i2: Int
            if bytesPerIndex == 4 {
                i0 = Int(facePointer.advanced(by: offset).assumingMemoryBound(to: UInt32.self).pointee)
                i1 = Int(facePointer.advanced(by: offset + 4).assumingMemoryBound(to: UInt32.self).pointee)
                i2 = Int(facePointer.advanced(by: offset + 8).assumingMemoryBound(to: UInt32.self).pointee)
            } else {
                i0 = Int(facePointer.advanced(by: offset).assumingMemoryBound(to: UInt16.self).pointee)
                i1 = Int(facePointer.advanced(by: offset + 2).assumingMemoryBound(to: UInt16.self).pointee)
                i2 = Int(facePointer.advanced(by: offset + 4).assumingMemoryBound(to: UInt16.self).pointee)
            }
            faces.append((i0, i1, i2))
        }

        return (vertices, faces)
    }
}
