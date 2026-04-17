// WindEstimator.swift — Estimate wind from Beaufort field obs, baro gradient, and terrain channeling
// Track history, mesh-share readings. No internet required.

import Foundation
import SwiftUI

// MARK: - BeaufortScale

enum BeaufortForce: Int, CaseIterable, Codable {
    case calm = 0, lightAir, lightBreeze, gentleBreeze, moderateBreeze,
         freshBreeze, strongBreeze, nearGale, gale, severeGale, storm

    var description: String {
        switch self {
        case .calm:          return "Calm"
        case .lightAir:      return "Light Air"
        case .lightBreeze:   return "Light Breeze"
        case .gentleBreeze:  return "Gentle Breeze"
        case .moderateBreeze: return "Moderate Breeze"
        case .freshBreeze:   return "Fresh Breeze"
        case .strongBreeze:  return "Strong Breeze"
        case .nearGale:      return "Near Gale"
        case .gale:          return "Gale"
        case .severeGale:    return "Severe Gale"
        case .storm:         return "Storm"
        }
    }

    var kphRange: String {
        switch self {
        case .calm:          return "< 1"
        case .lightAir:      return "1–5"
        case .lightBreeze:   return "6–11"
        case .gentleBreeze:  return "12–19"
        case .moderateBreeze: return "20–28"
        case .freshBreeze:   return "29–38"
        case .strongBreeze:  return "39–49"
        case .nearGale:      return "50–61"
        case .gale:          return "62–74"
        case .severeGale:    return "75–88"
        case .storm:         return "> 89"
        }
    }

    var avgKph: Double {
        switch self {
        case .calm:          return 0
        case .lightAir:      return 3
        case .lightBreeze:   return 8
        case .gentleBreeze:  return 15
        case .moderateBreeze: return 24
        case .freshBreeze:   return 33
        case .strongBreeze:  return 44
        case .nearGale:      return 55
        case .gale:          return 68
        case .severeGale:    return 81
        case .storm:         return 95
        }
    }

    var color: Color {
        switch self {
        case .calm, .lightAir, .lightBreeze, .gentleBreeze: return ZDDesign.successGreen
        case .moderateBreeze, .freshBreeze: return ZDDesign.cyanAccent
        case .strongBreeze, .nearGale: return ZDDesign.safetyYellow
        case .gale, .severeGale, .storm: return ZDDesign.signalRed
        }
    }

    var tacticalNote: String {
        switch self {
        case .calm, .lightAir: return "Flight ops unrestricted"
        case .lightBreeze, .gentleBreeze: return "Ballistic drift minimal"
        case .moderateBreeze: return "Account for drift in precision fire"
        case .freshBreeze: return "Chemical/smoke dispersal rapid"
        case .strongBreeze: return "Rotary wing marginal; drift significant"
        case .nearGale: return "Fixed wing max crosswind; chem unusable"
        case .gale, .severeGale, .storm: return "All aircraft grounded; shelter required"
        }
    }
}

// MARK: - WindObservation

struct WindObservation: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var beaufort: BeaufortForce
    var directionDeg: Double?     // 0-360, nil if unknown
    var estimatedKph: Double
    var terrainNote: String       // e.g., "valley channeling", "ridge exposure"
    var location: String          // MGRS or callsign location

    var cardinalDirection: String {
        guard let d = directionDeg else { return "—" }
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return dirs[Int((d + 11.25) / 22.5) % 16]
    }
}

// MARK: - TerrainChanneling

enum TerrainChanneling: String, CaseIterable {
    case none      = "Open"
    case valley    = "Valley / Canyon"
    case ridge     = "Ridge / Peak"
    case treeline  = "Forest Edge"
    case urban     = "Urban Canyon"

    var speedMultiplier: Double {
        switch self {
        case .none:     return 1.0
        case .valley:   return 1.4    // venturi effect
        case .ridge:    return 1.6    // orographic
        case .treeline: return 0.7    // drag reduction
        case .urban:    return 0.8
        }
    }

    var note: String {
        switch self {
        case .none:     return "No terrain effect"
        case .valley:   return "Venturi: expect 40% speed increase"
        case .ridge:    return "Orographic: exposed, 60% increase"
        case .treeline: return "Reduced by canopy drag"
        case .urban:    return "Deflection and eddies expected"
        }
    }
}

// MARK: - WindEstimator

@MainActor
final class WindEstimator: ObservableObject {
    static let shared = WindEstimator()

    @Published var history: [WindObservation] = []
    @Published var terrain: TerrainChanneling = .none

    private let saveURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("wind_obs.json")

    private init() { load() }

    // MARK: - Log Observation

    func logObservation(beaufort: BeaufortForce, directionDeg: Double?, terrainNote: String = "") {
        let adjustedKph = beaufort.avgKph * terrain.speedMultiplier
        let loc = LocationManager.shared.currentLocation.map {
            MGRSConverter.toMGRS(coordinate: $0, precision: 4)
        } ?? "Unknown"
        let obs = WindObservation(
            beaufort: beaufort,
            directionDeg: directionDeg,
            estimatedKph: adjustedKph,
            terrainNote: terrainNote.isEmpty ? terrain.rawValue : terrainNote,
            location: loc
        )
        history.insert(obs, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        save()
        MeshService.shared.sendText("[wind]\(String(format: "B%d dir%.0f kph%.0f", beaufort.rawValue, directionDeg ?? -1, adjustedKph))")
    }

    // MARK: - Derived

    var latestObservation: WindObservation? { history.first }

    var averageKph: Double {
        guard !history.isEmpty else { return 0 }
        let recent = Array(history.prefix(5))
        return recent.map(\.estimatedKph).reduce(0, +) / Double(recent.count)
    }

    var trend: String {
        guard history.count >= 3 else { return "Insufficient data" }
        let recent = Array(history.prefix(3)).map(\.estimatedKph)
        let delta = recent[0] - recent[2]
        if delta > 5 { return "Increasing" }
        if delta < -5 { return "Decreasing" }
        return "Steady"
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([WindObservation].self, from: data) else { return }
        history = loaded
    }
}

// MARK: - WindEstimatorView

struct WindEstimatorView: View {
    @ObservedObject private var estimator = WindEstimator.shared
    @State private var showLogSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let latest = estimator.latestObservation {
                            currentCard(latest)
                        } else {
                            noDataCard
                        }
                        terrainCard
                        if estimator.history.count >= 3 { trendCard }
                        historyCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Wind Estimator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLogSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showLogSheet) {
                LogWindSheet()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func currentCard(_ obs: WindObservation) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT WIND").font(.caption.bold()).foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.0f", obs.estimatedKph))
                            .font(.system(size: 48, weight: .bold)).foregroundColor(ZDDesign.pureWhite)
                        Text("kph").font(.title3).foregroundColor(.secondary)
                    }
                    Text("Beaufort \(obs.beaufort.rawValue) — \(obs.beaufort.description)")
                        .font(.caption).foregroundColor(obs.beaufort.color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let d = obs.directionDeg {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(ZDDesign.cyanAccent)
                            .rotationEffect(.degrees(d))
                        Text(obs.cardinalDirection)
                            .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                    } else {
                        Image(systemName: "questionmark.circle").foregroundColor(.secondary).font(.title)
                        Text("Dir unknown").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Divider().background(ZDDesign.mediumGray.opacity(0.3))
            HStack {
                Image(systemName: "exclamationmark.bubble.fill").foregroundColor(ZDDesign.safetyYellow).font(.caption)
                Text(obs.beaufort.tacticalNote).font(.caption).foregroundColor(ZDDesign.mediumGray)
                Spacer()
            }
            Text(obs.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var noDataCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "wind").font(.title).foregroundColor(.secondary)
            Text("No observations logged").font(.subheadline).foregroundColor(.secondary)
            Button("Log First Observation") { showLogSheet = true }
                .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(ZDDesign.darkCard).cornerRadius(12)
    }

    private var terrainCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TERRAIN CHANNELING").font(.caption.bold()).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TerrainChanneling.allCases, id: \.self) { t in
                        Button {
                            estimator.terrain = t
                        } label: {
                            Text(t.rawValue)
                                .font(.caption.bold())
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(estimator.terrain == t ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                                .foregroundColor(estimator.terrain == t ? .black : ZDDesign.pureWhite)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            Text(estimator.terrain.note).font(.caption2).foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TREND").font(.caption.bold()).foregroundColor(.secondary)
            HStack {
                Image(systemName: estimator.trend == "Increasing" ? "arrow.up.right" :
                                  estimator.trend == "Decreasing" ? "arrow.down.right" : "arrow.right")
                    .foregroundColor(estimator.trend == "Increasing" ? ZDDesign.signalRed :
                                     estimator.trend == "Decreasing" ? ZDDesign.successGreen : ZDDesign.cyanAccent)
                Text(estimator.trend).font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Text(String(format: "Avg %.0f kph", estimator.averageKph))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OBSERVATION LOG").font(.caption.bold()).foregroundColor(.secondary)
            if estimator.history.isEmpty {
                Text("No observations yet").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(estimator.history.prefix(10)) { obs in
                    HStack {
                        Circle().fill(obs.beaufort.color).frame(width: 8, height: 8)
                        Text("B\(obs.beaufort.rawValue)").font(.caption.bold().monospaced()).foregroundColor(ZDDesign.pureWhite)
                        Text(String(format: "%.0f kph", obs.estimatedKph)).font(.caption).foregroundColor(.secondary)
                        if let d = obs.directionDeg {
                            Text(String(format: "%.0f°", d)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(obs.timestamp.formatted(date: .omitted, time: .shortened))
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

// MARK: - Log Wind Sheet

struct LogWindSheet: View {
    @ObservedObject private var estimator = WindEstimator.shared
    @State private var beaufort: BeaufortForce = .lightBreeze
    @State private var directionText: String = ""
    @State private var note: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("BEAUFORT FORCE") {
                    Picker("Force", selection: $beaufort) {
                        ForEach(BeaufortForce.allCases, id: \.self) { f in
                            Text("B\(f.rawValue) — \(f.description) (\(f.kphRange) kph)").tag(f)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Section("DIRECTION (optional)") {
                    TextField("Degrees 0–360 or leave blank", text: $directionText)
                        .keyboardType(.numberPad)
                }
                Section("NOTE") {
                    TextField("Terrain effect, observation method…", text: $note)
                }
            }
            .navigationTitle("Log Wind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log") {
                        let dir = Double(directionText)
                        estimator.logObservation(beaufort: beaufort, directionDeg: dir, terrainNote: note)
                        dismiss()
                    }
                    .font(.body.bold())
                    .foregroundColor(ZDDesign.cyanAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
