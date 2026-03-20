// SubmapStore.swift — Ring buffer of recent scans (Boeing Cartographer pattern)

import simd
import Foundation
import Observation

/// Ring buffer for submap storage
@MainActor
public class SubmapStore: NSObject, ObservableObject {
    public static let shared = SubmapStore()

    @Published public var submaps: [[[simd_float2]]] = []

    private let maxSubmaps: Int = 20
    private var ringIndex: Int = 0

    private override init() {
        super.init()
    }

    /// Add scan to ring buffer
    public func add(scan: [[simd_float2]], pose: simd_float3) {
        // Transform scan by pose
        let transformed = scan.map { points in
            points.map { point in
                let p = simd_float3(point.x, point.y, 1)
                let cosTheta = cos(pose.z)
                let sinTheta = sin(pose.z)

                let rotated = simd_float2(
                    cosTheta * p.x - sinTheta * p.y,
                    sinTheta * p.x + cosTheta * p.y
                )

                return rotated + simd_float2(pose.x, pose.y)
            }
        }

        if submaps.count < maxSubmaps {
            submaps.append(transformed)
        } else {
            submaps[ringIndex] = transformed
            ringIndex = (ringIndex + 1) % maxSubmaps
        }
    }

    /// Get reference scan near position
    public func reference(near pose: simd_float3) -> [[simd_float2]]? {
        guard !submaps.isEmpty else {
            return nil
        }

        // Return oldest submap (coarse reference)
        return submaps[0]
    }

    /// Clear all submaps
    public func clear() {
        submaps.removeAll()
        ringIndex = 0
    }
}
