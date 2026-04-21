// ModelPerformanceMonitor.swift — Track on-device inference latency, memory, and throughput.
// Hooks into LocalInferenceEngine. Alerts on degradation. Recommends power/quality tradeoffs.
// No internet required. All metrics are ephemeral (current session only).

import Foundation
import SwiftUI

// MARK: - InferenceSample

struct InferenceSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let latencyMs: Double       // wall-clock ms for full response
    let tokensGenerated: Int
    let promptTokens: Int
    let memoryMB: Double        // resident memory at end of inference
    var tokensPerSec: Double { latencyMs > 0 ? Double(tokensGenerated) / (latencyMs / 1000) : 0 }
}

// MARK: - PerformanceAlert

enum PerformanceAlert: String, Identifiable {
    case latencySpike    = "Latency spike — inference > 3x baseline"
    case memoryPressure  = "Memory pressure — resident memory > 2 GB"
    case throughputDrop  = "Throughput drop — < 5 tokens/sec"
    case thermalThrottle = "Possible thermal throttle detected"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .latencySpike:    return "bolt.trianglebadge.exclamationmark"
        case .memoryPressure:  return "memorychip"
        case .throughputDrop:  return "tortoise.fill"
        case .thermalThrottle: return "thermometer.sun.fill"
        }
    }
    var color: Color {
        switch self {
        case .latencySpike, .memoryPressure: return ZDDesign.signalRed
        case .throughputDrop, .thermalThrottle: return ZDDesign.safetyYellow
        }
    }
}

// MARK: - PowerQualityMode

enum PowerQualityMode: String, CaseIterable {
    case performance = "Performance"
    case balanced    = "Balanced"
    case efficiency  = "Efficiency"
    var icon: String {
        switch self {
        case .performance: return "bolt.fill"
        case .balanced:    return "gauge.with.dots.needle.50percent"
        case .efficiency:  return "leaf.fill"
        }
    }
    var description: String {
        switch self {
        case .performance: return "Max quality, higher battery drain"
        case .balanced:    return "Default tradeoff"
        case .efficiency:  return "Reduce context length, longer prompts batched"
        }
    }
    var color: Color {
        switch self {
        case .performance: return .orange
        case .balanced:    return ZDDesign.cyanAccent
        case .efficiency:  return ZDDesign.successGreen
        }
    }
}

// MARK: - ModelPerformanceMonitor

@MainActor
final class ModelPerformanceMonitor: ObservableObject {
    static let shared = ModelPerformanceMonitor()

    @Published var samples: [InferenceSample] = []
    @Published var activeAlerts: [PerformanceAlert] = []
    @Published var recommendedMode: PowerQualityMode = .balanced

    private let maxSamples = 200
    private init() {}

    // MARK: - Record Sample

    /// Call this after each inference completes.
    func record(latencyMs: Double, tokensGenerated: Int, promptTokens: Int) {
        let mem = currentMemoryMB()
        let sample = InferenceSample(
            timestamp: Date(),
            latencyMs: latencyMs,
            tokensGenerated: tokensGenerated,
            promptTokens: promptTokens,
            memoryMB: mem
        )
        samples.append(sample)
        if samples.count > maxSamples { samples.removeFirst(samples.count - maxSamples) }
        evaluateAlerts(latest: sample)
    }

    // MARK: - Memory

    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    // MARK: - Alert Evaluation

    private func evaluateAlerts(latest: InferenceSample) {
        var alerts: [PerformanceAlert] = []

        // Latency spike: latest > 3x rolling median
        if samples.count >= 5 {
            let sorted = samples.dropLast().map(\.latencyMs).sorted()
            let median = sorted[sorted.count / 2]
            if latest.latencyMs > median * 3 { alerts.append(.latencySpike) }
        }

        // Memory > 2 GB
        if latest.memoryMB > 2048 { alerts.append(.memoryPressure) }

        // Throughput < 5 tok/s
        if latest.tokensPerSec < 5 && latest.tokensGenerated > 10 { alerts.append(.throughputDrop) }

        // Thermal: latency doubled in last 5 samples
        if samples.count >= 10 {
            let first5 = samples.suffix(10).prefix(5).map(\.latencyMs)
            let last5  = samples.suffix(5).map(\.latencyMs)
            let avg1 = first5.reduce(0, +) / 5
            let avg2 = last5.reduce(0, +) / 5
            if avg2 > avg1 * 2 && avg1 > 0 { alerts.append(.thermalThrottle) }
        }

        activeAlerts = alerts

        // Recommend mode
        if alerts.contains(.memoryPressure) || alerts.contains(.thermalThrottle) {
            recommendedMode = .efficiency
        } else if alerts.isEmpty {
            recommendedMode = .performance
        } else {
            recommendedMode = .balanced
        }
    }

    // MARK: - Stats

    var averageLatencyMs: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.latencyMs).reduce(0, +) / Double(samples.count)
    }

    var averageTokensPerSec: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.tokensPerSec).reduce(0, +) / Double(samples.count)
    }

    var peakMemoryMB: Double { samples.map(\.memoryMB).max() ?? 0 }
    var currentMemory: Double { currentMemoryMB() }

    var totalInferences: Int { samples.count }
}

// MARK: - ModelPerformanceView

struct ModelPerformanceView: View {
    @ObservedObject private var mon = ModelPerformanceMonitor.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if !mon.activeAlerts.isEmpty { alertsCard }
                        statsCard
                        recommendationCard
                        if !mon.samples.isEmpty { latencyChartCard }
                    }
                    .padding()
                }
            }
            .navigationTitle("Model Monitor")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mon.samples.removeAll(); mon.activeAlerts.removeAll() } label: {
                        Image(systemName: "trash").foregroundColor(ZDDesign.signalRed)
                    }
                    .disabled(mon.samples.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Alerts

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE ALERTS").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(mon.activeAlerts) { alert in
                HStack(spacing: 10) {
                    Image(systemName: alert.icon).foregroundColor(alert.color)
                    Text(alert.rawValue).font(.caption).foregroundColor(ZDDesign.pureWhite)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ZDDesign.signalRed.opacity(0.4), lineWidth: 1))
    }

    // MARK: Stats

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PERFORMANCE METRICS").font(.caption.bold()).foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statPill(v: String(format: "%.0f ms", mon.averageLatencyMs), l: "Avg Latency", c: ZDDesign.cyanAccent)
                statPill(v: String(format: "%.1f t/s", mon.averageTokensPerSec), l: "Avg Toks/sec", c: ZDDesign.successGreen)
                statPill(v: String(format: "%.0f MB", mon.currentMemory), l: "Memory Now", c: .orange)
                statPill(v: String(format: "%.0f MB", mon.peakMemoryMB), l: "Peak Memory", c: ZDDesign.signalRed)
                statPill(v: "\(mon.totalInferences)", l: "Inferences", c: ZDDesign.mediumGray)
                statPill(v: mon.samples.isEmpty ? "—" : String(format: "%.0f ms", mon.samples.last!.latencyMs),
                         l: "Last Latency", c: ZDDesign.pureWhite)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Recommendation

    private var recommendationCard: some View {
        let mode = mon.recommendedMode
        return VStack(alignment: .leading, spacing: 8) {
            Text("RECOMMENDED MODE").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 12) {
                Image(systemName: mode.icon).font(.title2).foregroundColor(mode.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue).font(.headline.bold()).foregroundColor(mode.color)
                    Text(mode.description).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Latency Chart

    private var latencyChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LATENCY HISTORY").font(.caption.bold()).foregroundColor(.secondary)
            GeometryReader { _ in
                let pts = mon.samples.suffix(60)
                Canvas { ctx, size in
                    guard pts.count > 1 else { return }
                    let maxL = pts.map(\.latencyMs).max() ?? 1
                    let minL = 0.0
                    let range = max(1, maxL - minL)
                    var path = Path()
                    for (i, s) in pts.enumerated() {
                        let x = CGFloat(i) / CGFloat(pts.count - 1) * size.width
                        let y = size.height - CGFloat((s.latencyMs - minL) / range) * size.height
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(path, with: .color(ZDDesign.cyanAccent), lineWidth: 1.5)
                    // Average line
                    let avg = mon.averageLatencyMs
                    let avgY = size.height - CGFloat((avg - minL) / range) * size.height
                    var avgPath = Path()
                    avgPath.move(to: CGPoint(x: 0, y: avgY))
                    avgPath.addLine(to: CGPoint(x: size.width, y: avgY))
                    ctx.stroke(avgPath, with: .color(.gray.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 80)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
            HStack {
                Text("Last \(min(60, mon.samples.count)) inferences").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "Max: %.0f ms", mon.samples.suffix(60).map(\.latencyMs).max() ?? 0))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func statPill(v: String, l: String, c: Color) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.caption.bold()).foregroundColor(c)
            Text(l).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(c.opacity(0.08)).cornerRadius(8)
    }
}
