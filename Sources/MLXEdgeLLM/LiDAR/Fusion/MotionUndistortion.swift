// MotionUndistortion.swift — Per-point deskewing using Kalman-fused poses
// Corrects motion distortion in point clouds captured during device movement

import Foundation
import simd

// MARK: - MotionUndistortion

final class MotionUndistortion {

    /// Undistort a point cloud by compensating for device motion during capture.
    ///
    /// Each point is assumed to have been captured at a linearly interpolated time
    /// between `startTime` and `endTime` (based on scan line order). The inverse
    /// motion from each point's capture time to the reference time is applied.
    ///
    /// - Parameters:
    ///   - points: Raw points in the camera/sensor frame
    ///   - startTime: Timestamp of first point (top of depth image)
    ///   - endTime: Timestamp of last point (bottom of depth image)
    ///   - kalman: The KalmanFuse providing interpolated poses
    ///   - referenceTime: The time at which to align all points (defaults to endTime)
    /// - Returns: Undistorted points in world frame at the reference time
    static func undistort(
        points: [SIMD3<Float>],
        startTime: TimeInterval,
        endTime: TimeInterval,
        kalman: KalmanFuse,
        referenceTime: TimeInterval? = nil
    ) -> [SIMD3<Float>] {
        guard points.count > 1 else {
            // Single point or empty — just transform to world frame
            if let point = points.first, let pose = kalman.interpolatedPose(at: endTime) {
                return [transformPoint(point, by: pose.transform)]
            }
            return points
        }

        let refTime = referenceTime ?? endTime
        guard let refPose = kalman.interpolatedPose(at: refTime) else { return points }
        let refTransformInv = refPose.transform.inverse

        let duration = endTime - startTime
        guard duration > 0 else {
            // Zero duration — all points at same time, just transform
            return points.map { transformPoint($0, by: refPose.transform) }
        }

        var undistorted = [SIMD3<Float>]()
        undistorted.reserveCapacity(points.count)

        // Process in batches of 64 to reduce interpolation calls
        // Points within the same batch share an interpolated pose
        let batchSize = 64
        let totalPoints = points.count

        for batchStart in stride(from: 0, to: totalPoints, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalPoints)
            let batchMidIndex = (batchStart + batchEnd) / 2
            let t = Double(batchMidIndex) / Double(totalPoints - 1)
            let sampleTime = startTime + t * duration

            guard let samplePose = kalman.interpolatedPose(at: sampleTime) else {
                // Fallback: use reference pose
                for i in batchStart..<batchEnd {
                    undistorted.append(points[i])
                }
                continue
            }

            // Transform: world_at_sample -> world_at_ref
            // point_world = samplePose.transform * point_sensor
            // point_at_ref = refTransformInv * samplePose.transform * point_sensor
            let correction = refTransformInv * samplePose.transform

            for i in batchStart..<batchEnd {
                undistorted.append(transformPoint(points[i], by: correction))
            }
        }

        return undistorted
    }

    /// Undistort using a precomputed array of poses (more efficient when poses are already available)
    static func undistort(
        points: [SIMD3<Float>],
        poses: [FusedPose],
        referenceIndex: Int? = nil
    ) -> [SIMD3<Float>] {
        guard points.count > 1, poses.count >= 2 else { return points }

        let refIdx = referenceIndex ?? (poses.count - 1)
        let refTransformInv = poses[refIdx].transform.inverse

        var undistorted = [SIMD3<Float>]()
        undistorted.reserveCapacity(points.count)

        for (i, point) in points.enumerated() {
            // Map point index to pose index
            let poseT = Float(i) / Float(points.count - 1) * Float(poses.count - 1)
            let poseIdx0 = min(Int(poseT), poses.count - 2)
            let poseIdx1 = poseIdx0 + 1
            let alpha = poseT - Float(poseIdx0)

            // Interpolate transform between two nearest poses
            let t0 = poses[poseIdx0].transform
            let t1 = poses[poseIdx1].transform

            // Linear interpolation of transform columns (sufficient for small inter-pose motion)
            let interpTransform = lerpTransform(t0, t1, t: alpha)
            let correction = refTransformInv * interpTransform

            undistorted.append(transformPoint(point, by: correction))
        }

        return undistorted
    }

    // MARK: - Transform Helpers

    private static func transformPoint(_ point: SIMD3<Float>, by transform: simd_float4x4) -> SIMD3<Float> {
        let p4 = transform * SIMD4<Float>(point, 1.0)
        return SIMD3<Float>(p4.x, p4.y, p4.z)
    }

    private static func lerpTransform(
        _ a: simd_float4x4,
        _ b: simd_float4x4,
        t: Float
    ) -> simd_float4x4 {
        // Interpolate rotation via slerp, position via lerp
        let qa = simd_quatf(a)
        let qb = simd_quatf(b)
        let qi = simd_slerp(qa, qb, t)

        let pa = SIMD3<Float>(a.columns.3.x, a.columns.3.y, a.columns.3.z)
        let pb = SIMD3<Float>(b.columns.3.x, b.columns.3.y, b.columns.3.z)
        let pi = simd_mix(pa, pb, SIMD3<Float>(repeating: t))

        let rot = simd_float3x3(qi)
        return simd_float4x4(columns: (
            SIMD4<Float>(rot.columns.0, 0),
            SIMD4<Float>(rot.columns.1, 0),
            SIMD4<Float>(rot.columns.2, 0),
            SIMD4<Float>(pi, 1)
        ))
    }
}
