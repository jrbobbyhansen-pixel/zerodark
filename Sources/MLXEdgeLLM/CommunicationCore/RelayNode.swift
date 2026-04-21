// RelayNode.swift — Dedicated mesh relay node configuration
// Optimize device for message forwarding: keep-awake, low UI overhead.
// Show relay statistics: packets forwarded, active routes, uptime, throughput graph.

import Foundation
import SwiftUI

// MARK: - RelayStats

struct RelayStats {
    var packetsForwarded: Int = 0
    var bytesForwarded: Int = 0
    var activeRoutes: Int = 0
    var uplinkTime: Date?
    var peakThroughputBPS: Double = 0
    var recentThroughputSamples: [Double] = []   // last 60 samples (1s each)

    var uptimeFormatted: String {
        guard let start = uplinkTime else { return "—" }
        let s = Int(Date().timeIntervalSince(start))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }

    var totalKilobytes: Double { Double(bytesForwarded) / 1024 }
    var avgThroughputBPS: Double {
        guard !recentThroughputSamples.isEmpty else { return 0 }
        return recentThroughputSamples.reduce(0, +) / Double(recentThroughputSamples.count)
    }
}

// MARK: - RelayOptimizationLevel

enum RelayOptimizationLevel: String, CaseIterable, Codable {
    case balanced     = "Balanced"
    case performance  = "Performance"
    case batteryFirst = "Battery First"

    var description: String {
        switch self {
        case .balanced:     return "Normal mesh participation"
        case .performance:  return "Maximize forwarding, higher battery drain"
        case .batteryFirst: return "Extend runtime, throttle non-critical packets"
        }
    }

    var icon: String {
        switch self {
        case .balanced:     return "equal.circle.fill"
        case .performance:  return "bolt.fill"
        case .batteryFirst: return "battery.100.bolt"
        }
    }

    var color: Color {
        switch self {
        case .balanced:     return ZDDesign.cyanAccent
        case .performance:  return .orange
        case .batteryFirst: return ZDDesign.successGreen
        }
    }
}

// MARK: - MeshRelayManager

@MainActor
final class MeshRelayManager: ObservableObject {
    static let shared = MeshRelayManager()

    @Published var isActive = false
    @Published var optimization: RelayOptimizationLevel = .balanced
    @Published var stats = RelayStats()

    private var statsTimer: Timer?
    private var pendingBytes: Int = 0

    private init() {
        subscribeMesh()
    }

    // MARK: - Start / Stop

    func start() {
        guard !isActive else { return }
        isActive = true
        stats = RelayStats()
        stats.uplinkTime = Date()
        stats.activeRoutes = max(1, MeshService.shared.peers.count)

        applyOptimization()

        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sampleStats() }
        }

        AuditLogger.shared.log(.meshJoined, detail: "relay_started opt:\(optimization.rawValue)")
    }

    func stop() {
        isActive = false
        statsTimer?.invalidate()
        statsTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        AuditLogger.shared.log(.meshLeft, detail: "relay_stopped fwd:\(stats.packetsForwarded)")
    }

    func applyOptimization() {
        UIApplication.shared.isIdleTimerDisabled = (optimization == .performance || optimization == .balanced)
    }

    // MARK: - Stats Sampling

    private func sampleStats() {
        guard isActive else { return }
        let bps = Double(pendingBytes)
        pendingBytes = 0
        stats.recentThroughputSamples.append(bps)
        if stats.recentThroughputSamples.count > 60 {
            stats.recentThroughputSamples.removeFirst()
        }
        if bps > stats.peakThroughputBPS { stats.peakThroughputBPS = bps }
        stats.activeRoutes = max(1, MeshService.shared.peers.filter { $0.status == .online }.count)
    }

    // MARK: - Mesh Subscribe

    private func subscribeMesh() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.meshMessage"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            Task { @MainActor [weak self] in
                guard self?.isActive == true else { return }
                self?.stats.packetsForwarded += 1
                let bytes = text.utf8.count
                self?.stats.bytesForwarded += bytes
                self?.pendingBytes += bytes
            }
        }
    }

    // MARK: - Battery estimate

    var estimatedHoursRemaining: Double? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        guard level > 0 else { return nil }
        let drainPerHour: Double
        switch optimization {
        case .performance:  drainPerHour = 0.15
        case .balanced:     drainPerHour = 0.08
        case .batteryFirst: drainPerHour = 0.04
        }
        return Double(level) / drainPerHour
    }
}

// MARK: - RelayNodeView

struct RelayNodeView: View {
    @ObservedObject private var relay = MeshRelayManager.shared
    @ObservedObject private var mesh = MeshService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        relayControlCard
                        if relay.isActive {
                            statsCard
                            throughputCard
                        }
                        optimizationCard
                        batteryCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Relay Node")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Control Card

    private var relayControlCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(relay.isActive ? ZDDesign.successGreen : ZDDesign.mediumGray)
                            .frame(width: 10, height: 10)
                        Text(relay.isActive ? "RELAY ACTIVE" : "RELAY INACTIVE")
                            .font(.caption.bold())
                            .foregroundColor(relay.isActive ? ZDDesign.successGreen : .secondary)
                    }
                    if relay.isActive {
                        Text("Uptime: \(relay.stats.uptimeFormatted)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    if relay.isActive { relay.stop() } else { relay.start() }
                } label: {
                    Text(relay.isActive ? "Stop" : "Start Relay")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(relay.isActive ? ZDDesign.signalRed : ZDDesign.successGreen)
                        .cornerRadius(8)
                }
            }

            if relay.isActive && mesh.peers.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(ZDDesign.safetyYellow)
                    Text("No mesh peers — relay has no traffic to forward.")
                        .font(.caption).foregroundColor(ZDDesign.safetyYellow)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 12) {
            Text("RELAY STATISTICS").font(.caption.bold()).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statPill(value: "\(relay.stats.packetsForwarded)", label: "Packets", icon: "arrow.triangle.2.circlepath", color: ZDDesign.cyanAccent)
                statPill(value: String(format: "%.1f KB", relay.stats.totalKilobytes), label: "Forwarded", icon: "tray.and.arrow.up.fill", color: .green)
                statPill(value: "\(relay.stats.activeRoutes)", label: "Active Routes", icon: "point.3.connected.trianglepath.dotted", color: .orange)
                statPill(value: String(format: "%.0f B/s", relay.stats.avgThroughputBPS), label: "Avg Throughput", icon: "speedometer", color: .purple)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Throughput Chart

    private var throughputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("THROUGHPUT (60s)").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "Peak: %.0f B/s", relay.stats.peakThroughputBPS))
                    .font(.caption2).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                let samples = relay.stats.recentThroughputSamples
                let maxVal = max(1, samples.max() ?? 1)
                Canvas { ctx, size in
                    guard samples.count > 1 else { return }
                    let w = size.width / CGFloat(samples.count - 1)
                    var path = Path()
                    for (i, val) in samples.enumerated() {
                        let x = CGFloat(i) * w
                        let y = size.height - CGFloat(val / maxVal) * size.height
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(path, with: .color(ZDDesign.cyanAccent), lineWidth: 1.5)
                }
            }
            .frame(height: 60)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Optimization Card

    private var optimizationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPTIMIZATION MODE").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(RelayOptimizationLevel.allCases, id: \.self) { level in
                Button {
                    relay.optimization = level
                    if relay.isActive { relay.applyOptimization() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: level.icon).foregroundColor(level.color).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.rawValue).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text(level.description).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if relay.optimization == level {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundColor(level.color)
                        }
                    }
                    .padding(10)
                    .background(relay.optimization == level ? level.color.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Battery Card

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BATTERY MANAGEMENT").font(.caption.bold()).foregroundColor(.secondary)
            if let hours = relay.estimatedHoursRemaining {
                HStack {
                    Image(systemName: "clock.fill").foregroundColor(ZDDesign.cyanAccent)
                    Text(String(format: "Est. relay runtime: %.1f hours", hours))
                        .font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                }
            }
            Text("Tips: close all apps, enable Low Power Mode, and use a charging cable during extended relay operations.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func statPill(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundColor(color)
            Text(value).font(.headline.bold()).foregroundColor(ZDDesign.pureWhite)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}
