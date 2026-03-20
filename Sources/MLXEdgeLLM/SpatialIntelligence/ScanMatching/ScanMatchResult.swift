// ScanMatchResult.swift — Scan matching result (Boeing Cartographer pattern)

import simd
import Foundation

/// Result of scan matching operation
public struct ScanMatchResult {
    public let transform: simd_float3x3  // Rotation + translation
    public let score: Float  // Match quality 0-1
    public let converged: Bool  // Did algorithm converge

    public init(transform: simd_float3x3, score: Float, converged: Bool) {
        self.transform = transform
        self.score = max(0, min(1, score))
        self.converged = converged
    }
}
