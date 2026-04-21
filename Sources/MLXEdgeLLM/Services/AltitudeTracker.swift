// AltitudeTracker.swift — Altitude acclimatization tracking, AMS risk, ascent rate warnings
// Uses GPS altitude from LocationManager. Wilderness Medicine guidelines.

import Foundation
import CoreLocation
import SwiftUI

// MARK: - AltitudeBand

enum AltitudeBand: String, CaseIterable, Codable, Comparable {
    case low        = "Low (<1500m)"
    case moderate   = "Moderate (1500–2500m)"
    case high       = "High (2500–3500m)"
    case veryHigh   = "Very High (3500–5500m)"
    case extreme    = "Extreme (>5500m)"

    static func < (lhs: AltitudeBand, rhs: AltitudeBand) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    static func forAltitude(_ m: Double) -> AltitudeBand {
        if m < 1500 { return .low }
        if m < 2500 { return .moderate }
        if m < 3500 { return .high }
        if m < 5500 { return .veryHigh }
        return .extreme
    }

    var color: Color {
        switch self {
        case .low:      return ZDDesign.successGreen
        case .moderate: return ZDDesign.cyanAccent
        case .high:     return ZDDesign.safetyYellow
        case .veryHigh: return .orange
        case .extreme:  return ZDDesign.signalRed
        }
    }

    var acclimatizationNote: String {
        switch self {
        case .low:      return "No acclimatization needed"
        case .moderate: return "Mild symptoms possible; 1-day rest recommended"
        case .high:     return "Ascend max 500m/day sleeping alt; rest day every 3 days"
        case .veryHigh: return "Ascend max 300m/day; mandatory rest days"
        case .extreme:  return "Supplemental O₂ recommended; limit exposure"
        }
    }

    var o2Saturation: String {
        switch self {
        case .low:      return "~98%"
        case .moderate: return "~95%"
        case .high:     return "~90%"
        case .veryHigh: return "~80–85%"
        case .extreme:  return "~70–75%"
        }
    }
}

// MARK: - AMSRisk

enum AMSRisk: String {
    case low      = "Low"
    case moderate = "Moderate"
    case high     = "High"
    case severe   = "Severe — Descend Immediately"

    var color: Color {
        switch self {
        case .low:     return ZDDesign.successGreen
        case .moderate: return ZDDesign.safetyYellow
        case .high:    return .orange
        case .severe:  return ZDDesign.signalRed
        }
    }
}

// MARK: - AltitudeSample

struct AltitudeSample: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var altitudeM: Double
    var band: AltitudeBand
}

// MARK: - AltitudeTracker

@MainActor
final class AltitudeTracker: ObservableObject {
    static let shared = AltitudeTracker()

    @Published private(set) var currentAltitudeM: Double = 0
    @Published private(set) var history: [AltitudeSample] = []
    @Published private(set) var timeAtBand: [AltitudeBand: TimeInterval] = [:]   // seconds
    @Published private(set) var ascentRateWarnings: [String] = []

    // Max recommended ascent rate above 2500m: 300m sleeping alt gain/day
    private let dangerousAscentRateMPerHour: Double = 500   // 500m/hour instantaneous = emergency
    private let saveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("altitude_tracker.json")

    private var lastSample: AltitudeSample?
    private var locationObserver: NSObjectProtocol?

    private init() {
        load()
        locationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.locationUpdate"),
            object: nil, queue: .main
        ) { [weak self] note in
            guard let alt = note.userInfo?["altitude"] as? Double else { return }
            Task { @MainActor [weak self] in self?.update(altitude: alt) }
        }
    }

    func update(altitude: Double) {
        currentAltitudeM = altitude
        let band = AltitudeBand.forAltitude(altitude)
        let sample = AltitudeSample(altitudeM: altitude, band: band)

        // Track time at band
        if let prev = lastSample {
            let elapsed = sample.timestamp.timeIntervalSince(prev.timestamp)
            timeAtBand[prev.band, default: 0] += elapsed

            // Ascent rate check
            let altDelta = altitude - prev.altitudeM
            let hoursFraction = elapsed / 3600.0
            if hoursFraction > 0 {
                let ratePerHour = altDelta / hoursFraction
                if ratePerHour > dangerousAscentRateMPerHour {
                    let msg = String(format: "⚠ Rapid ascent: %.0f m/hr at %.0fm", ratePerHour, altitude)
                    ascentRateWarnings.insert(msg, at: 0)
                    if ascentRateWarnings.count > 10 { ascentRateWarnings = Array(ascentRateWarnings.prefix(10)) }
                }
            }
        }

        history.insert(sample, at: 0)
        if history.count > 500 { history = Array(history.prefix(500)) }
        lastSample = sample
        save()
    }

    // MARK: - AMS Risk Assessment

    var amsRisk: AMSRisk {
        let band = AltitudeBand.forAltitude(currentAltitudeM)
        let hoursAtHighAlt = (timeAtBand[.high] ?? 0) + (timeAtBand[.veryHigh] ?? 0) + (timeAtBand[.extreme] ?? 0)
        let hoursHigh = hoursAtHighAlt / 3600

        // Acclimatization improves over time; rapid ascent worsens risk
        let wasLow = (timeAtBand[.low] ?? 0) + (timeAtBand[.moderate] ?? 0) > 172800  // 48h acclimatization

        switch band {
        case .low, .moderate:
            return .low
        case .high:
            return wasLow && hoursHigh < 48 ? .moderate : .low
        case .veryHigh:
            if ascentRateWarnings.count >= 2 { return .severe }
            return wasLow ? .moderate : .high
        case .extreme:
            return ascentRateWarnings.isEmpty ? .high : .severe
        }
    }

    // MARK: - Acclimatization Schedule

    var acclimatizationRecommendation: [String] {
        let band = AltitudeBand.forAltitude(currentAltitudeM)
        var recs: [String] = [band.acclimatizationNote]

        let hoursHigh = ((timeAtBand[.high] ?? 0) + (timeAtBand[.veryHigh] ?? 0)) / 3600
        if hoursHigh < 24 && band >= .high {
            recs.append("Rest at current altitude for \(max(0, Int(24 - hoursHigh))) more hours")
        }
        if band >= .veryHigh {
            recs.append("Climb high, sleep low — return 300–600m lower to sleep")
            recs.append("Hydrate ≥4L/day; avoid alcohol and sedatives")
        }
        if !ascentRateWarnings.isEmpty {
            recs.append("Recent rapid ascent detected — monitor closely for AMS symptoms")
        }
        return recs
    }

    // MARK: - Helpers

    var currentBand: AltitudeBand { AltitudeBand.forAltitude(currentAltitudeM) }

    var totalAscent: Double {
        guard history.count > 1 else { return 0 }
        var asc = 0.0
        for i in 1..<history.count {
            let delta = history[i-1].altitudeM - history[i].altitudeM
            if delta > 0 { asc += delta }
        }
        return asc
    }

    // MARK: - Persistence

    struct SavedState: Codable {
        var timeAtBand: [String: TimeInterval]
        var history: [AltitudeSample]
    }

    private func save() {
        let state = SavedState(
            timeAtBand: Dictionary(uniqueKeysWithValues: timeAtBand.map { ($0.key.rawValue, $0.value) }),
            history: Array(history.prefix(200))
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        history = state.history
        timeAtBand = Dictionary(uniqueKeysWithValues: state.timeAtBand.compactMap { k, v in
            AltitudeBand(rawValue: k).map { ($0, v) }
        })
        lastSample = history.first
    }
}

// MARK: - AltitudeTrackerView

struct AltitudeTrackerView: View {
    @ObservedObject private var tracker = AltitudeTracker.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        currentCard
                        riskCard
                        recommendationsCard
                        bandTimeCard
                        if !tracker.ascentRateWarnings.isEmpty { warningsCard }
                        historyCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Altitude Tracker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var currentCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT ALTITUDE").font(.caption.bold()).foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", tracker.currentAltitudeM))
                            .font(.system(size: 52, weight: .bold)).foregroundColor(ZDDesign.pureWhite)
                        Text("m").font(.title3).foregroundColor(.secondary)
                    }
                    Text(String(format: "%.0f ft", tracker.currentAltitudeM * 3.28084))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(tracker.currentBand.rawValue)
                        .font(.caption.bold()).foregroundColor(tracker.currentBand.color)
                        .multilineTextAlignment(.trailing)
                    Text("O₂ sat \(tracker.currentBand.o2Saturation)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            if tracker.totalAscent > 0 {
                HStack {
                    Image(systemName: "arrow.up.right").foregroundColor(.orange).font(.caption)
                    Text(String(format: "Total ascent: %.0fm", tracker.totalAscent))
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var riskCard: some View {
        HStack(spacing: 12) {
            Image(systemName: tracker.amsRisk == .low ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title2).foregroundColor(tracker.amsRisk.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("AMS RISK").font(.caption.bold()).foregroundColor(.secondary)
                Text(tracker.amsRisk.rawValue).font(.subheadline.bold())
                    .foregroundColor(tracker.amsRisk.color)
            }
            Spacer()
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var recommendationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACCLIMATIZATION PLAN").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(tracker.acclimatizationRecommendation, id: \.self) { rec in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(ZDDesign.cyanAccent).font(.caption).padding(.top, 2)
                    Text(rec).font(.caption).foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var bandTimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIME AT ALTITUDE BANDS").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(AltitudeBand.allCases, id: \.self) { band in
                let hours = (tracker.timeAtBand[band] ?? 0) / 3600
                HStack {
                    Circle().fill(band.color).frame(width: 8, height: 8)
                    Text(band.rawValue).font(.caption).foregroundColor(ZDDesign.mediumGray)
                    Spacer()
                    Text(hours < 1 ? String(format: "%.0f min", hours * 60) : String(format: "%.1f hr", hours))
                        .font(.caption.monospaced()).foregroundColor(ZDDesign.pureWhite)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASCENT RATE WARNINGS").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(tracker.ascentRateWarnings.prefix(5), id: \.self) { w in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(ZDDesign.signalRed).font(.caption)
                    Text(w).font(.caption).foregroundColor(ZDDesign.safetyYellow)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALTITUDE HISTORY").font(.caption.bold()).foregroundColor(.secondary)
            let samples = Array(tracker.history.prefix(8).reversed())
            if samples.isEmpty {
                Text("No altitude data yet").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(samples) { s in
                    HStack {
                        Circle().fill(s.band.color).frame(width: 8, height: 8)
                        Text(String(format: "%.0f m", s.altitudeM))
                            .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                        Spacer()
                        Text(s.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2.monospaced()).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}
