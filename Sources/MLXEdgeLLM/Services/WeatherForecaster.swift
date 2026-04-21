// WeatherForecaster.swift — Barometric pressure trend, 12-24hr prediction, storm warning
// No internet required. Uses CMAltimeter for real barometric pressure readings.

import Foundation
import CoreLocation
import CoreMotion
import SwiftUI

// MARK: - BarometricPressureTrend

enum BarometricPressureTrend: String {
    case stable      = "Stable"
    case rapidRise   = "Rising"
    case rapidDrop   = "Falling"

    var icon: String {
        switch self {
        case .stable:    return "arrow.right.circle.fill"
        case .rapidRise: return "arrow.up.right.circle.fill"
        case .rapidDrop: return "arrow.down.right.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .stable:    return ZDDesign.cyanAccent
        case .rapidRise: return ZDDesign.successGreen
        case .rapidDrop: return ZDDesign.signalRed
        }
    }
}

// MARK: - PressureSample

struct PressureSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let hPa: Double
}

// MARK: - ActivityLevel

enum ActivityLevel: String, CaseIterable {
    case rest     = "Rest"
    case light    = "Light"
    case moderate = "Moderate"
    case heavy    = "Heavy"
    case extreme  = "Extreme"
}

// MARK: - WeatherForecaster

@MainActor
final class WeatherForecaster: ObservableObject {
    static let shared = WeatherForecaster()

    @Published private(set) var trend: BarometricPressureTrend = .stable
    @Published private(set) var stormWarning: Bool = false
    @Published private(set) var currentPressureHPa: Double = 1013.25
    @Published private(set) var relativeAltitudeMeters: Double = 0
    @Published private(set) var pressureAltitudeMeters: Double = 0
    @Published private(set) var pressureHistory: [PressureSample] = []   // newest last
    @Published private(set) var forecast: String = "Insufficient data"

    // Legacy compatibility
    var barometricPressureTrend: BarometricPressureTrend { trend }

    private let altimeter = CMAltimeter()
    private let maxSamples = 144   // 12 hours at 5-min intervals

    private init() {
        startAltimeter()
    }

    // MARK: - Altimeter

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let data, error == nil else { return }
            let hPa = data.pressure.doubleValue * 10.0   // kPa → hPa
            Task { @MainActor [weak self] in
                self?.ingestReading(hPa: hPa, relativeAlt: data.relativeAltitude.doubleValue)
            }
        }
    }

    func stopAltimeter() { altimeter.stopRelativeAltitudeUpdates() }

    // MARK: - Ingest + Analyze

    func addPressureReading(_ hPa: Double) { ingestReading(hPa: hPa, relativeAlt: relativeAltitudeMeters) }

    private func ingestReading(hPa: Double, relativeAlt: Double) {
        currentPressureHPa = hPa
        relativeAltitudeMeters = relativeAlt
        pressureAltitudeMeters = pressureAltitude(hPa: hPa)

        pressureHistory.append(PressureSample(timestamp: Date(), hPa: hPa))
        if pressureHistory.count > maxSamples { pressureHistory.removeFirst() }

        analyze()
    }

    private func analyze() {
        // 3-hour window for trend
        let cutoff3h = Date().addingTimeInterval(-10800)
        let recent = pressureHistory.filter { $0.timestamp > cutoff3h }
        guard recent.count >= 3 else { forecast = "Insufficient data"; return }

        let first = recent.first!.hPa
        let last  = recent.last!.hPa
        let delta = last - first

        // NOAA: rapid change = ≥1.5 hPa/3hr
        if delta < -3.0 {
            trend = .rapidDrop; stormWarning = true
            forecast = "Storm likely — rapid pressure fall of \(String(format: "%.1f", abs(delta))) hPa in 3h"
        } else if delta < -1.5 {
            trend = .rapidDrop; stormWarning = false
            forecast = "Deteriorating conditions — pressure falling"
        } else if delta > 3.0 {
            trend = .rapidRise; stormWarning = false
            forecast = "Clearing — pressure rising rapidly"
        } else if delta > 1.5 {
            trend = .rapidRise; stormWarning = false
            forecast = "Improving — pressure rising"
        } else {
            trend = .stable; stormWarning = false
            forecast = "Steady conditions — pressure stable"
        }
    }

    // MARK: - Pressure Altitude (ISA)

    func pressureAltitude(hPa: Double, qnh: Double = 1013.25) -> Double {
        44330.0 * (1.0 - pow(hPa / qnh, 0.1903))
    }

    // MARK: - Hydration Calculator

    func calculateHydrationMlPerHour(tempC: Double, activityLevel: ActivityLevel) -> Double {
        let base = 250.0
        let tempMult: Double
        if tempC < 15      { tempMult = 0.8 }
        else if tempC < 25 { tempMult = 1.0 }
        else if tempC < 35 { tempMult = 1.0 + (tempC - 25) * 0.1 }
        else               { tempMult = 2.0 + (tempC - 35) * 0.15 }
        let actMult: Double
        switch activityLevel {
        case .rest:     actMult = 1.0
        case .light:    actMult = 1.5
        case .moderate: actMult = 2.0
        case .heavy:    actMult = 3.0
        case .extreme:  actMult = 4.0
        }
        return base * tempMult * actMult
    }

    // MARK: - 3h delta helper

    var pressureDelta3h: Double? {
        let cutoff = Date().addingTimeInterval(-10800)
        let slice = pressureHistory.filter { $0.timestamp > cutoff }
        guard let f = slice.first, let l = slice.last else { return nil }
        return l.hPa - f.hPa
    }
}

// MARK: - WeatherForecasterView

struct WeatherForecasterView: View {
    @ObservedObject private var wx = WeatherForecaster.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if wx.stormWarning { stormBanner }
                        currentCard
                        trendCard
                        chartCard
                        altCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Weather Forecaster")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Storm Banner

    private var stormBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill").foregroundColor(.black)
            Text("STORM WARNING — rapid pressure drop")
                .font(.subheadline.bold()).foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(ZDDesign.signalRed)
        .cornerRadius(10)
    }

    // MARK: - Current Card

    private var currentCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRESSURE").font(.caption.bold()).foregroundColor(.secondary)
                    Text(String(format: "%.1f hPa", wx.currentPressureHPa))
                        .font(.largeTitle.bold()).foregroundColor(ZDDesign.pureWhite)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: wx.trend.icon)
                        .font(.title).foregroundColor(wx.trend.color)
                    Text(wx.trend.rawValue)
                        .font(.caption.bold()).foregroundColor(wx.trend.color)
                }
            }
            Divider().background(ZDDesign.mediumGray.opacity(0.3))
            HStack {
                Image(systemName: "text.bubble.fill").foregroundColor(ZDDesign.cyanAccent)
                Text(wx.forecast)
                    .font(.subheadline).foregroundColor(ZDDesign.mediumGray)
                Spacer()
            }
            if let d = wx.pressureDelta3h {
                Text(String(format: "%+.1f hPa / 3h", d))
                    .font(.caption.monospaced())
                    .foregroundColor(d < 0 ? ZDDesign.signalRed : ZDDesign.successGreen)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Trend Interpretation

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INTERPRETATION").font(.caption.bold()).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                trendRow(delta: "<-3.0 hPa/3h", label: "Storm likely", color: ZDDesign.signalRed)
                trendRow(delta: "-1.5 to -3.0", label: "Conditions deteriorating", color: .orange)
                trendRow(delta: "±1.5 hPa", label: "Stable", color: ZDDesign.cyanAccent)
                trendRow(delta: "+1.5 to +3.0", label: "Improving", color: ZDDesign.successGreen)
                trendRow(delta: ">+3.0 hPa/3h", label: "Clearing rapidly", color: ZDDesign.successGreen)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func trendRow(delta: String, label: String, color: Color) -> some View {
        HStack {
            Text(delta).font(.caption.monospaced()).foregroundColor(.secondary).frame(width: 120, alignment: .leading)
            Text(label).font(.caption).foregroundColor(color)
        }
    }

    // MARK: - Pressure Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PRESSURE HISTORY").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Text("\(wx.pressureHistory.count) samples").font(.caption2).foregroundColor(.secondary)
            }
            if wx.pressureHistory.count > 1 {
                GeometryReader { geo in
                    let samples = wx.pressureHistory.map(\.hPa)
                    let minP = (samples.min() ?? 1013) - 2
                    let maxP = (samples.max() ?? 1013) + 2
                    let range = maxP - minP
                    Canvas { ctx, size in
                        guard samples.count > 1 else { return }
                        let w = size.width / CGFloat(samples.count - 1)
                        var path = Path()
                        for (i, val) in samples.enumerated() {
                            let x = CGFloat(i) * w
                            let y = size.height - CGFloat((val - minP) / range) * size.height
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        ctx.stroke(path, with: .color(wx.trend.color), lineWidth: 1.5)
                        // Reference line at 1013.25 hPa
                        let refY = size.height - CGFloat((1013.25 - minP) / range) * size.height
                        var refPath = Path()
                        refPath.move(to: CGPoint(x: 0, y: refY))
                        refPath.addLine(to: CGPoint(x: size.width, y: refY))
                        ctx.stroke(refPath, with: .color(.gray.opacity(0.3)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(height: 80)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            } else {
                Text("Collecting pressure data…")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Altitude Card

    private var altCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRESSURE ALTITUDE").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text(String(format: "%.0f m", wx.pressureAltitudeMeters))
                        .font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text("Pressure Alt").font(.caption2).foregroundColor(.secondary)
                }
                VStack(spacing: 2) {
                    Text(String(format: "%.0f m", wx.relativeAltitudeMeters))
                        .font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text("Rel Altitude").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}
