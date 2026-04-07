// Colorization.swift — Camera-to-point-cloud color projection
// Projects each 3D point onto the camera image using ARKit intrinsics/extrinsics
// Samples pixel color at the projected coordinate

import Foundation
import simd
import ARKit
import CoreVideo

// MARK: - Colored Point

struct ColoredPoint {
    let position: SIMD3<Float>
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

// MARK: - PointCloudColorizer

class PointCloudColorizer {

    /// Colorize a point cloud using the camera frame's image and intrinsics.
    /// Projects each 3D world point into the camera's 2D image plane and samples the pixel.
    static func colorize(
        points: [SIMD3<Float>],
        frame: ARFrame
    ) -> [ColoredPoint] {
        let intrinsics = frame.camera.intrinsics
        let viewMatrix = frame.camera.viewMatrix(for: .landscapeRight)
        let imageBuffer = frame.capturedImage

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else { return [] }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)

        var result: [ColoredPoint] = []
        result.reserveCapacity(points.count)

        for point in points {
            // Transform world point to camera space
            let worldPos = SIMD4<Float>(point.x, point.y, point.z, 1.0)
            let cameraPos = viewMatrix * worldPos

            // Skip points behind camera
            guard cameraPos.z < 0 else { continue }

            // Project to image plane using intrinsics
            // Camera convention: x right, y down, z forward (negative in ARKit)
            let x = cameraPos.x / (-cameraPos.z)
            let y = cameraPos.y / (-cameraPos.z)

            let px = Int(intrinsics[0][0] * x + intrinsics[2][0])
            let py = Int(intrinsics[1][1] * y + intrinsics[2][1])

            // Bounds check
            guard px >= 0, px < width, py >= 0, py < height else { continue }

            // Sample pixel (YCbCr 420 format → approximate RGB)
            // ARKit capturedImage is in kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let rgb = sampleYCbCrPixel(baseAddress: baseAddress, bytesPerRow: bytesPerRow,
                                        width: width, height: height, x: px, y: py, buffer: imageBuffer)

            result.append(ColoredPoint(position: point, r: rgb.0, g: rgb.1, b: rgb.2))
        }

        return result
    }

    /// Colorize using multiple frames for better coverage.
    /// Each point takes color from the frame where it's most visible (closest to image center).
    static func colorizeMultiFrame(
        points: [SIMD3<Float>],
        frames: [ARFrame]
    ) -> [ColoredPoint] {
        guard !frames.isEmpty else { return [] }
        if frames.count == 1 { return colorize(points: points, frame: frames[0]) }

        // For each point, find the best frame (point closest to image center)
        var bestColors: [ColoredPoint?] = Array(repeating: nil, count: points.count)
        var bestCenterDist: [Float] = Array(repeating: .infinity, count: points.count)

        for frame in frames {
            let intrinsics = frame.camera.intrinsics
            let viewMatrix = frame.camera.viewMatrix(for: .landscapeRight)
            let width = CVPixelBufferGetWidth(frame.capturedImage)
            let height = CVPixelBufferGetHeight(frame.capturedImage)
            let cx = Float(width) / 2.0
            let cy = Float(height) / 2.0

            CVPixelBufferLockBaseAddress(frame.capturedImage, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(frame.capturedImage, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(frame.capturedImage) else { continue }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(frame.capturedImage)

            for (i, point) in points.enumerated() {
                let worldPos = SIMD4<Float>(point.x, point.y, point.z, 1.0)
                let cameraPos = viewMatrix * worldPos
                guard cameraPos.z < 0 else { continue }

                let x = cameraPos.x / (-cameraPos.z)
                let y = cameraPos.y / (-cameraPos.z)
                let px = intrinsics[0][0] * x + intrinsics[2][0]
                let py = intrinsics[1][1] * y + intrinsics[2][1]

                guard px >= 0, px < Float(width), py >= 0, py < Float(height) else { continue }

                let centerDist = (px - cx) * (px - cx) + (py - cy) * (py - cy)
                if centerDist < bestCenterDist[i] {
                    bestCenterDist[i] = centerDist
                    let rgb = sampleYCbCrPixel(baseAddress: baseAddress, bytesPerRow: bytesPerRow,
                                                width: width, height: height, x: Int(px), y: Int(py), buffer: frame.capturedImage)
                    bestColors[i] = ColoredPoint(position: point, r: rgb.0, g: rgb.1, b: rgb.2)
                }
            }
        }

        return bestColors.compactMap { $0 }
    }

    // MARK: - YCbCr Pixel Sampling

    /// Sample a pixel from a YCbCr 420 biplanar buffer and convert to RGB.
    private static func sampleYCbCrPixel(
        baseAddress: UnsafeMutableRawPointer,
        bytesPerRow: Int,
        width: Int, height: Int,
        x: Int, y: Int,
        buffer: CVPixelBuffer
    ) -> (UInt8, UInt8, UInt8) {
        // Y plane (full resolution)
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let cbcrPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else {
            return (128, 128, 128)
        }

        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let cbcrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)

        let yValue = yPlane.advanced(by: y * yBytesPerRow + x).load(as: UInt8.self)

        // CbCr plane (half resolution)
        let cbcrX = x / 2
        let cbcrY = y / 2
        let cbcrOffset = cbcrY * cbcrBytesPerRow + cbcrX * 2
        let cb = cbcrPlane.advanced(by: cbcrOffset).load(as: UInt8.self)
        let cr = cbcrPlane.advanced(by: cbcrOffset + 1).load(as: UInt8.self)

        // YCbCr → RGB (BT.601)
        let yf = Float(yValue)
        let cbf = Float(cb) - 128.0
        let crf = Float(cr) - 128.0

        let r = UInt8(clamping: Int(yf + 1.402 * crf))
        let g = UInt8(clamping: Int(yf - 0.344 * cbf - 0.714 * crf))
        let b = UInt8(clamping: Int(yf + 1.772 * cbf))

        return (r, g, b)
    }
}
