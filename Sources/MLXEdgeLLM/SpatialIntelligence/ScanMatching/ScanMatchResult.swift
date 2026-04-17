// ScanMatchResult.swift — Scan matching result (Boeing Cartographer pattern)

import simd
import Foundation

/// Result of scan matching operation
public struct ScanMatchResult {
    /// Full 4x4 world-space alignment transform from ICP
    public let alignmentTransform: simd_float4x4
    /// XYZ translation delta in world-space meters (ARKit convention: +X east, +Y up, -Z north)
    public let translationMeters: SIMD3<Float>
    /// Match quality 0–1 (higher = more confident)
    public let score: Float
    /// Whether ICP converged within maxIterations
    public let converged: Bool
    /// Mean point-to-point residual (meters) at convergence
    public let meanResidual: Float

    public init(
        alignmentTransform: simd_float4x4 = matrix_identity_float4x4,
        translationMeters: SIMD3<Float>,
        score: Float,
        converged: Bool,
        meanResidual: Float = 0
    ) {
        self.alignmentTransform = alignmentTransform
        self.translationMeters = translationMeters
        self.score = max(0, min(1, score))
        self.converged = converged
        self.meanResidual = meanResidual
    }
}
