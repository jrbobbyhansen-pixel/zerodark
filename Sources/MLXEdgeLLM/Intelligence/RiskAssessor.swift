// RiskAssessor.swift — AI mission risk evaluation from real app state
// Pulls from WeatherForecaster, AltitudeTracker, MeshService, TempLogger, SafetyMonitor.
// Outputs 0-1 risk score per domain + ranked mitigations.

import Foundation
import SwiftUI

// MARK: - RiskDomain

struct RiskDomain: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let score: Double   // 0-1
    let factors: [String]
    let mitigations: [String]
    var color: Color {
        if score < 0.33 { return ZDDesign.successGreen }
        if score < 0.66 { return ZDDesign.safetyYellow }
        return ZDDesign.signalRed
    }
    var label: String {
        if score < 0.33 { return "LOW" }
        if score < 0.66 { return "MODERATE" }
        return "HIGH"
    }
}

// MARK: - RiskAssessment

struct RiskAssessment {
    let timestamp: Date
    let overallScore: Double        // 0-1, weighted avg
    let domains: [RiskDomain]
    let topMitigations: [String]    // ranked by domain score descending

    var overallLabel: String {
        if overallScore < 0.33 { return "LOW" }
        if overallScore < 0.66 { return "MODERATE" }
        return "HIGH"
    }
    var overallColor: Color {
        if overallScore < 0.33 { return ZDDesign.successGreen }
        if overallScore < 0.66 { return ZDDesign.safetyYellow }
        return ZDDesign.signalRed
    }
}

// MARK: - RiskAssessorEngine

@MainActor
enum RiskAssessorEngine {

    static func assess() -> RiskAssessment {
        let weather   = weatherDomain()
        let altitude  = altitudeDomain()
        let team      = teamDomain()
        let env       = environmentDomain()
        let comms     = commsDomain()
        let domains   = [weather, altitude, team, env, comms]

        // Weighted: team = 0.3, weather = 0.25, comms = 0.2, altitude = 0.15, env = 0.1
        let weights: [Double] = [0.25, 0.15, 0.30, 0.10, 0.20]
        let overall = zip(domains, weights).reduce(0) { $0 + $1.0.score * $1.1 }

        let ranked = domains.sorted { $0.score > $1.score }
        let mitigations = ranked.flatMap { $0.mitigations }.prefix(6)

        return RiskAssessment(
            timestamp: Date(),
            overallScore: min(1.0, overall),
            domains: domains,
            topMitigations: Array(mitigations)
        )
    }

    // MARK: Weather

    private static func weatherDomain() -> RiskDomain {
        let wf = WeatherForecaster.shared
        var score = 0.0
        var factors: [String] = []
        var mitigations: [String] = []

        if wf.pressureHistory.isEmpty {
            score += 0.2
            factors.append("No barometric data")
            mitigations.append("Log barometric readings to enable forecast.")
        } else {
            switch wf.trend {
            case .rapidDrop:
                score += 0.8
                factors.append("Rapid pressure drop — storm imminent")
                mitigations.append("Seek shelter. Postpone exposed movement.")
            case .stable:
                score += 0.1
                factors.append("Stable pressure")
            case .rapidRise:
                score += 0.05
                factors.append("Pressure rising — improving conditions")
            }
        }

        // Wind risk
        if let latest = WindEstimator.shared.history.last {
            let bft = latest.beaufort.rawValue
            let windScore = min(1.0, Double(bft) / 10.0)
            score = max(score, windScore * 0.6)
            if bft >= 6 {
                factors.append("Beaufort \(bft) — strong wind")
                mitigations.append("Reduce load. Avoid exposed ridgelines.")
            }
        }

        // Temperature risk
        if let tempReading = TempLogger.shared.readings.last {
            let risk = tempReading.risk
            if risk != .none {
                score = max(score, 0.5)
                factors.append("Cold injury risk: \(risk.rawValue)")
                mitigations.append("Layer up. Monitor extremities. Limit exposure time.")
            }
        }

        return RiskDomain(
            name: "Weather", icon: "cloud.bolt.fill",
            score: min(1, score), factors: factors, mitigations: mitigations
        )
    }

    // MARK: Altitude

    private static func altitudeDomain() -> RiskDomain {
        let tracker = AltitudeTracker.shared
        var score = 0.0
        var factors: [String] = []
        var mitigations: [String] = []

        switch tracker.currentBand {
        case .low:      score = 0.0
        case .moderate: score = 0.1
        case .high:     score = 0.3;  factors.append("High altitude — monitor for AMS")
        case .veryHigh: score = 0.55; factors.append("Very high altitude — AMS risk elevated")
        case .extreme:  score = 0.85; factors.append("Extreme altitude — HACE/HAPE risk")
        }

        let amsRisk = tracker.amsRisk
        if amsRisk != .low {
            score = max(score, amsRisk == .high || amsRisk == .severe ? 0.75 : 0.4)
            factors.append("AMS risk: \(amsRisk.rawValue)")
            if amsRisk == .severe {
                mitigations.append("Descend immediately. Do not ascend further.")
            } else {
                mitigations.append("Rest and acclimatize before ascending.")
            }
        }

        if !tracker.ascentRateWarnings.isEmpty {
            score = max(score, 0.6)
            factors.append("Ascent rate too fast (>500 m/hr)")
            mitigations.append("Slow ascent. Rest 1 hr before continuing up.")
        }

        return RiskDomain(
            name: "Altitude", icon: "mountain.2.fill",
            score: min(1, score), factors: factors, mitigations: mitigations
        )
    }

    // MARK: Team

    private static func teamDomain() -> RiskDomain {
        var score = 0.0
        var factors: [String] = []
        var mitigations: [String] = []

        let peers = MeshService.shared.peers
        let onlinePeers = peers.filter { $0.status != .offline }
        if peers.isEmpty {
            score += 0.7
            factors.append("No mesh network — isolated")
            mitigations.append("Establish comms before movement. Use check-in protocol.")
        } else if onlinePeers.count < peers.count {
            let missing = peers.count - onlinePeers.count
            score += Double(missing) / Double(peers.count) * 0.5
            factors.append("\(missing) team member(s) offline")
            mitigations.append("Verify offline members before departure.")
        } else {
            factors.append("\(onlinePeers.count) team members online")
        }

        // Hydration risk
        let hydration = HydrationCalculator.shared
        let target = max(1, hydration.dailyNeedML)
        let pct = hydration.todayIntakeML / target
        if pct < 0.5 {
            score += 0.4
            factors.append("Hydration below 50% of daily target")
            mitigations.append("Enforce water intake before movement.")
        } else if pct < 0.75 {
            score += 0.2
            factors.append("Hydration below 75% target")
        }

        return RiskDomain(
            name: "Team", icon: "person.3.fill",
            score: min(1, score), factors: factors, mitigations: mitigations
        )
    }

    // MARK: Environment

    private static func environmentDomain() -> RiskDomain {
        var score = 0.0
        var factors: [String] = []
        var mitigations: [String] = []

        // Light conditions
        switch LightEstimator.shared.currentLevel {
        case .night, .astronomicalTwilight:
            score += 0.5
            factors.append("Low ambient light — NVG or torch required")
            mitigations.append("Confirm NVG availability. Slow movement speed.")
        case .nauticalTwilight:
            score += 0.3
            factors.append("Reduced light conditions")
        default: break
        }

        // Moon phase
        let moonIllum = MoonPhaseService.shared.illumination
        if moonIllum > 0.75 {
            score += 0.15
            factors.append("High lunar illumination — reduced concealment")
            mitigations.append("Use terrain masking. Avoid movement on open ground.")
        } else if moonIllum < 0.1 {
            score += 0.2
            factors.append("Near-dark lunar phase — navigation risk")
            mitigations.append("Use GPS or pre-plotted terrain features.")
        }

        return RiskDomain(
            name: "Environment", icon: "eye.fill",
            score: min(1, score), factors: factors, mitigations: mitigations
        )
    }

    // MARK: Comms

    private static func commsDomain() -> RiskDomain {
        var score = 0.0
        var factors: [String] = []
        var mitigations: [String] = []

        let peers = MeshService.shared.peers
        if peers.isEmpty {
            score = 0.8
            factors.append("No mesh nodes reachable")
            mitigations.append("Establish radio/satellite backup. Brief team on PACE plan.")
        } else {
            let anomalies = MeshAnomalyDetector.shared.alerts
            if !anomalies.isEmpty {
                score = 0.5
                factors.append("\(anomalies.count) mesh anomaly/anomalies detected")
                mitigations.append("Investigate mesh issues before critical movement.")
            } else {
                factors.append("Mesh network healthy (\(peers.count) nodes)")
            }
        }

        return RiskDomain(
            name: "Comms", icon: "antenna.radiowaves.left.and.right",
            score: min(1, score), factors: factors, mitigations: mitigations
        )
    }
}

// MARK: - RiskAssessor (manager)

@MainActor
final class RiskAssessor: ObservableObject {
    static let shared = RiskAssessor()

    @Published var assessment: RiskAssessment? = nil
    @Published var isAssessing = false

    private init() {}

    func runAssessment() {
        isAssessing = true
        // RiskAssessorEngine is @MainActor, so assess() runs synchronously
        let result = RiskAssessorEngine.assess()
        assessment = result
        isAssessing = false
    }
}

// MARK: - RiskAssessorView

struct RiskAssessorView: View {
    @ObservedObject private var mgr = RiskAssessor.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let a = mgr.assessment {
                            overallCard(a)
                            ForEach(a.domains) { d in domainCard(d) }
                            if !a.topMitigations.isEmpty { mitigationsCard(a.topMitigations) }
                        } else {
                            noAssessmentCard
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Risk Assessor")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if mgr.isAssessing {
                        ProgressView().tint(ZDDesign.cyanAccent)
                    } else {
                        Button {
                            mgr.runAssessment()
                        } label: {
                            Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .onAppear { if mgr.assessment == nil { mgr.runAssessment() } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Overall

    private func overallCard(_ a: RiskAssessment) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MISSION RISK").font(.caption.bold()).foregroundColor(.secondary)
                    Text(a.overallLabel)
                        .font(.system(size: 40, weight: .black))
                        .foregroundColor(a.overallColor)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(a.overallColor.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: CGFloat(a.overallScore))
                        .stroke(a.overallColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.0f%%", a.overallScore * 100))
                        .font(.headline.bold()).foregroundColor(a.overallColor)
                }
            }
            Text(a.timestamp, style: .time)
                .font(.caption2).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Domain Card

    private func domainCard(_ d: RiskDomain) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: d.icon).foregroundColor(d.color)
                Text(d.name.uppercased()).font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Text(d.label).font(.caption.bold()).foregroundColor(d.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(d.color.opacity(0.1)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(d.color)
                        .frame(width: geo.size.width * CGFloat(d.score), height: 6)
                }
            }
            .frame(height: 6)
            ForEach(d.factors, id: \.self) { f in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").foregroundColor(d.color)
                    Text(f).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Mitigations

    private func mitigationsCard(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP MITIGATIONS").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(items.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent).frame(width: 16)
                    Text(items[i]).font(.caption).foregroundColor(ZDDesign.pureWhite)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: No Data

    private var noAssessmentCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundColor(.secondary)
            Text("Tap refresh to run assessment").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(ZDDesign.darkCard).cornerRadius(12)
    }
}
