// PipelineBenchmark.swift — Per-component timing, memory, and thermal profiling
// Tracks performance of each pipeline stage for optimization and diagnostics

import Foundation

// MARK: - Component Timing

struct ComponentTiming {
    let name: String
    var totalMs: Double = 0
    var callCount: Int = 0
    var minMs: Double = .infinity
    var maxMs: Double = 0
    var lastMs: Double = 0

    var averageMs: Double {
        callCount > 0 ? totalMs / Double(callCount) : 0
    }

    mutating func record(_ ms: Double) {
        lastMs = ms
        totalMs += ms
        callCount += 1
        minMs = min(minMs, ms)
        maxMs = max(maxMs, ms)
    }
}

// MARK: - Pipeline Metrics

struct PipelineMetrics {
    var kalmanPredict: ComponentTiming = ComponentTiming(name: "Kalman Predict")
    var kalmanUpdate: ComponentTiming = ComponentTiming(name: "Kalman Update")
    var motionUndistortion: ComponentTiming = ComponentTiming(name: "Motion Undistortion")
    var clutterFilter: ComponentTiming = ComponentTiming(name: "Clutter Filter")
    var yoloInference: ComponentTiming = ComponentTiming(name: "YOLO Inference")
    var gaussianTraining: ComponentTiming = ComponentTiming(name: "Gaussian Training")
    var gaussianExtrapolation: ComponentTiming = ComponentTiming(name: "Gaussian Extrapolation")
    var hapticUpdate: ComponentTiming = ComponentTiming(name: "Haptic Update")
    var totalFrame: ComponentTiming = ComponentTiming(name: "Total Frame")

    var allComponents: [ComponentTiming] {
        [kalmanPredict, kalmanUpdate, motionUndistortion, clutterFilter,
         yoloInference, gaussianTraining, gaussianExtrapolation, hapticUpdate, totalFrame]
    }

    /// Total pipeline processing time budget usage (target: <33ms for 30fps)
    var budgetUsage: Float {
        Float(totalFrame.lastMs / 33.33)
    }
}

// MARK: - Memory Metrics

struct MemoryMetrics {
    let physicalMemoryUsed: UInt64      // bytes
    let physicalMemoryTotal: UInt64
    let gaussianCount: Int
    let pointCloudSize: Int

    var usagePercent: Float {
        physicalMemoryTotal > 0 ? Float(physicalMemoryUsed) / Float(physicalMemoryTotal) * 100 : 0
    }

    static func current(gaussianCount: Int = 0, pointCloudSize: Int = 0) -> MemoryMetrics {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let used = result == KERN_SUCCESS ? info.resident_size : 0
        let total = ProcessInfo.processInfo.physicalMemory

        return MemoryMetrics(
            physicalMemoryUsed: used,
            physicalMemoryTotal: total,
            gaussianCount: gaussianCount,
            pointCloudSize: pointCloudSize
        )
    }
}

// MARK: - Benchmark Snapshot

struct BenchmarkSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let metrics: PipelineMetrics
    let memory: MemoryMetrics
    let thermalLevel: ThermalLevel
    let fps: Double
}

// MARK: - PipelineBenchmark

@MainActor
final class PipelineBenchmark: ObservableObject {

    @Published private(set) var currentMetrics = PipelineMetrics()
    @Published private(set) var currentMemory = MemoryMetrics.current()
    @Published private(set) var fps: Double = 0
    @Published private(set) var snapshots: [BenchmarkSnapshot] = []

    private var frameTimestamps: [CFAbsoluteTime] = []
    private let fpsWindowSize = 30
    private let maxSnapshots = 300 // 5 minutes at 1/sec

    // Timing helpers
    private var componentStartTimes: [String: CFAbsoluteTime] = [:]

    // MARK: - Timing API

    /// Start timing a component
    func startTiming(_ component: String) {
        componentStartTimes[component] = CFAbsoluteTimeGetCurrent()
    }

    /// End timing and record the result
    func endTiming(_ component: String) {
        guard let startTime = componentStartTimes.removeValue(forKey: component) else { return }
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // ms

        switch component {
        case "kalmanPredict": currentMetrics.kalmanPredict.record(elapsed)
        case "kalmanUpdate": currentMetrics.kalmanUpdate.record(elapsed)
        case "motionUndistortion": currentMetrics.motionUndistortion.record(elapsed)
        case "clutterFilter": currentMetrics.clutterFilter.record(elapsed)
        case "yoloInference": currentMetrics.yoloInference.record(elapsed)
        case "gaussianTraining": currentMetrics.gaussianTraining.record(elapsed)
        case "gaussianExtrapolation": currentMetrics.gaussianExtrapolation.record(elapsed)
        case "hapticUpdate": currentMetrics.hapticUpdate.record(elapsed)
        case "totalFrame": currentMetrics.totalFrame.record(elapsed)
        default: break
        }
    }

    /// Convenience: measure a block and record timing
    func measure<T>(_ component: String, _ block: () -> T) -> T {
        startTiming(component)
        let result = block()
        endTiming(component)
        return result
    }

    /// Async version of measure
    func measure<T>(_ component: String, _ block: () async -> T) async -> T {
        startTiming(component)
        let result = await block()
        endTiming(component)
        return result
    }

    // MARK: - Frame Tracking

    func recordFrame() {
        let now = CFAbsoluteTimeGetCurrent()
        frameTimestamps.append(now)

        // Trim old timestamps
        while frameTimestamps.count > fpsWindowSize {
            frameTimestamps.removeFirst()
        }

        // Calculate FPS
        if frameTimestamps.count >= 2 {
            let duration = frameTimestamps.last! - frameTimestamps.first!
            fps = duration > 0 ? Double(frameTimestamps.count - 1) / duration : 0
        }
    }

    // MARK: - Snapshot

    func takeSnapshot(thermalLevel: ThermalLevel, gaussianCount: Int = 0, pointCloudSize: Int = 0) {
        currentMemory = MemoryMetrics.current(gaussianCount: gaussianCount, pointCloudSize: pointCloudSize)

        let snapshot = BenchmarkSnapshot(
            timestamp: Date(),
            metrics: currentMetrics,
            memory: currentMemory,
            thermalLevel: thermalLevel,
            fps: fps
        )

        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst()
        }
    }

    // MARK: - Report

    func printReport() {
        print("=== LiDAR Pipeline Benchmark ===")
        print(String(format: "FPS: %.1f | Budget: %.0f%%", fps, currentMetrics.budgetUsage * 100))
        print(String(format: "Memory: %.0f MB / %.0f MB (%.0f%%)",
                     Double(currentMemory.physicalMemoryUsed) / 1e6,
                     Double(currentMemory.physicalMemoryTotal) / 1e6,
                     currentMemory.usagePercent))
        print("--- Component Timings ---")
        for c in currentMetrics.allComponents where c.callCount > 0 {
            print(String(format: "  %-24s avg: %6.2f ms  min: %6.2f  max: %6.2f  calls: %d",
                         c.name, c.averageMs, c.minMs, c.maxMs, c.callCount))
        }
        print("============================")
    }

    func reset() {
        currentMetrics = PipelineMetrics()
        frameTimestamps.removeAll()
        snapshots.removeAll()
        fps = 0
    }
}
