// CurrentEstimator.swift — River current speed & direction from terrain gradient + channel width.
// Uses Manning's equation and channel geometry to estimate cross-section velocity.
// Calculates drift offset for water crossings and time-of-submersion.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - ChannelProfile

struct ChannelProfile {
    let widthM: Double          // estimated channel width (m)
    let depthM: Double          // estimated mean depth (m)
    let gradientPct: Double     // bed slope as a percentage
    let manningN: Double        // roughness coefficient
    let bankAngleDeg: Double    // average bank steepness

    /// Manning's equation: V = (1/n) * R^(2/3) * S^(1/2)
    /// R = hydraulic radius ≈ depth for wide channels
    var currentSpeedMps: Double {
        let R = depthM   // hydraulic radius ≈ mean depth for wide channels
        let S = gradientPct / 100.0
        return (1.0 / manningN) * pow(R, 2.0/3.0) * pow(S, 0.5)
    }

    var froude: Double {
        guard depthM > 0 else { return 0 }
        return currentSpeedMps / sqrt(9.81 * depthM)
    }

    var flowRegime: FlowRegime {
        if froude < 0.85 { return .subcritical }
        if froude < 1.15 { return .critical }
        return .supercritical
    }
}

enum FlowRegime: String {
    case subcritical   = "Subcritical (smooth)"
    case critical      = "Critical (turbulent)"
    case supercritical = "Supercritical (rapid)"

    var color: Color {
        switch self {
        case .subcritical:   return ZDDesign.successGreen
        case .critical:      return ZDDesign.safetyYellow
        case .supercritical: return ZDDesign.signalRed
        }
    }
}

// MARK: - Manning's N presets

enum ChannelRoughness: String, CaseIterable, Identifiable {
    case cleanChannel   = "Clean Channel"
    case grassBed       = "Grass/Sand Bed"
    case gravel         = "Gravel"
    case cobble         = "Cobble"
    case boulder        = "Boulders"
    case heavyVeg       = "Heavy Vegetation"

    var id: String { rawValue }
    var n: Double {
        switch self {
        case .cleanChannel: return 0.025
        case .grassBed:     return 0.035
        case .gravel:       return 0.040
        case .cobble:       return 0.055
        case .boulder:      return 0.075
        case .heavyVeg:     return 0.100
        }
    }
}

// MARK: - CrossingDrift

struct CrossingDrift {
    let crossingWidthM: Double
    let swimSpeedMps: Double        // person's swim speed perpendicular to current
    let currentSpeedMps: Double
    let currentBearingDeg: Double   // direction current flows

    /// Time to cross at perpendicular swim speed
    var crossingTimeSec: Double { crossingWidthM / max(0.01, swimSpeedMps) }

    /// Downstream drift in metres
    var driftM: Double { currentSpeedMps * crossingTimeSec }

    /// Landing bearing offset from direct crossing
    var driftAngleDeg: Double {
        atan2(driftM, crossingWidthM) * 180 / .pi
    }

    /// Danger: current > 1.5 m/s is swift water rescue threshold
    var isSwiftWater: Bool { currentSpeedMps > 1.5 }

    var riskLabel: String {
        switch currentSpeedMps {
        case 0..<0.5:  return "Calm — easy wade"
        case 0.5..<1.0: return "Moderate — swim assist"
        case 1.0..<1.5: return "Fast — rope required"
        case 1.5..<2.5: return "Swift — trained rescue only"
        default:        return "Extreme — no crossing"
        }
    }
    var riskColor: Color {
        switch currentSpeedMps {
        case 0..<0.5:  return ZDDesign.successGreen
        case 0.5..<1.0: return ZDDesign.safetyYellow
        case 1.0..<1.5: return .orange
        default:        return ZDDesign.signalRed
        }
    }
}

// MARK: - CurrentEstimatorEngine

enum CurrentEstimatorEngine {

    /// Estimate channel profile from a WaterCrossing candidate + optional SRTM gradient.
    static func estimateProfile(
        crossing: WaterCrossing,
        roughness: ChannelRoughness,
        useTerrainGradient: Bool = true
    ) -> ChannelProfile {
        // Width from WaterCrossing.estimatedWidthM
        let widthM = crossing.estimatedWidthM

        // Depth heuristic: wide rivers are deeper; use log-relation
        // Based on: d ≈ 0.26 * W^0.4 (empirical for natural channels)
        let depthM = 0.26 * pow(widthM, 0.4)

        // Gradient: use terrain approach slope as proxy if available
        let gradPct: Double
        if useTerrainGradient {
            let avgSlopeDeg = (crossing.approachSlopeDeg + crossing.departureSlopeDeg) / 2
            // Bed gradient ≈ half the valley slope (accounts for channel sinuosity)
            gradPct = tan(avgSlopeDeg * .pi / 180) * 50  // 50% of valley slope
        } else {
            gradPct = 0.5   // default 0.5% gradient
        }

        return ChannelProfile(
            widthM: widthM,
            depthM: depthM,
            gradientPct: max(0.01, gradPct),
            manningN: roughness.n,
            bankAngleDeg: (crossing.approachSlopeDeg + crossing.departureSlopeDeg) / 2
        )
    }

    /// Calculate drift for a person crossing a channel.
    static func calculateDrift(
        profile: ChannelProfile,
        crossingWidthM: Double,
        swimSpeedMps: Double = 0.8,
        currentBearingDeg: Double = 90   // default: river flows east
    ) -> CrossingDrift {
        CrossingDrift(
            crossingWidthM: crossingWidthM,
            swimSpeedMps: swimSpeedMps,
            currentSpeedMps: profile.currentSpeedMps,
            currentBearingDeg: currentBearingDeg
        )
    }
}

// MARK: - CurrentEstimatorManager

@MainActor
final class CurrentEstimatorManager: ObservableObject {
    static let shared = CurrentEstimatorManager()

    @Published var selectedCrossing: WaterCrossing? = nil
    @Published var roughness: ChannelRoughness = .gravel
    @Published var swimSpeedMps: Double = 0.8
    @Published var currentBearingDeg: Double = 90
    @Published var profile: ChannelProfile? = nil
    @Published var drift: CrossingDrift? = nil

    private init() {}

    func estimate() {
        guard let crossing = selectedCrossing else { return }
        let p = CurrentEstimatorEngine.estimateProfile(crossing: crossing, roughness: roughness)
        let d = CurrentEstimatorEngine.calculateDrift(
            profile: p,
            crossingWidthM: crossing.estimatedWidthM,
            swimSpeedMps: swimSpeedMps,
            currentBearingDeg: currentBearingDeg
        )
        profile = p
        drift = d
    }
}

// MARK: - CurrentEstimatorView

struct CurrentEstimatorView: View {
    @ObservedObject private var mgr = CurrentEstimatorManager.shared
    @ObservedObject private var analyzer = WaterCrossingAnalyzer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Crossing picker
                        crossingPickerCard
                        // Channel settings
                        settingsCard
                        if let p = mgr.profile {
                            profileCard(p)
                        }
                        if let d = mgr.drift {
                            driftCard(d)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Current Estimator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mgr.estimate()
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .onAppear {
                if mgr.selectedCrossing == nil {
                    mgr.selectedCrossing = analyzer.crossings.first
                }
                mgr.estimate()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Crossing Picker

    private var crossingPickerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CROSSING SITE").font(.caption.bold()).foregroundColor(.secondary)
            if analyzer.crossings.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.circle").foregroundColor(.secondary)
                    Text("No crossings found. Analyze terrain in Water Crossings.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(analyzer.crossings.prefix(8)) { c in
                            let isSelected = mgr.selectedCrossing?.id == c.id
                            Button {
                                mgr.selectedCrossing = c
                                mgr.estimate()
                            } label: {
                                VStack(spacing: 3) {
                                    Text(String(format: "%.0fm", c.estimatedWidthM))
                                        .font(.caption.bold())
                                        .foregroundColor(isSelected ? ZDDesign.cyanAccent : ZDDesign.pureWhite)
                                    Text(c.safetyLabel)
                                        .font(.system(size: 9))
                                        .foregroundColor(c.safetyColor)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(isSelected ? ZDDesign.cyanAccent.opacity(0.15) : ZDDesign.darkCard)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? ZDDesign.cyanAccent : Color.clear, lineWidth: 1))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHANNEL CONDITIONS").font(.caption.bold()).foregroundColor(.secondary)
            HStack {
                Text("Bed type").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $mgr.roughness) {
                    ForEach(ChannelRoughness.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .tint(ZDDesign.cyanAccent)
            }
            HStack {
                Text("Swim speed").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f m/s", mgr.swimSpeedMps)).font(.caption).foregroundColor(ZDDesign.pureWhite)
            }
            Slider(value: $mgr.swimSpeedMps, in: 0.3...2.0, step: 0.1)
                .tint(ZDDesign.cyanAccent)
                .onChange(of: mgr.swimSpeedMps) { _, _ in mgr.estimate() }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Profile Card

    private func profileCard(_ p: ChannelProfile) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CHANNEL PROFILE").font(.caption.bold()).foregroundColor(.secondary)
                    Text(String(format: "%.1f m/s", p.currentSpeedMps))
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("current speed").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    regimeBadge(p.flowRegime)
                    froudeBadge(p.froude)
                }
            }
            Divider().background(ZDDesign.mediumGray.opacity(0.2))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCell("Width", String(format: "%.0fm", p.widthM))
                metricCell("Depth", String(format: "%.1fm", p.depthM))
                metricCell("Gradient", String(format: "%.2f%%", p.gradientPct))
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func regimeBadge(_ regime: FlowRegime) -> some View {
        Text(regime.rawValue)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(regime.color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(regime.color.opacity(0.15))
            .cornerRadius(6)
    }

    private func froudeBadge(_ f: Double) -> some View {
        Text(String(format: "Fr %.2f", f))
            .font(.caption2).foregroundColor(.secondary)
    }

    // MARK: Drift Card

    private func driftCard(_ d: CrossingDrift) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CROSSING DRIFT").font(.caption.bold()).foregroundColor(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.riskLabel).font(.subheadline.bold()).foregroundColor(d.riskColor)
                    if d.isSwiftWater {
                        Label("SWIFT WATER — rope or rescue team required", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundColor(ZDDesign.signalRed)
                    }
                }
                Spacer()
            }
            Divider().background(ZDDesign.mediumGray.opacity(0.2))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCell("Drift", String(format: "%.0fm", d.driftM))
                metricCell("Angle", String(format: "%.0f°", d.driftAngleDeg))
                metricCell("Cross time", String(format: "%.0fs", d.crossingTimeSec))
                metricCell("Width", String(format: "%.0fm", d.crossingWidthM))
            }
            // Drift diagram using Canvas
            driftDiagram(d)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func driftDiagram(_ d: CrossingDrift) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let scaleM = w / max(1, d.crossingWidthM + d.driftM + 10)

            // Banks
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: h)) },
                       with: .color(ZDDesign.cyanAccent), lineWidth: 2)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: d.crossingWidthM * scaleM, y: 0)); p.addLine(to: CGPoint(x: d.crossingWidthM * scaleM, y: h)) },
                       with: .color(ZDDesign.cyanAccent), lineWidth: 2)

            // Desired crossing (straight across)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 5, y: h - 10))
                p.addLine(to: CGPoint(x: d.crossingWidthM * scaleM - 5, y: h - 10))
            }, with: .color(.green.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [4]))

            // Actual drift path
            let endX = (d.crossingWidthM + d.driftM) * scaleM
            let endY: CGFloat = h - 10
            let startY: CGFloat = 10
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: 5, y: startY))
                p.addLine(to: CGPoint(x: min(endX, w - 5), y: endY))
            }, with: .color(d.riskColor), lineWidth: 2)

            // Labels
            ctx.draw(Text("Start").font(.system(size: 9)).foregroundColor(.secondary),
                     at: CGPoint(x: 12, y: 20))
            ctx.draw(Text(String(format: "+%.0fm drift", d.driftM)).font(.system(size: 9)).foregroundColor(d.riskColor),
                     at: CGPoint(x: min(endX, w - 30), y: endY - 12))
        }
        .frame(height: 80)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.2))
        .cornerRadius(6)
    }
}
