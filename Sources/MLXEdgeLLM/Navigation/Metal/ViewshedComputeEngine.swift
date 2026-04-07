// ViewshedComputeEngine.swift — Metal pipeline host for GPU viewshed computation
// Extracts elevation grid from TerrainEngine, dispatches viewshedCompute kernel,
// reads back visibility buffer → ViewshedResult

import Foundation
import Metal
import CoreLocation

@MainActor
final class ViewshedComputeEngine {
    static let shared = ViewshedComputeEngine()

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLComputePipelineState?
    private var isReady = false

    private init() {
        setupMetal()
    }

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "viewshedCompute") else { return }

        do {
            pipelineState = try device.makeComputePipelineState(function: function)
            isReady = true
        } catch {
            isReady = false
        }
    }

    /// Compute viewshed on GPU, falling back to CPU raycast if Metal unavailable.
    func computeViewshed(
        from observer: CLLocationCoordinate2D,
        radius: Double = 2000,
        observerHeight: Double = 1.8,
        resolution: Int = 360,
        samplesPerRadial: Int = 200
    ) async -> ViewshedResult? {
        guard isReady, let device, let commandQueue, let pipelineState else {
            // CPU fallback via LOSRaycastEngine
            return cpuFallbackViewshed(
                from: observer, radius: radius,
                observerHeight: observerHeight,
                resolution: resolution, samplesPerRadial: samplesPerRadial
            )
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Extract elevation grid from TerrainEngine
        let gridData = extractElevationGrid(
            center: observer,
            radius: radius,
            cellSizeMeters: 30.0  // ~1 arc-second SRTM resolution
        )

        guard !gridData.elevations.isEmpty else { return nil }

        // Observer terrain elevation
        let obsTerrainElev = TerrainEngine.shared.elevationAt(coordinate: observer) ?? 0
        let obsTotal = obsTerrainElev + observerHeight

        // Create uniforms
        var uniforms = ViewshedUniforms(
            observerLatLon: SIMD2<Float>(Float(observer.latitude), Float(observer.longitude)),
            observerElevation: Float(obsTotal),
            radius: Float(radius),
            resolution: UInt32(resolution),
            samplesPerRadial: UInt32(samplesPerRadial),
            earthRadius: 6_371_000.0,
            gridWidth: UInt32(gridData.width),
            gridHeight: UInt32(gridData.height),
            gridOriginLatLon: SIMD2<Float>(Float(gridData.originLat), Float(gridData.originLon)),
            gridCellSize: Float(gridData.cellSizeDeg)
        )

        // Create Metal buffers
        let elevationSize = gridData.elevations.count * MemoryLayout<Float>.stride
        guard let elevationBuffer = device.makeBuffer(
            bytes: gridData.elevations,
            length: elevationSize,
            options: .storageModeShared
        ) else { return nil }

        let outputCount = resolution * samplesPerRadial
        let outputSize = outputCount * MemoryLayout<Float>.stride
        guard let outputBuffer = device.makeBuffer(
            length: outputSize,
            options: .storageModeShared
        ) else { return nil }

        guard let uniformBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<ViewshedUniforms>.stride,
            options: .storageModeShared
        ) else { return nil }

        // Dispatch compute
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(elevationBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(uniformBuffer, offset: 0, index: 2)

        let threadgroupSize = MTLSize(width: min(resolution, pipelineState.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        let gridSize = MTLSize(width: resolution, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        // Execute and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read back results
        let outputPointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: outputCount)
        let visibility = Array(UnsafeBufferPointer(start: outputPointer, count: outputCount))

        let computeTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return ViewshedResult(
            observer: observer,
            radius: radius,
            resolution: resolution,
            samplesPerRadial: samplesPerRadial,
            visibility: visibility,
            computeTimeMs: computeTimeMs
        )
    }

    // MARK: - Elevation Grid Extraction

    private struct GridData {
        let elevations: [Float]
        let width: Int
        let height: Int
        let originLat: Double
        let originLon: Double
        let cellSizeDeg: Double
    }

    private func extractElevationGrid(center: CLLocationCoordinate2D, radius: Double, cellSizeMeters: Double) -> GridData {
        // Compute bounding box
        let mPerDegLat = 111320.0
        let mPerDegLon = 111320.0 * cos(center.latitude * .pi / 180.0)

        let latExtent = radius / mPerDegLat
        let lonExtent = radius / max(mPerDegLon, 1.0)

        let cellSizeDeg = cellSizeMeters / mPerDegLat  // approx

        let originLat = center.latitude - latExtent
        let originLon = center.longitude - lonExtent

        let width = max(Int((2.0 * lonExtent) / cellSizeDeg), 2)
        let height = max(Int((2.0 * latExtent) / cellSizeDeg), 2)

        // Sample elevation grid
        var elevations = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for col in 0..<width {
                let lat = originLat + Double(row) * cellSizeDeg
                let lon = originLon + Double(col) * cellSizeDeg
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                let elev = TerrainEngine.shared.elevationAt(coordinate: coord) ?? 0
                elevations[row * width + col] = Float(elev)
            }
        }

        return GridData(
            elevations: elevations,
            width: width,
            height: height,
            originLat: originLat,
            originLon: originLon,
            cellSizeDeg: cellSizeDeg
        )
    }
}

    // MARK: - CPU Fallback

    private func cpuFallbackViewshed(
        from observer: CLLocationCoordinate2D,
        radius: Double,
        observerHeight: Double,
        resolution: Int,
        samplesPerRadial: Int
    ) -> ViewshedResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let cpuResult = LOSRaycastEngine.shared.computeViewshed(
            from: observer, radius: radius, resolution: resolution
        )

        // Convert CPU result (one entry per radial) to full visibility buffer
        var visibility = [Float](repeating: 0, count: resolution * samplesPerRadial)
        for (idx, entry) in cpuResult.enumerated() {
            // Fill all samples along this radial with same visibility
            for s in 0..<samplesPerRadial {
                visibility[idx * samplesPerRadial + s] = entry.isVisible ? 1.0 : 0.0
            }
        }

        let computeTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        return ViewshedResult(
            observer: observer,
            radius: radius,
            resolution: resolution,
            samplesPerRadial: samplesPerRadial,
            visibility: visibility,
            computeTimeMs: computeTimeMs
        )
    }
}

// MARK: - Metal Uniform Struct (must match .metal)

struct ViewshedUniforms {
    var observerLatLon: SIMD2<Float>
    var observerElevation: Float
    var radius: Float
    var resolution: UInt32
    var samplesPerRadial: UInt32
    var earthRadius: Float
    var gridWidth: UInt32
    var gridHeight: UInt32
    var gridOriginLatLon: SIMD2<Float>
    var gridCellSize: Float
}
