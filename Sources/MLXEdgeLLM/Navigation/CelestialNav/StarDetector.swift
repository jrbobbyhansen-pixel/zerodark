// StarDetector.swift — Detect bright stars in video frames (NASA COTS-Star-Tracker pattern)

import AVFoundation
import Vision
import Accelerate

/// Detected star in image
public struct DetectedStar {
    public let x: Int
    public let y: Int
    public let brightness: Float

    public init(x: Int, y: Int, brightness: Float) {
        self.x = x
        self.y = y
        self.brightness = brightness
    }
}

/// Star detector using image processing
public class StarDetector {
    private let brightnessThreshold: Float = 200  // 0-255 grayscale
    private let minBlobSize: Int = 5  // Minimum pixels for valid star

    public init() {}

    /// Detect stars in pixel buffer
    public func detect(in pixelBuffer: CVPixelBuffer) -> [DetectedStar] {
        // Convert to grayscale
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let grayscale = convertToGrayscale(pixelBuffer, width: width, height: height) else {
            return []
        }

        // Find bright pixels above threshold
        var brightPixels: [(Int, Int)] = []

        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                if idx < grayscale.count && grayscale[idx] > brightnessThreshold {
                    brightPixels.append((x, y))
                }
            }
        }

        // Cluster bright pixels into blobs (simple connectivity)
        var visited: [(Int, Int)] = []
        var stars: [DetectedStar] = []

        for pixel in brightPixels {
            guard !visited.contains(where: { $0 == pixel }) else { continue }

            // BFS cluster
            var blob: [(Int, Int)] = []
            var queue = [pixel]

            while !queue.isEmpty {
                let current = queue.removeFirst()
                if visited.contains(where: { $0 == current }) { continue }

                visited.append(current)
                blob.append(current)

                // Check 8-neighbors
                for dx in -1...1 {
                    for dy in -1...1 {
                        guard dx != 0 || dy != 0 else { continue }
                        let neighbor = (current.0 + dx, current.1 + dy)
                        if !visited.contains(where: { $0 == neighbor }) && brightPixels.contains(where: { $0 == neighbor }) {
                            queue.append(neighbor)
                        }
                    }
                }
            }

            // Compute blob centroid if large enough
            if blob.count >= minBlobSize {
                let avgX = Int(Float(blob.map { $0.0 }.reduce(0, +)) / Float(blob.count))
                let avgY = Int(Float(blob.map { $0.1 }.reduce(0, +)) / Float(blob.count))
                let brightness = grayscale[avgY * width + avgX]

                stars.append(DetectedStar(x: avgX, y: avgY, brightness: brightness))
            }
        }

        return stars
    }

    /// Convert pixel buffer to grayscale
    private func convertToGrayscale(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Float]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var grayscale = [Float](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4  // Assume BGRA

                let b = Float(buffer[offset])
                let g = Float(buffer[offset + 1])
                let r = Float(buffer[offset + 2])

                // Standard grayscale formula
                grayscale[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        return grayscale
    }
}
