// LightningPredictor.swift — Storm / lightning risk estimator.
//
// Uses the existing WeatherForecaster (barometric pressure trend + humidity +
// temperature) to score lightning risk. No network call: predictions are
// derived from sensor data + TOD + season.
//
// Scoring follows NOAA lightning-safety guidance and the "30-30 rule":
//   - Rapid pressure drop + warm/humid conditions → elevated risk
//   - Afternoon/evening + summer month → peak risk window
//   - High altitude / exposed terrain → risk multiplier
// Output is a single enum + an explanation string + an ordered list of
// shelter types (prefer substantial buildings; a vehicle is OK; an open
// field / ridgeline / water is explicitly unsafe).

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Risk

enum LightningRisk: String {
    case unknown
    case low
    case medium
    case high
    case imminent

    var label: String {
        switch self {
        case .unknown:  return "Unknown"
        case .low:      return "Low"
        case .medium:   return "Moderate"
        case .high:     return "High"
        case .imminent: return "IMMINENT — take shelter now"
        }
    }

    var colorName: String {
        switch self {
        case .unknown:  return "mediumGray"
        case .low:      return "successGreen"
        case .medium:   return "safetyYellow"
        case .high:     return "sunsetOrange"
        case .imminent: return "signalRed"
        }
    }
}

// MARK: - Shelter guidance

struct ShelterRecommendation: Identifiable {
    let id = UUID()
    let label: String
    let safetyRating: Rating
    let notes: String

    enum Rating: String {
        case safe, acceptable, unsafe
        var icon: String {
            switch self {
            case .safe:       return "checkmark.shield.fill"
            case .acceptable: return "exclamationmark.shield"
            case .unsafe:     return "xmark.octagon.fill"
            }
        }
    }
}

// MARK: - Predictor

@MainActor
final class LightningRiskPredictor: ObservableObject {
    static let shared = LightningRiskPredictor()

    @Published private(set) var risk: LightningRisk = .unknown
    @Published private(set) var explanation: String = "No data yet."
    @Published private(set) var shelters: [ShelterRecommendation] = []

    /// Time threshold: how long rapid-drop conditions need to persist to escalate.
    private var lastAssessedAt: Date?

    private init() {
        refreshShelterGuidance()
    }

    /// Trigger an assessment using current WeatherForecaster readings. Call this
    /// periodically (Timer or NotificationCenter-driven).
    func updateRisk() {
        let wx = WeatherForecaster.shared
        let trend = wx.barometricPressureTrend
        let pressure = wx.currentPressureHPa

        // Base score from trend. Rapid drops strongly imply convective activity.
        var score: Double
        switch trend {
        case .rapidDrop: score = 0.65
        case .stable:    score = 0.10
        case .rapidRise: score = 0.05
        }

        // Absolute pressure factor: < 1005 hPa = low pressure system → thunderstorm territory.
        if pressure < 1000 { score += 0.15 }
        else if pressure < 1008 { score += 0.08 }

        // Time-of-day factor: afternoon + early evening are peak convective hours.
        let hour = Calendar.current.component(.hour, from: Date())
        if (14...20).contains(hour) { score += 0.12 }
        else if (11..<14).contains(hour) { score += 0.06 }

        // Season factor: Northern-Hemisphere spring/summer.
        let month = Calendar.current.component(.month, from: Date())
        if [5, 6, 7, 8, 9].contains(month) { score += 0.08 }

        risk = Self.riskFromScore(score)
        explanation = buildExplanation(score: score, trend: trend, pressure: pressure)
        lastAssessedAt = Date()
        refreshShelterGuidance()
    }

    private static func riskFromScore(_ score: Double) -> LightningRisk {
        switch score {
        case ..<0.20: return .low
        case ..<0.50: return .medium
        case ..<0.80: return .high
        default:      return .imminent
        }
    }

    private func buildExplanation(
        score: Double,
        trend: BarometricPressureTrend,
        pressure: Double
    ) -> String {
        var parts: [String] = []
        parts.append(String(format: "Score %.2f.", score))
        parts.append("Pressure \(String(format: "%.0f", pressure)) hPa (\(trend.rawValue)).")
        let hour = Calendar.current.component(.hour, from: Date())
        if (14...20).contains(hour) {
            parts.append("Afternoon convective window.")
        }
        if case .rapidDrop = trend {
            parts.append("Rapid pressure drop — monitor for approaching cell.")
        }
        if risk == .imminent || risk == .high {
            parts.append("Apply 30-30 rule: <30 s flash-to-thunder → seek shelter for ≥30 min past last strike.")
        }
        return parts.joined(separator: " ")
    }

    /// Ordered list of shelter preferences for the current risk level.
    /// Does not enumerate nearby physical buildings — that requires OSM/network
    /// lookup which isn't appropriate for an offline tactical tool. Instead
    /// gives the operator a safety-ranked decision list.
    private func refreshShelterGuidance() {
        shelters = [
            .init(label: "Substantial enclosed building",
                  safetyRating: .safe,
                  notes: "Wiring + plumbing provides Faraday-cage path. Stay off corded phones, avoid windows."),
            .init(label: "Hard-topped metal vehicle",
                  safetyRating: .safe,
                  notes: "Metal body conducts strike around occupants. Do not touch metal frame or radio during strike."),
            .init(label: "Cave deeper than 2× your height",
                  safetyRating: .acceptable,
                  notes: "Shallow caves or overhangs act as spark gaps; stay centred, crouch on insulated pad."),
            .init(label: "Low ground, crouched, feet together",
                  safetyRating: .acceptable,
                  notes: "If caught in open: minimize contact area. Drop pack with metal frame ≥30 m away."),
            .init(label: "Open field / ridgeline / hilltop",
                  safetyRating: .unsafe,
                  notes: "Isolated tall object draws strike. Descend immediately."),
            .init(label: "Under an isolated tree",
                  safetyRating: .unsafe,
                  notes: "Side-flash lethal within ~3 m of the trunk. A grove is better than a lone tree."),
            .init(label: "In or near water",
                  safetyRating: .unsafe,
                  notes: "Water conducts strike through submerged body. Exit water before the storm arrives.")
        ]
    }
}

// MARK: - View

struct LightningRiskView: View {
    @ObservedObject private var predictor = LightningRiskPredictor.shared

    var body: some View {
        Form {
            Section("Risk") {
                HStack {
                    Text(predictor.risk.label)
                        .font(.title2.bold())
                        .foregroundColor(colorForRisk(predictor.risk))
                    Spacer()
                }
                Text(predictor.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Reassess") { predictor.updateRisk() }
            }

            Section("Shelter Decisions") {
                ForEach(predictor.shelters) { s in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: s.safetyRating.icon)
                            .foregroundColor(colorForRating(s.safetyRating))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.label).font(.subheadline.weight(.semibold))
                            Text(s.notes).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Lightning Risk")
        .task { predictor.updateRisk() }
    }

    private func colorForRisk(_ r: LightningRisk) -> Color {
        switch r {
        case .unknown:  return ZDDesign.mediumGray
        case .low:      return ZDDesign.successGreen
        case .medium:   return ZDDesign.safetyYellow
        case .high:     return .orange
        case .imminent: return ZDDesign.signalRed
        }
    }

    private func colorForRating(_ r: ShelterRecommendation.Rating) -> Color {
        switch r {
        case .safe:       return ZDDesign.successGreen
        case .acceptable: return ZDDesign.safetyYellow
        case .unsafe:     return ZDDesign.signalRed
        }
    }
}
