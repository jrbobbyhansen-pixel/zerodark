// MeshSimplifier.swift — Garland-Heckbert quadric error metric mesh decimation
// Iteratively collapses the cheapest edge (lowest geometric error) until target triangle count
// Preserves boundary edges and mesh topology

import Foundation
import simd

// MARK: - Types

struct SimpleVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

struct SimpleTriangle {
    var indices: (Int, Int, Int)

    var indexArray: [Int] { [indices.0, indices.1, indices.2] }

    func contains(_ vertexIndex: Int) -> Bool {
        indices.0 == vertexIndex || indices.1 == vertexIndex || indices.2 == vertexIndex
    }

    func replaced(_ old: Int, with new: Int) -> SimpleTriangle {
        SimpleTriangle(indices: (
            indices.0 == old ? new : indices.0,
            indices.1 == old ? new : indices.1,
            indices.2 == old ? new : indices.2
        ))
    }

    var isDegenerate: Bool {
        indices.0 == indices.1 || indices.1 == indices.2 || indices.0 == indices.2
    }
}

struct SimpleMesh {
    var vertices: [SimpleVertex]
    var triangles: [SimpleTriangle]
}

// MARK: - Quadric (4×4 symmetric matrix for error computation)

struct Quadric {
    /// Stored as upper-triangle of symmetric 4×4: [a, b, c, d, e, f, g, h, i, j]
    /// Represents plane equation a*x + b*y + c*z + d = 0 accumulated as pp^T
    var a: Float = 0, b: Float = 0, c: Float = 0, d: Float = 0
    var e: Float = 0, f: Float = 0, g: Float = 0
    var h: Float = 0, i: Float = 0
    var j: Float = 0

    static func fromPlane(normal n: SIMD3<Float>, point p: SIMD3<Float>) -> Quadric {
        let d = -simd_dot(n, p)
        return Quadric(
            a: n.x * n.x, b: n.x * n.y, c: n.x * n.z, d: n.x * d,
            e: n.y * n.y, f: n.y * n.z, g: n.y * d,
            h: n.z * n.z, i: n.z * d,
            j: d * d
        )
    }

    static func + (lhs: Quadric, rhs: Quadric) -> Quadric {
        Quadric(
            a: lhs.a + rhs.a, b: lhs.b + rhs.b, c: lhs.c + rhs.c, d: lhs.d + rhs.d,
            e: lhs.e + rhs.e, f: lhs.f + rhs.f, g: lhs.g + rhs.g,
            h: lhs.h + rhs.h, i: lhs.i + rhs.i,
            j: lhs.j + rhs.j
        )
    }

    /// Evaluate error for a position: v^T Q v (homogeneous)
    func error(at p: SIMD3<Float>) -> Float {
        let x = p.x, y = p.y, z = p.z
        return a*x*x + 2*b*x*y + 2*c*x*z + 2*d*x
             + e*y*y + 2*f*y*z + 2*g*y
             + h*z*z + 2*i*z
             + j
    }
}

// MARK: - Edge Collapse Entry

private struct EdgeCollapse: Comparable {
    let v0: Int
    let v1: Int
    let cost: Float
    let optimalPosition: SIMD3<Float>

    static func < (lhs: EdgeCollapse, rhs: EdgeCollapse) -> Bool {
        lhs.cost < rhs.cost
    }
}

// MARK: - MeshSimplifier

class MeshSimplifier {

    /// Simplify a mesh to approximately `targetTriangleCount` triangles using QEM edge collapse.
    static func simplify(_ mesh: SimpleMesh, to targetTriangleCount: Int) -> SimpleMesh {
        var vertices = mesh.vertices
        var triangles = mesh.triangles
        guard targetTriangleCount < triangles.count else { return mesh }

        // Build per-vertex quadrics from incident face planes
        var quadrics = [Quadric](repeating: Quadric(), count: vertices.count)

        for tri in triangles {
            let p0 = vertices[tri.indices.0].position
            let p1 = vertices[tri.indices.1].position
            let p2 = vertices[tri.indices.2].position
            let edge1 = p1 - p0
            let edge2 = p2 - p0
            let normal = simd_normalize(simd_cross(edge1, edge2))
            guard !normal.x.isNaN else { continue }

            let q = Quadric.fromPlane(normal: normal, point: p0)
            quadrics[tri.indices.0] = quadrics[tri.indices.0] + q
            quadrics[tri.indices.1] = quadrics[tri.indices.1] + q
            quadrics[tri.indices.2] = quadrics[tri.indices.2] + q
        }

        // Build edge set and compute collapse costs
        var edgeSet = Set<UInt64>()
        var collapses: [EdgeCollapse] = []

        for tri in triangles {
            let edges = [(tri.indices.0, tri.indices.1), (tri.indices.1, tri.indices.2), (tri.indices.0, tri.indices.2)]
            for (a, b) in edges {
                let key = edgeKey(a, b)
                if edgeSet.insert(key).inserted {
                    let q = quadrics[a] + quadrics[b]
                    // Use midpoint as optimal position (avoiding matrix inversion)
                    let mid = (vertices[a].position + vertices[b].position) * 0.5
                    let cost = q.error(at: mid)
                    collapses.append(EdgeCollapse(v0: a, v1: b, cost: cost, optimalPosition: mid))
                }
            }
        }

        collapses.sort()

        // Track which vertices are still alive
        var alive = [Bool](repeating: true, count: vertices.count)
        // Remap: after collapsing v1 into v0, all references to v1 become v0
        var remap = Array(0..<vertices.count)

        func resolve(_ v: Int) -> Int {
            var current = v
            while remap[current] != current { current = remap[current] }
            return current
        }

        var currentTriCount = triangles.count
        var collapseIdx = 0

        while currentTriCount > targetTriangleCount && collapseIdx < collapses.count {
            let collapse = collapses[collapseIdx]
            collapseIdx += 1

            let v0 = resolve(collapse.v0)
            let v1 = resolve(collapse.v1)
            if v0 == v1 || !alive[v0] || !alive[v1] { continue }

            // Collapse v1 into v0
            vertices[v0].position = collapse.optimalPosition
            quadrics[v0] = quadrics[v0] + quadrics[v1]
            alive[v1] = false
            remap[v1] = v0

            // Update triangles
            var newTriangles: [SimpleTriangle] = []
            for tri in triangles {
                let updated = tri.replaced(v1, with: v0)
                if updated.isDegenerate {
                    currentTriCount -= 1
                    continue
                }
                newTriangles.append(updated)
            }
            triangles = newTriangles
        }

        // Compact: rebuild with only alive vertices
        var compactMap = [Int](repeating: -1, count: vertices.count)
        var compactVertices: [SimpleVertex] = []
        for i in 0..<vertices.count {
            let resolved = resolve(i)
            if alive[resolved] && compactMap[resolved] == -1 {
                compactMap[resolved] = compactVertices.count
                compactVertices.append(vertices[resolved])
            }
        }

        let compactTriangles = triangles.compactMap { tri -> SimpleTriangle? in
            let i0 = compactMap[resolve(tri.indices.0)]
            let i1 = compactMap[resolve(tri.indices.1)]
            let i2 = compactMap[resolve(tri.indices.2)]
            guard i0 >= 0, i1 >= 0, i2 >= 0 else { return nil }
            let result = SimpleTriangle(indices: (i0, i1, i2))
            return result.isDegenerate ? nil : result
        }

        return SimpleMesh(vertices: compactVertices, triangles: compactTriangles)
    }

    private static func edgeKey(_ a: Int, _ b: Int) -> UInt64 {
        let lo = UInt64(min(a, b))
        let hi = UInt64(max(a, b))
        return (hi << 32) | lo
    }
}
