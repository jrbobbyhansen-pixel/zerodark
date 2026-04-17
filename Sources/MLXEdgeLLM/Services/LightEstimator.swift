// LightEstimator.swift — Predict light levels by time, location, and cloud cover
// Plan NVG ↔ white-light transitions. Uses SunCalculatorEngine (no ARKit, no internet).

import Foundation
import SwiftUI

// MARK: - LightLevel

enum LightLevel: String, CaseIterable {
    case fullDaylight     = "Full Daylight"
    case overcastDay      = "Overcast Day"
    case goldenHour       = "Golden Hour"
    case civilTwilight    = "Civil Twilight"
    case nauticalTwilight = "Nautical Twilight"
    case astronomicalTwilight = "Astronomical Twilight"
    case night            = "Night"
    case moonlit          = "Moonlit Night"

    var lux: Double {
        switch self {
        case .fullDaylight:           return 100_000
        case .overcastDay:            return 10_000
        case .goldenHour:             return 400
        case .civilTwilight:          return 10
        case .nauticalTwilight:       return 1
        case .astronomicalTwilight:   return 0.1
        case .moonlit:                return 0.5
        case .night:                  return 0.001
        }
    }

    var nvgRecommendation: String {
        switch self {
        case .fullDaylight, .overcastDay: return "White light — NVG not required"
        case .goldenHour:   return "Marginal — NVG ready but not needed"
        case .civilTwilight: return "Transition — NVG recommended"
        case .nauticalTwilight, .astronomicalTwilight: return "NVG required"
        case .moonlit:      return "NVG preferred — partial ambient available"
        case .night:        return "NVG required — no ambient light"
        }
    }

    var icon: String {
        switch self {
        case .fullDaylight, .overcastDay: return "sun.max.fill"
        case .goldenHour:     return "sun.horizon.fill"
        case .civilTwilight:  return "sunset.fill"
        case .nauticalTwilight, .astronomicalTwilight: return "moon.stars.fill"
        case .moonlit:        return "moon.fill"
        case .night:          return "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .fullDaylight:   return .yellow
        case .overcastDay:    return ZDDesign.mediumGray
        case .goldenHour:     return .orange
        case .civilTwilight:  return ZDDesign.cyanAccent
        case .nauticalTwilight: return .indigo
        case .astronomicalTwilight: return .purple
        case .moonlit:        return ZDDesign.safetyYellow.opacity(0.7)
        case .night:          return ZDDesign.mediumGray.opacity(0.5)
        }
    }
}

// MARK: - CloudCover

enum CloudCover: String, CaseIterable {
    case clear     = "Clear"
    case scattered = "Scattered"
    case overcast  = "Overcast"
    case storm     = "Storm"

    var luxMultiplier: Double {
        switch self {
        case .clear:     return 1.0
        case .scattered: return 0.7
        case .overcast:  return 0.1
        case .storm:     return 0.05
        }
    }
}

// MARK: - LightForecastSample

struct LightForecastSample: Identifiable {
    let id = UUID()
    let time: Date
    let level: LightLevel
    let estimatedLux: Double
    let solarAltitude: Double
}

// MARK: - LightEstimator

@MainActor
final class LightEstimator: ObservableObject {
    static let shared = LightEstimator()

    @Published var cloudCover: CloudCover = .clear
    @Published private(set) var currentLevel: LightLevel = .night
    @Published private(set) var currentLux: Double = 0
    @Published private(set) var isNVGMode: Bool = false
    @Published private(set) var forecast: [LightForecastSample] = []

    private var refreshTimer: Timer?

    private init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        guard let loc = LocationManager.shared.currentLocation else { return }
        let now = Date()
        let (level, lux) = estimate(date: now, lat: loc.latitude, lon: loc.longitude)
        currentLevel = level
        currentLux = lux
        isNVGMode = lux < 10
        buildForecast(lat: loc.latitude, lon: loc.longitude)
    }

    // MARK: - Estimation

    func estimate(date: Date, lat: Double, lon: Double) -> (LightLevel, Double) {
        let solarAlt = SunCalculatorEngine.altitude(at: date, lat: lat, lon: lon)
        let moonAge  = MoonCalculatorEngine.age(jd: MoonCalculatorEngine.julianDay(date: date))
        let moonIllum = MoonCalculatorEngine.illumination(age: moonAge)

        let level = lightLevel(solarAlt: solarAlt, moonIllum: moonIllum)
        let baseLux: Double
        if solarAlt > 6 {
            baseLux = max(400, min(100_000, 100_000 * sin(solarAlt * .pi / 180)))
        } else if solarAlt > 0 {
            baseLux = 400 * (solarAlt / 6.0)
        } else if solarAlt > -6 {
            let t = (solarAlt + 6) / 6.0
            baseLux = 10 * t
        } else if solarAlt > -12 {
            let t = (solarAlt + 12) / 6.0
            baseLux = 1.0 * t
        } else if solarAlt > -18 {
            let t = (solarAlt + 18) / 6.0
            baseLux = 0.1 * t
        } else {
            baseLux = moonIllum * 0.5
        }

        let adjustedLux = max(0.001, baseLux * cloudCover.luxMultiplier)
        return (level, adjustedLux)
    }

    private func lightLevel(solarAlt: Double, moonIllum: Double) -> LightLevel {
        if solarAlt > 6 {
            return cloudCover == .overcast || cloudCover == .storm ? .overcastDay : .fullDaylight
        }
        if solarAlt > 0   { return .goldenHour }
        if solarAlt > -6  { return .civilTwilight }
        if solarAlt > -12 { return .nauticalTwilight }
        if solarAlt > -18 { return .astronomicalTwilight }
        return moonIllum > 0.3 ? .moonlit : .night
    }

    // MARK: - 24h Forecast

    private func buildForecast(lat: Double, lon: Double) {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: Date())
        forecast = stride(from: 0, to: 1440, by: 30).map { min -> LightForecastSample in
            let t = start.addingTimeInterval(Double(min) * 60)
            let solarAlt = SunCalculatorEngine.altitude(at: t, lat: lat, lon: lon)
            let moonAge  = MoonCalculatorEngine.age(jd: MoonCalculatorEngine.julianDay(date: t))
            let moonIllum = MoonCalculatorEngine.illumination(age: moonAge)
            let (level, lux) = estimate(date: t, lat: lat, lon: lon)
            return LightForecastSample(time: t, level: level, estimatedLux: lux, solarAltitude: solarAlt)
        }
    }

    // MARK: - NVG Transition Windows

    var nvgTransitionWindows: [(label: String, time: Date)] {
        var windows: [(String, Date)] = []
        let pairs = zip(forecast, forecast.dropFirst())
        for (a, b) in pairs {
            let wasNVG = a.estimatedLux < 10
            let isNVG  = b.estimatedLux < 10
            if !wasNVG && isNVG  { windows.append(("NVG On",  b.time)) }
            if wasNVG  && !isNVG { windows.append(("NVG Off", b.time)) }
        }
        return windows
    }
}

// MARK: - LightEstimatorView

struct LightEstimatorView: View {
    @ObservedObject private var estimator = LightEstimator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        currentCard
                        cloudCard
                        transitionCard
                        chartCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Light Estimator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { estimator.refresh() } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var currentCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: estimator.currentLevel.icon)
                    .font(.system(size: 44))
                    .foregroundColor(estimator.currentLevel.color)
                VStack(alignment: .leading, spacing: 6) {
                    Text(estimator.currentLevel.rawValue)
                        .font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text(String(format: "~%.0f lux", estimator.currentLux))
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                if estimator.isNVGMode {
                    Label("NVG", systemImage: "eye.fill")
                        .font(.caption.bold()).foregroundColor(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(ZDDesign.successGreen)
                        .cornerRadius(6)
                }
            }
            Divider().background(ZDDesign.mediumGray.opacity(0.3))
            Text(estimator.currentLevel.nvgRecommendation)
                .font(.subheadline).foregroundColor(ZDDesign.mediumGray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLOUD COVER").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(CloudCover.allCases, id: \.self) { c in
                    Button {
                        estimator.cloudCover = c
                        estimator.refresh()
                    } label: {
                        Text(c.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(estimator.cloudCover == c ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                            .foregroundColor(estimator.cloudCover == c ? .black : ZDDesign.pureWhite)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var transitionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NVG TRANSITION WINDOWS").font(.caption.bold()).foregroundColor(.secondary)
            let windows = estimator.nvgTransitionWindows
            if windows.isEmpty {
                Text("No transitions in forecast").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(windows, id: \.time) { w in
                    HStack {
                        Image(systemName: w.label == "NVG On" ? "eye.fill" : "eye.slash.fill")
                            .foregroundColor(w.label == "NVG On" ? ZDDesign.successGreen : .orange)
                        Text(w.label).font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                        Spacer()
                        Text(w.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("24H LIGHT FORECAST").font(.caption.bold()).foregroundColor(.secondary)
            GeometryReader { _ in
                let samples = estimator.forecast
                Canvas { ctx, size in
                    guard samples.count > 1 else { return }
                    let w = size.width / CGFloat(samples.count - 1)
                    let maxVal = log10(max(1, samples.map(\.estimatedLux).max() ?? 1) + 1)
                    var path = Path()
                    for (i, s) in samples.enumerated() {
                        let x = CGFloat(i) * w
                        let y = size.height - CGFloat(log10(max(1, s.estimatedLux) + 1) / maxVal) * size.height
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(path, with: .color(ZDDesign.cyanAccent), lineWidth: 1.5)
                    // NVG threshold at 10 lux
                    let nvgY = size.height - CGFloat(log10(11) / maxVal) * size.height
                    var nvgPath = Path()
                    nvgPath.move(to: CGPoint(x: 0, y: nvgY))
                    nvgPath.addLine(to: CGPoint(x: size.width, y: nvgY))
                    ctx.stroke(nvgPath, with: .color(.green.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .frame(height: 80)
            .background(Color.white.opacity(0.03))
            .cornerRadius(6)
            HStack {
                Text("00:00").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("12:00").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("24:00").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}
