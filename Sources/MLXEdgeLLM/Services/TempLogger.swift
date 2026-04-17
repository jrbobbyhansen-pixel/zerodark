// TempLogger.swift — Temperature logging, trend graphs, overnight prediction, cold injury risk
// Manual input or from WeatherService. JSON persistence. No internet required.

import Foundation
import SwiftUI

// MARK: - TemperatureUnit

enum TemperatureUnit: String, CaseIterable {
    case celsius    = "°C"
    case fahrenheit = "°F"

    func convert(_ value: Double, to target: TemperatureUnit) -> Double {
        if self == target { return value }
        return self == .celsius ? value * 9/5 + 32 : (value - 32) * 5/9
    }
}

// MARK: - ColdInjuryRisk

enum ColdInjuryRisk: String, CaseIterable {
    case none       = "None"
    case frostnip   = "Frostnip Risk"
    case frostbite  = "Frostbite Risk"
    case hypothermia = "Hypothermia Risk"

    var color: Color {
        switch self {
        case .none:        return ZDDesign.successGreen
        case .frostnip:    return ZDDesign.safetyYellow
        case .frostbite:   return .orange
        case .hypothermia: return ZDDesign.signalRed
        }
    }

    var icon: String {
        switch self {
        case .none:        return "checkmark.shield.fill"
        case .frostnip:    return "thermometer.snowflake"
        case .frostbite:   return "exclamationmark.triangle.fill"
        case .hypothermia: return "person.fill.xmark"
        }
    }

    static func assess(tempC: Double, windKph: Double = 0) -> ColdInjuryRisk {
        // Wind chill (simplified Siple-Passel)
        let wc = tempC <= 10 && windKph > 5
            ? 13.12 + 0.6215 * tempC - 11.37 * pow(windKph, 0.16) + 0.3965 * tempC * pow(windKph, 0.16)
            : tempC
        if wc > 0    { return .none }
        if wc > -10  { return .frostnip }
        if wc > -20  { return .frostbite }
        return .hypothermia
    }
}

// MARK: - TemperatureReading

struct TemperatureReading: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var celsius: Double
    var windKph: Double
    var isManual: Bool
    var source: String

    var fahrenheit: Double { celsius * 9/5 + 32 }
    var windChillC: Double {
        guard celsius <= 10, windKph > 5 else { return celsius }
        return 13.12 + 0.6215 * celsius - 11.37 * pow(windKph, 0.16) + 0.3965 * celsius * pow(windKph, 0.16)
    }
    var risk: ColdInjuryRisk { ColdInjuryRisk.assess(tempC: celsius, windKph: windKph) }
}

// MARK: - TempLogger (ObservableObject)

@MainActor
final class TempLogger: ObservableObject {
    static let shared = TempLogger()

    @Published var readings: [TemperatureReading] = []
    @Published var unit: TemperatureUnit = .fahrenheit

    private let saveURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("temp_log.json")
    private let maxReadings = 500

    private init() { load() }

    // MARK: - Log

    func log(celsius: Double, windKph: Double = 0, isManual: Bool = true, source: String = "Manual") {
        let reading = TemperatureReading(celsius: celsius, windKph: windKph, isManual: isManual, source: source)
        readings.insert(reading, at: 0)
        if readings.count > maxReadings { readings = Array(readings.prefix(maxReadings)) }
        save()
    }

    // MARK: - Derived

    var currentReading: TemperatureReading? { readings.first }
    var currentRisk: ColdInjuryRisk { currentReading.map { $0.risk } ?? .none }

    var last24h: [TemperatureReading] {
        let cutoff = Date().addingTimeInterval(-86400)
        return readings.filter { $0.timestamp > cutoff }.reversed()
    }

    var predictedOvernightLow: Double? {
        guard readings.count >= 3 else { return nil }
        let recent = Array(last24h.suffix(6))
        guard recent.count >= 2 else { return nil }
        // Linear extrapolation to next 6am
        let first = recent.first!; let last = recent.last!
        let deltaT = last.celsius - first.celsius
        let deltaTime = last.timestamp.timeIntervalSince(first.timestamp)
        guard deltaTime > 0 else { return nil }
        let rate = deltaT / deltaTime   // °C/s
        // Hours until 6am
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = 6; components.minute = 0
        var sixAM = cal.date(from: components) ?? Date()
        if sixAM < Date() { sixAM = sixAM.addingTimeInterval(86400) }
        let hoursToSixAM = sixAM.timeIntervalSinceNow
        let projected = last.celsius + rate * hoursToSixAM
        return projected
    }

    var minTemp: Double? { last24h.map(\.celsius).min() }
    var maxTemp: Double? { last24h.map(\.celsius).max() }

    func displayTemp(_ celsius: Double) -> String {
        let val = unit == .fahrenheit ? celsius * 9/5 + 32 : celsius
        return String(format: "%.1f%@", val, unit.rawValue)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(readings) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([TemperatureReading].self, from: data) else { return }
        readings = loaded
    }
}

// MARK: - TempLoggerView

struct TempLoggerView: View {
    @ObservedObject private var logger = TempLogger.shared
    @State private var showLogSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if let r = logger.currentReading {
                            currentCard(r)
                        } else {
                            noDataCard
                        }
                        riskCard
                        if logger.last24h.count > 1 { chartCard }
                        if logger.last24h.count >= 3 { forecastCard }
                        historyCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Temperature Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            logger.unit = logger.unit == .celsius ? .fahrenheit : .celsius
                        } label: {
                            Text(logger.unit.rawValue).font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button { showLogSheet = true } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showLogSheet) { LogTempSheet() }
        }
        .preferredColorScheme(.dark)
    }

    private func currentCard(_ r: TemperatureReading) -> some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT").font(.caption.bold()).foregroundColor(.secondary)
                    Text(logger.displayTemp(r.celsius))
                        .font(.system(size: 52, weight: .bold)).foregroundColor(ZDDesign.pureWhite)
                    if r.windKph > 0 {
                        Text("Wind chill: \(logger.displayTemp(r.windChillC))")
                            .font(.caption).foregroundColor(ZDDesign.cyanAccent)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let hi = logger.maxTemp, let lo = logger.minTemp {
                        Text("H: \(logger.displayTemp(hi))").font(.caption).foregroundColor(.orange)
                        Text("L: \(logger.displayTemp(lo))").font(.caption).foregroundColor(.blue)
                    }
                    Text(r.source).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var noDataCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "thermometer").font(.title).foregroundColor(.secondary)
            Text("No readings logged").font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(ZDDesign.darkCard).cornerRadius(12)
    }

    private var riskCard: some View {
        HStack(spacing: 12) {
            Image(systemName: logger.currentRisk.icon)
                .font(.title2).foregroundColor(logger.currentRisk.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("COLD INJURY RISK").font(.caption.bold()).foregroundColor(.secondary)
                Text(logger.currentRisk.rawValue).font(.subheadline.bold())
                    .foregroundColor(logger.currentRisk.color)
            }
            Spacer()
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("24H TREND").font(.caption.bold()).foregroundColor(.secondary)
            let samples = logger.last24h
            GeometryReader { _ in
                Canvas { ctx, size in
                    guard samples.count > 1 else { return }
                    let temps = samples.map(\.celsius)
                    let minT = (temps.min() ?? 0) - 2
                    let maxT = (temps.max() ?? 0) + 2
                    let range = max(1, maxT - minT)
                    let w = size.width / CGFloat(samples.count - 1)
                    var path = Path()
                    for (i, s) in samples.enumerated() {
                        let x = CGFloat(i) * w
                        let y = size.height - CGFloat((s.celsius - minT) / range) * size.height
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(path, with: .color(ZDDesign.cyanAccent), lineWidth: 1.5)
                    // 0°C reference
                    if minT < 0 && maxT > 0 {
                        let refY = size.height - CGFloat((0 - minT) / range) * size.height
                        var refPath = Path()
                        refPath.move(to: CGPoint(x: 0, y: refY))
                        refPath.addLine(to: CGPoint(x: size.width, y: refY))
                        ctx.stroke(refPath, with: .color(.blue.opacity(0.4)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
            }
            .frame(height: 80)
            .background(Color.white.opacity(0.03))
            .cornerRadius(6)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OVERNIGHT LOW ESTIMATE").font(.caption.bold()).foregroundColor(.secondary)
            if let low = logger.predictedOvernightLow {
                HStack {
                    Image(systemName: "moon.stars.fill").foregroundColor(.indigo)
                    Text("Est. 06:00 low: \(logger.displayTemp(low))")
                        .font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    Spacer()
                    let rsk = ColdInjuryRisk.assess(tempC: low)
                    Text(rsk.rawValue).font(.caption).foregroundColor(rsk.color)
                }
            } else {
                Text("Need more readings for forecast").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOG").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(logger.readings.prefix(10)) { r in
                HStack {
                    Circle().fill(r.risk.color).frame(width: 8, height: 8)
                    Text(logger.displayTemp(r.celsius))
                        .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                    if r.windKph > 0 {
                        Text("WC:\(logger.displayTemp(r.windChillC))")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Text(r.source).font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(r.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospaced()).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}

// MARK: - Log Temp Sheet

struct LogTempSheet: View {
    @ObservedObject private var logger = TempLogger.shared
    @State private var tempText: String = ""
    @State private var windText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("TEMPERATURE (\(logger.unit.rawValue))") {
                    TextField("e.g. 32 or -5", text: $tempText)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section("WIND SPEED (kph, optional)") {
                    TextField("0 if calm", text: $windText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Log Temperature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log") {
                        guard var val = Double(tempText) else { return }
                        if logger.unit == .fahrenheit { val = (val - 32) * 5/9 }
                        let wind = Double(windText) ?? 0
                        logger.log(celsius: val, windKph: wind)
                        dismiss()
                    }
                    .font(.body.bold()).foregroundColor(ZDDesign.cyanAccent)
                    .disabled(Double(tempText) == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
