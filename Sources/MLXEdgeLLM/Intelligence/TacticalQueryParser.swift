// TacticalQueryParser.swift — Parse natural-language queries into structured ZeroDark action intents.
// Rule-based keyword/pattern matching. No inference required. Returns intent + matched tool.
// Ambiguous queries generate clarifying question list.

import Foundation
import SwiftUI

// MARK: - TacticalIntent

enum TacticalTool: String, CaseIterable {
    case distanceBearing    = "Distance & Bearing"
    case areaCalculator     = "Area Calculator"
    case elevationProfile   = "Elevation Profile"
    case sitrep             = "SITREP Generator"
    case riskAssessor       = "Risk Assessor"
    case weatherForecaster  = "Weather Forecaster"
    case moonPhase          = "Moon Phase"
    case sunCalculator      = "Sun Calculator"
    case lightEstimator     = "Light Estimator"
    case windEstimator      = "Wind Estimator"
    case tempLogger         = "Temperature Log"
    case altitudeTracker    = "Altitude Tracker"
    case hydration          = "Hydration"
    case opOrder            = "Op Order Builder"
    case riskMatrix         = "Risk Matrix"
    case missionTimeline    = "Mission Timeline"
    case commsLog           = "Comms Log"
    case decisionLog        = "Decision Log"
    case lidarScan          = "LiDAR Scan"
    case terrainComparison  = "Terrain Comparison"
    case meshExport         = "Mesh Export"
    case navigation         = "Navigation"
    case unknown            = "Unknown"

    var icon: String {
        switch self {
        case .distanceBearing:   return "ruler.fill"
        case .areaCalculator:    return "pentagon.fill"
        case .elevationProfile:  return "mountain.2.fill"
        case .sitrep:            return "doc.text.fill"
        case .riskAssessor:      return "exclamationmark.triangle.fill"
        case .weatherForecaster: return "barometer"
        case .moonPhase:         return "moonphase.full.moon"
        case .sunCalculator:     return "sun.max.fill"
        case .lightEstimator:    return "eye.fill"
        case .windEstimator:     return "wind"
        case .tempLogger:        return "thermometer.snowflake"
        case .altitudeTracker:   return "mountain.2.fill"
        case .hydration:         return "drop.fill"
        case .opOrder:           return "doc.richtext.fill"
        case .riskMatrix:        return "exclamationmark.triangle.fill"
        case .missionTimeline:   return "timeline.selection"
        case .commsLog:          return "antenna.radiowaves.left.and.right"
        case .decisionLog:       return "brain"
        case .lidarScan:         return "viewfinder.circle.fill"
        case .terrainComparison: return "arrow.left.arrow.right.circle"
        case .meshExport:        return "square.and.arrow.up"
        case .navigation:        return "location.fill"
        case .unknown:           return "questionmark.circle"
        }
    }
}

struct ParsedIntent: Identifiable {
    let id = UUID()
    let tool: TacticalTool
    let confidence: Double  // 0-1
    let extractedParams: [String: String]   // key-value pairs extracted from query
    let clarifyingQuestions: [String]       // empty if confidence >= 0.7
    let rawQuery: String
    let explanation: String                 // how the intent was determined
}

// MARK: - TacticalQueryParser

enum TacticalQueryParser {

    // MARK: - Pattern Tables

    private static let patterns: [(keywords: [String], tool: TacticalTool, paramKeys: [String])] = [
        // Distance / bearing
        (["distance", "bearing", "how far", "range", "azimuth", "direction to", "waypoint"], .distanceBearing, ["from", "to", "target"]),
        // Area
        (["area", "polygon", "hectares", "acres", "square", "perimeter", "sector size", "lz size"], .areaCalculator, ["region"]),
        // Elevation
        (["elevation", "altitude profile", "gain", "loss", "saddle", "high point", "climb", "descent profile"], .elevationProfile, []),
        // SITREP
        (["sitrep", "situation report", "status report", "current status", "team status update"], .sitrep, []),
        // Risk
        (["risk", "danger", "threat level", "assess risk", "mission risk", "hazard score"], .riskAssessor, ["mission"]),
        // Weather
        (["weather", "barometer", "pressure", "storm", "forecast", "rain", "precipitation"], .weatherForecaster, []),
        // Moon
        (["moon", "lunar", "moonrise", "moonset", "illumination", "night ops light"], .moonPhase, []),
        // Sun
        (["sunrise", "sunset", "golden hour", "nautical twilight", "civil twilight", "solar", "dawn", "dusk"], .sunCalculator, ["date"]),
        // Light
        (["lux", "ambient light", "nvg", "night vision", "light level", "darkness"], .lightEstimator, []),
        // Wind
        (["wind", "beaufort", "gusts", "channeling", "orographic"], .windEstimator, []),
        // Temp
        (["temperature", "wind chill", "cold injury", "overnight low", "freeze risk", "hypothermia"], .tempLogger, []),
        // Altitude
        (["ams", "altitude sickness", "acclimatize", "ascent rate", "high altitude"], .altitudeTracker, []),
        // Hydration
        (["water", "hydration", "intake", "dehydration", "liters per day"], .hydration, []),
        // OPORD
        (["opord", "op order", "five paragraph", "situation annex", "mission statement"], .opOrder, []),
        // Risk Matrix
        (["risk matrix", "probability", "severity", "5x5", "risk assessment form"], .riskMatrix, []),
        // Timeline
        (["timeline", "phase", "nlt", "latest time", "schedule", "h-hour"], .missionTimeline, []),
        // Comms
        (["comms log", "radio log", "message log", "transmission history"], .commsLog, []),
        // Decision log
        (["decision log", "ai decisions", "audit trail", "ai recommendations"], .decisionLog, []),
        // LiDAR
        (["scan", "lidar", "point cloud", "3d scan", "room scan", "terrain scan"], .lidarScan, []),
        // Compare
        (["compare scan", "change detection", "before after", "terrain change", "difference"], .terrainComparison, []),
        // Export
        (["export mesh", "export ply", "export obj", "export point cloud", "download scan"], .meshExport, []),
        // Navigation
        (["navigate", "route", "path", "get me to", "directions", "waypoint route"], .navigation, ["destination"]),
    ]

    // MARK: - Parse

    static func parse(_ query: String) -> ParsedIntent {
        let q = query.lowercased()
        var scores: [(TacticalTool, Double, [String: String])] = []

        for entry in patterns {
            var matchCount = 0
            var params = [String: String]()
            for kw in entry.keywords {
                if q.contains(kw) { matchCount += 1 }
            }
            if matchCount > 0 {
                let conf = min(1.0, Double(matchCount) / max(1.0, Double(entry.keywords.count) * 0.3))
                // Extract simple param values (word after param key)
                for paramKey in entry.paramKeys {
                    if let range = q.range(of: paramKey + " ") {
                        let after = String(q[range.upperBound...])
                        let word = after.components(separatedBy: .whitespaces).first ?? ""
                        if !word.isEmpty { params[paramKey] = word }
                    }
                }
                scores.append((entry.tool, conf, params))
            }
        }

        scores.sort { $0.1 > $1.1 }

        guard let top = scores.first else {
            return ParsedIntent(
                tool: .unknown,
                confidence: 0,
                extractedParams: [:],
                clarifyingQuestions: ["What would you like to do?",
                                      "Which tool are you looking for?"],
                rawQuery: query,
                explanation: "No matching tool found for: \"\(query)\""
            )
        }

        var clarifying: [String] = []
        if top.1 < 0.7 {
            clarifying.append("Did you mean \(top.0.rawValue)?")
            if scores.count > 1 {
                clarifying.append("Or did you mean \(scores[1].0.rawValue)?")
            }
        }

        return ParsedIntent(
            tool: top.0,
            confidence: top.1,
            extractedParams: top.2,
            clarifyingQuestions: clarifying,
            rawQuery: query,
            explanation: "Matched \(top.0.rawValue) with \(String(format: "%.0f", top.1 * 100))% confidence"
        )
    }
}

// MARK: - TacticalQueryParserManager

@MainActor
final class TacticalQueryParserManager: ObservableObject {
    static let shared = TacticalQueryParserManager()

    @Published var history: [ParsedIntent] = []
    @Published var currentResult: ParsedIntent? = nil

    private init() {}

    func parse(_ query: String) {
        let result = TacticalQueryParser.parse(query)
        currentResult = result
        history.insert(result, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
    }
}

// MARK: - TacticalQueryParserView

struct TacticalQueryParserView: View {
    @ObservedObject private var mgr = TacticalQueryParserManager.shared
    @State private var queryText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    Divider().background(ZDDesign.mediumGray.opacity(0.3))
                    if let result = mgr.currentResult {
                        resultView(result)
                    } else if !mgr.history.isEmpty {
                        historyList
                    } else {
                        emptyState
                    }
                }
            }
            .navigationTitle("Query Parser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                if !mgr.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { mgr.history.removeAll(); mgr.currentResult = nil }
                            .foregroundColor(ZDDesign.signalRed)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(ZDDesign.mediumGray)
            TextField("Ask a tactical question…", text: $queryText)
                .foregroundColor(ZDDesign.pureWhite)
                .submitLabel(.search)
                .onSubmit { if !queryText.isEmpty { mgr.parse(queryText); queryText = "" } }
            if !queryText.isEmpty {
                Button { queryText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ZDDesign.darkCard)
    }

    // MARK: Result View

    @ViewBuilder
    private func resultView(_ r: ParsedIntent) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Intent card
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: r.tool.icon)
                            .font(.title)
                            .foregroundColor(r.confidence >= 0.7 ? ZDDesign.cyanAccent : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.tool.rawValue)
                                .font(.headline.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text(r.explanation)
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        confidenceBadge(r.confidence)
                    }

                    if !r.extractedParams.isEmpty {
                        Divider().background(ZDDesign.mediumGray.opacity(0.2))
                        ForEach(r.extractedParams.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            HStack {
                                Text(k.capitalized).font(.caption.bold()).foregroundColor(.secondary)
                                Spacer()
                                Text(v).font(.caption.monospaced()).foregroundColor(ZDDesign.cyanAccent)
                            }
                        }
                    }

                    if !r.clarifyingQuestions.isEmpty {
                        Divider().background(ZDDesign.mediumGray.opacity(0.2))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CLARIFICATION NEEDED").font(.caption.bold()).foregroundColor(.orange)
                            ForEach(r.clarifyingQuestions, id: \.self) { q in
                                Label(q, systemImage: "questionmark.circle").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(ZDDesign.darkCard)
                .cornerRadius(12)

                // Query
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUERY").font(.caption.bold()).foregroundColor(.secondary)
                    Text("\"\(r.rawQuery)\"").font(.subheadline.italic()).foregroundColor(ZDDesign.pureWhite)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(ZDDesign.darkCard)
                .cornerRadius(12)

                // History preview
                if mgr.history.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RECENT QUERIES").font(.caption.bold()).foregroundColor(.secondary)
                        ForEach(mgr.history.dropFirst().prefix(5)) { h in
                            Button { mgr.currentResult = h } label: {
                                HStack {
                                    Image(systemName: h.tool.icon).foregroundColor(.secondary)
                                    Text(h.rawQuery).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                    Spacer()
                                    confidenceBadge(h.confidence).scaleEffect(0.8)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }

    // MARK: History List

    private var historyList: some View {
        List(mgr.history) { intent in
            Button { mgr.currentResult = intent } label: {
                HStack(spacing: 12) {
                    Image(systemName: intent.tool.icon)
                        .foregroundColor(intent.confidence >= 0.7 ? ZDDesign.cyanAccent : .orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(intent.rawQuery).font(.subheadline).foregroundColor(ZDDesign.pureWhite).lineLimit(1)
                        Text(intent.tool.rawValue).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    confidenceBadge(intent.confidence)
                }
            }
            .listRowBackground(ZDDesign.darkCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
            Text("Ask a tactical question").font(.subheadline).foregroundColor(.secondary)
            Text("e.g. \"How far to grid 14S MP 12345 67890?\"").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func confidenceBadge(_ c: Double) -> some View {
        Text("\(Int(c * 100))%")
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(c >= 0.7 ? ZDDesign.successGreen.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundColor(c >= 0.7 ? ZDDesign.successGreen : .orange)
            .cornerRadius(4)
    }
}
