// AvalancheAnalyzer.swift — Avalanche terrain analysis from slope/aspect data.
// Identifies prone zones (30-45°), terrain traps (gullies, convexities, cliff bases),
// rates overall avalanche risk, and suggests safe travel corridors.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - AvalancheRisk

enum AvalancheRisk: String, CaseIterable {
    case low       = "Low"
    case moderate  = "Moderate"
    case considerable = "Considerable"
    case high      = "High"
    case extreme   = "Extreme"

    var color: Color {
        switch self {
        case .low:          return ZDDesign.successGreen
        case .moderate:     return ZDDesign.safetyYellow
        case .considerable: return Color.orange
        case .high:         return ZDDesign.signalRed
        case .extreme:      return Color(red: 0.6, green: 0, blue: 0.8)
        }
    }

    var numericValue: Int {
        switch self { case .low: return 1; case .moderate: return 2;
                      case .considerable: return 3; case .high: return 4; case .extreme: return 5 }
    }
}

// MARK: - TerrainTrapType

enum TerrainTrapType: String, CaseIterable {
    case gully       = "Gully"
    case cliffBase   = "Cliff Base"
    case convexRoll  = "Convex Roll"
    case narrowCross = "Narrow Crossing"
    case treeWell    = "Tree Well"

    var icon: String {
        switch self {
        case .gully:       return "arrow.down.to.line"
        case .cliffBase:   return "mountain.2.fill"
        case .convexRoll:  return "chart.line.uptrend.xyaxis"
        case .narrowCross: return "arrow.left.and.right.circle"
        case .treeWell:    return "tree.fill"
        }
    }
}

// MARK: - AvalancheZone

struct AvalancheZone: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let slopeDeg: Double
    let aspectDeg: Double
    let risk: AvalancheRisk
    let traps: [TerrainTrapType]

    var isProne: Bool { slopeDeg >= 30 && slopeDeg <= 45 }
    var isCritical: Bool { risk == .high || risk == .extreme }

    var aspectCardinal: String {
        guard aspectDeg >= 0 else { return "Flat" }
        let dirs = ["N","NE","E","SE","S","SW","W","NW","N"]
        return dirs[Int((aspectDeg + 22.5) / 45.0) % 8]
    }
}

// MARK: - AvalancheAnalysis

struct AvalancheAnalysis {
    let timestamp: Date
    let zones: [AvalancheZone]
    let overallRisk: AvalancheRisk
    let proneZoneCount: Int
    let trapCount: Int
    let safeCorridors: [String]           // directional advice
    let keyFactors: [String]
    let totalZones: Int

    var pronePercent: Double {
        guard totalZones > 0 else { return 0 }
        return Double(proneZoneCount) / Double(totalZones) * 100
    }
}

// MARK: - AvalancheAnalyzerEngine

@MainActor
enum AvalancheAnalyzerEngine {

    static func analyze(slopeResult: TerrainSlopeResult,
                        snowPresent: Bool,
                        recentSnowfall: Bool,
                        windLoadedAspects: Set<String> = []) -> AvalancheAnalysis {

        var avalancheZones: [AvalancheZone] = []
        var proneCount = 0
        var totalTraps = 0

        // Identify prone and trap zones from slope result
        for (idx, zone) in slopeResult.zones.enumerated() {
            let risk = zoneRisk(zone, snowPresent: snowPresent,
                                recentSnowfall: recentSnowfall,
                                windLoadedAspects: windLoadedAspects)
            let traps = detectTraps(
                zone: zone,
                allZones: slopeResult.zones,
                idx: idx,
                rows: slopeResult.gridRows,
                cols: slopeResult.gridCols
            )
            if zone.slopeDeg >= 30 && zone.slopeDeg <= 45 { proneCount += 1 }
            if !traps.isEmpty { totalTraps += 1 }
            if risk != .low || !traps.isEmpty {
                avalancheZones.append(AvalancheZone(
                    row: zone.row, col: zone.col,
                    slopeDeg: zone.slopeDeg, aspectDeg: zone.aspectDeg,
                    risk: risk, traps: traps
                ))
            }
        }

        let overallRisk = computeOverallRisk(
            zones: slopeResult.zones,
            proneCount: proneCount,
            snowPresent: snowPresent,
            recentSnowfall: recentSnowfall
        )

        let corridors = safeCorridors(
            zones: slopeResult.zones,
            windLoadedAspects: windLoadedAspects
        )

        let factors = keyFactors(
            overallRisk: overallRisk,
            proneCount: proneCount,
            trapCount: totalTraps,
            snowPresent: snowPresent,
            recentSnowfall: recentSnowfall,
            meanSlope: slopeResult.meanSlope,
            windLoadedAspects: windLoadedAspects
        )

        return AvalancheAnalysis(
            timestamp: Date(),
            zones: avalancheZones,
            overallRisk: overallRisk,
            proneZoneCount: proneCount,
            trapCount: totalTraps,
            safeCorridors: corridors,
            keyFactors: factors,
            totalZones: slopeResult.zones.count
        )
    }

    // MARK: Zone Risk

    private static func zoneRisk(_ zone: SlopeZone,
                                  snowPresent: Bool,
                                  recentSnowfall: Bool,
                                  windLoadedAspects: Set<String>) -> AvalancheRisk {
        guard snowPresent else {
            return zone.slopeDeg >= 40 ? .moderate : .low
        }

        var score = 0

        // Slope angle
        if zone.slopeDeg >= 45       { score += 4 }
        else if zone.slopeDeg >= 38  { score += 3 }
        else if zone.slopeDeg >= 30  { score += 2 }
        else if zone.slopeDeg >= 20  { score += 1 }

        // Aspect — lee aspects (N, NE, E) accumulate wind slab
        if windLoadedAspects.contains(zone.aspectCardinal) { score += 2 }
        // Solar: south-facing aspects in spring = wet avalanche risk
        if ["S","SE","SW"].contains(zone.aspectCardinal)   { score += 1 }

        // Recent snowfall adds instability
        if recentSnowfall { score += 2 }

        switch score {
        case 0...1: return .low
        case 2...3: return .moderate
        case 4...5: return .considerable
        case 6...7: return .high
        default:    return .extreme
        }
    }

    // MARK: Terrain Traps

    private static func detectTraps(zone: SlopeZone,
                                    allZones: [SlopeZone],
                                    idx: Int,
                                    rows: Int,
                                    cols: Int) -> [TerrainTrapType] {
        var traps: [TerrainTrapType] = []

        // Gully: zones with aspect that converges (E and W neighbours both steep)
        let left = idx > 0 ? allZones[idx-1] : nil
        let right = idx < allZones.count-1 ? allZones[idx+1] : nil
        if let l = left, let r = right,
           l.slopeDeg > 25 && r.slopeDeg > 25 && zone.slopeDeg < l.slopeDeg && zone.slopeDeg < r.slopeDeg {
            traps.append(.gully)
        }

        // Cliff base: zone below very steep terrain (>50°)
        if let prev = idx >= cols ? allZones[idx - cols] : nil, prev.slopeDeg > 50 {
            traps.append(.cliffBase)
        }

        // Convex roll: slope increasing then decreasing
        if let prev = idx >= cols ? allZones[idx - cols] : nil,
           let curr_zone = Optional(zone),
           prev.slopeDeg < curr_zone.slopeDeg && curr_zone.slopeDeg > 30 {
            traps.append(.convexRoll)
        }

        // Narrow crossing: steep on both row-sides
        if idx >= cols && idx + cols < allZones.count {
            let above = allZones[idx - cols]
            let below = allZones[idx + cols]
            if above.slopeDeg > 30 && below.slopeDeg > 30 && zone.slopeDeg < 15 {
                traps.append(.narrowCross)
            }
        }

        return traps
    }

    // MARK: Overall Risk

    private static func computeOverallRisk(zones: [SlopeZone],
                                           proneCount: Int,
                                           snowPresent: Bool,
                                           recentSnowfall: Bool) -> AvalancheRisk {
        guard snowPresent else { return .low }
        let total = zones.count
        guard total > 0 else { return .low }

        let proneFraction = Double(proneCount) / Double(total)
        var score = proneFraction * 5   // 0-5 base
        if recentSnowfall { score += 1.5 }
        // Weather factor: rapid pressure drop = storm snow
        if case .rapidDrop = WeatherForecaster.shared.trend { score += 1.0 }

        switch score {
        case ..<1:   return .low
        case 1..<2.5: return .moderate
        case 2.5..<4: return .considerable
        case 4..<5.5: return .high
        default:      return .extreme
        }
    }

    // MARK: Safe Corridors

    private static func safeCorridors(zones: [SlopeZone],
                                       windLoadedAspects: Set<String>) -> [String] {
        var corridors: [String] = []

        // Count flat zones (<25°) by aspect
        var flatByAspect: [String: Int] = [:]
        for zone in zones where zone.slopeDeg < 25 {
            flatByAspect[zone.aspectCardinal, default: 0] += 1
        }

        // Prefer aspects not in wind-loaded set
        let safeCandidates = flatByAspect.sorted { $0.value > $1.value }
            .filter { !windLoadedAspects.contains($0.key) }

        if let best = safeCandidates.first {
            corridors.append("Travel on \(best.key)-facing terrain (slope < 25°, \(best.value) safe cells).")
        }
        corridors.append("Stay on ridgelines — avoid runout zones below 30° slopes.")
        corridors.append("Cross avalanche paths one at a time; choose narrow point high on slope.")
        if !windLoadedAspects.isEmpty {
            corridors.append("Avoid \(windLoadedAspects.joined(separator: ", "))-facing lee aspects — wind slab suspected.")
        }
        return corridors
    }

    // MARK: Key Factors

    private static func keyFactors(overallRisk: AvalancheRisk,
                                    proneCount: Int,
                                    trapCount: Int,
                                    snowPresent: Bool,
                                    recentSnowfall: Bool,
                                    meanSlope: Double,
                                    windLoadedAspects: Set<String>) -> [String] {
        var factors: [String] = []
        if !snowPresent { factors.append("No snow cover — dry avalanche risk only on extreme slopes.") }
        else {
            factors.append("Snow present — all slope ratings active.")
            if recentSnowfall { factors.append("Recent snowfall — instability elevated.") }
        }
        factors.append(String(format: "%.0f%% of terrain in critical 30–45° band.", Double(proneCount > 0 ? proneCount : 0) * 100 / Double(max(1, proneCount + 1))))
        if meanSlope >= 30 { factors.append(String(format: "Mean slope %.0f° — predominantly steep.", meanSlope)) }
        if trapCount > 0  { factors.append("\(trapCount) terrain trap\(trapCount == 1 ? "" : "s") identified (gullies/cliff bases).") }
        factors.append("Overall rating: \(overallRisk.rawValue) — AIARE scale equivalent.")
        return factors
    }
}

// MARK: - AvalancheAnalyzerManager

@MainActor
final class AvalancheAnalyzerManager: ObservableObject {
    static let shared = AvalancheAnalyzerManager()

    @Published var analysis: AvalancheAnalysis? = nil
    @Published var isAnalyzing = false
    @Published var snowPresent = true
    @Published var recentSnowfall = false
    @Published var windLoadedAspects: Set<String> = []

    private init() {
        // Pre-populate snow from TempLogger
        if let temp = TempLogger.shared.readings.last {
            snowPresent = temp.celsius < 2.0
        }
    }

    func analyze() {
        guard let slopeResult = TerrainSlopeAnalyzerViewModel().result else {
            // Build fresh slope analysis from breadcrumbs
            let vm = TerrainSlopeAnalyzerViewModel()
            Task {
                await vm.analyze(coordinate: LocationManager.shared.locationOrDefault)
                if let r = vm.result {
                    self.run(slopeResult: r)
                }
            }
            return
        }
        run(slopeResult: slopeResult)
    }

    private func run(slopeResult: TerrainSlopeResult) {
        isAnalyzing = true
        let snap_snow = snowPresent
        let snap_rain = recentSnowfall
        let snap_wind = windLoadedAspects
        Task.detached(priority: .userInitiated) {
            let result = await MainActor.run {
                AvalancheAnalyzerEngine.analyze(
                    slopeResult: slopeResult,
                    snowPresent: snap_snow,
                    recentSnowfall: snap_rain,
                    windLoadedAspects: snap_wind
                )
            }
            await MainActor.run { [weak self] in
                self?.analysis = result
                self?.isAnalyzing = false
            }
        }
    }
}

// MARK: - AvalancheAnalyzerView

struct AvalancheAnalyzerView: View {
    @ObservedObject private var mgr = AvalancheAnalyzerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Inputs row
                        inputsCard
                        if mgr.isAnalyzing {
                            loadingView
                        } else if let a = mgr.analysis {
                            overallRiskCard(a)
                            factorsCard(a)
                            corridorsCard(a)
                            if !a.zones.isEmpty { zonesCard(a) }
                        } else {
                            noAnalysisView
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Avalanche Analyzer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if mgr.isAnalyzing {
                        ProgressView().tint(ZDDesign.cyanAccent)
                    } else {
                        Button {
                            mgr.analyze()
                        } label: {
                            Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .onAppear { if mgr.analysis == nil { mgr.analyze() } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Inputs

    private var inputsCard: some View {
        VStack(spacing: 10) {
            Text("CONDITIONS").font(.caption.bold()).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 20) {
                Toggle(isOn: $mgr.snowPresent) {
                    Label("Snow cover", systemImage: "snowflake").font(.caption)
                }
                .tint(ZDDesign.cyanAccent)
                Toggle(isOn: $mgr.recentSnowfall) {
                    Label("Recent snowfall", systemImage: "cloud.snow").font(.caption)
                }
                .tint(ZDDesign.cyanAccent)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Loading / No Data

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.4)
            Text("Analyzing terrain…").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    private var noAnalysisView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.secondary)
            Text("Tap refresh to analyze").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(ZDDesign.darkCard).cornerRadius(12)
    }

    // MARK: Overall Risk

    private func overallRiskCard(_ a: AvalancheAnalysis) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AVALANCHE RISK").font(.caption.bold()).foregroundColor(.secondary)
                Text(a.overallRisk.rawValue)
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(a.overallRisk.color)
            }
            Spacer()
            VStack(spacing: 4) {
                // Risk ladder
                ForEach(AvalancheRisk.allCases.reversed(), id: \.rawValue) { r in
                    HStack(spacing: 6) {
                        Circle().fill(r.color)
                            .frame(width: r == a.overallRisk ? 14 : 8,
                                   height: r == a.overallRisk ? 14 : 8)
                        Text(r.rawValue)
                            .font(.system(size: r == a.overallRisk ? 11 : 9, weight: r == a.overallRisk ? .bold : .regular))
                            .foregroundColor(r == a.overallRisk ? r.color : .secondary)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Key Factors

    private func factorsCard(_ a: AvalancheAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEY FACTORS").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 16) {
                statCell(value: String(format: "%.0f%%", a.pronePercent), label: "Prone", color: ZDDesign.signalRed)
                statCell(value: "\(a.trapCount)", label: "Traps", color: .orange)
                statCell(value: "\(a.zones.count)", label: "Flagged", color: ZDDesign.safetyYellow)
            }
            Divider().background(ZDDesign.mediumGray.opacity(0.2))
            ForEach(a.keyFactors, id: \.self) { f in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").foregroundColor(.secondary)
                    Text(f).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Safe Corridors

    private func corridorsCard(_ a: AvalancheAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAFE TRAVEL CORRIDORS").font(.caption.bold()).foregroundColor(ZDDesign.successGreen)
            ForEach(a.safeCorridors.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i+1).").font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent).frame(width: 18)
                    Text(a.safeCorridors[i]).font(.caption).foregroundColor(ZDDesign.pureWhite)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Zones List

    private func zonesCard(_ a: AvalancheAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLAGGED ZONES (\(a.zones.count))").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(a.zones.sorted { $0.risk.numericValue > $1.risk.numericValue }.prefix(10)) { zone in
                HStack {
                    Circle().fill(zone.risk.color).frame(width: 8, height: 8)
                    Text(String(format: "%.0f°", zone.slopeDeg))
                        .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite).frame(width: 36)
                    Text(zone.aspectCardinal)
                        .font(.caption).foregroundColor(.secondary).frame(width: 28)
                    Text(zone.risk.rawValue)
                        .font(.caption.bold()).foregroundColor(zone.risk.color)
                    Spacer()
                    if !zone.traps.isEmpty {
                        ForEach(zone.traps, id: \.rawValue) { trap in
                            Image(systemName: trap.icon).font(.caption2).foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
