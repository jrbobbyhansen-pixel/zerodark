// HydrationCalc.swift — Water needs by activity/temp/altitude/weight. Track intake. Dehydration alerts.

import Foundation
import SwiftUI

// MARK: - DehydrationRisk

enum DehydrationRisk: String {
    case normal   = "Normal"
    case mild     = "Mild Dehydration"
    case moderate = "Moderate Dehydration"
    case severe   = "Severe Dehydration"

    var color: Color {
        switch self {
        case .normal:   return ZDDesign.successGreen
        case .mild:     return ZDDesign.safetyYellow
        case .moderate: return .orange
        case .severe:   return ZDDesign.signalRed
        }
    }
    var icon: String {
        switch self {
        case .normal:   return "drop.fill"
        case .mild:     return "drop.halffull"
        case .moderate: return "exclamationmark.triangle.fill"
        case .severe:   return "person.fill.xmark"
        }
    }
    var symptoms: String {
        switch self {
        case .normal:   return "Well hydrated"
        case .mild:     return "Thirst, dark urine, fatigue"
        case .moderate: return "Headache, dizziness, reduced performance"
        case .severe:   return "Confusion, rapid HR, emergency"
        }
    }
}

// MARK: - IntakeEvent

struct IntakeEvent: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var amountML: Double
    var source: String  // water, electrolyte drink, etc.
}

// MARK: - HydrationCalculator

@MainActor
final class HydrationCalculator: ObservableObject {
    static let shared = HydrationCalculator()

    // MARK: - Inputs
    @Published var bodyWeightKg: Double = 75
    @Published var activity: ActivityLevel = .moderate
    @Published var temperatureC: Double = 25
    @Published var altitudeM: Double = 0
    @Published var intakeLog: [IntakeEvent] = []

    private let saveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("hydration_log.json")

    private init() {
        load()
        // Sync altitude from AltitudeTracker
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.locationUpdate"),
            object: nil, queue: .main
        ) { [weak self] note in
            if let alt = note.userInfo?["altitude"] as? Double {
                Task { @MainActor [weak self] in self?.altitudeM = alt }
            }
        }
    }

    // MARK: - Calculated Needs

    /// Recommended total daily intake in mL.
    var dailyNeedML: Double {
        // Base: 35 mL/kg/day (WHO guideline)
        var need = bodyWeightKg * 35

        // Temperature: +300 mL per 5°C above 20°C
        let tempDelta = max(0, temperatureC - 20)
        need += (tempDelta / 5.0) * 300

        // Activity multiplier
        switch activity {
        case .rest:     need *= 1.0
        case .light:    need *= 1.3
        case .moderate: need *= 1.6
        case .heavy:    need *= 2.0
        case .extreme:  need *= 2.5
        }

        // Altitude: +500 mL above 2500m (increased respiration loss)
        if altitudeM > 2500 { need += 500 }
        if altitudeM > 4000 { need += 500 }

        return need
    }

    var hourlyNeedML: Double { dailyNeedML / 16.0 }   // 16 waking hours

    // MARK: - Intake Tracking

    var todayIntakeML: Double {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return intakeLog.filter { $0.timestamp > startOfDay }.map(\.amountML).reduce(0, +)
    }

    var deficitML: Double { max(0, dailyNeedML - todayIntakeML) }
    var surplusML: Double { max(0, todayIntakeML - dailyNeedML) }

    var hydrationPercentage: Double {
        min(1.0, todayIntakeML / dailyNeedML)
    }

    var risk: DehydrationRisk {
        let pct = hydrationPercentage
        if pct >= 0.9  { return .normal }
        if pct >= 0.7  { return .mild }
        if pct >= 0.5  { return .moderate }
        return .severe
    }

    // MARK: - Log Intake

    func logIntake(amountML: Double, source: String = "Water") {
        intakeLog.insert(IntakeEvent(amountML: amountML, source: source), at: 0)
        if intakeLog.count > 200 { intakeLog = Array(intakeLog.prefix(200)) }
        save()
    }

    func clearToday() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        intakeLog.removeAll { $0.timestamp > startOfDay }
        save()
    }

    // MARK: - Next Drink Reminder

    var nextDrinkReminderML: Double { hourlyNeedML }

    var nextDrinkMessage: String {
        String(format: "Drink %.0f mL now (%@)", nextDrinkReminderML, activity.rawValue.lowercased() + " ops")
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(intakeLog) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([IntakeEvent].self, from: data) else { return }
        intakeLog = loaded
    }
}

// MARK: - HydrationView

struct HydrationView: View {
    @ObservedObject private var calc = HydrationCalculator.shared
    @State private var showLogSheet = false
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        progressCard
                        reminderCard
                        settingsCard
                        historyCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Hydration")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLogSheet = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showLogSheet) { LogIntakeSheet() }
        }
        .preferredColorScheme(.dark)
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: calc.risk.icon)
                    .font(.system(size: 40)).foregroundColor(calc.risk.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(calc.risk.rawValue).font(.title3.bold()).foregroundColor(calc.risk.color)
                    Text(calc.risk.symptoms).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            Divider().background(ZDDesign.mediumGray.opacity(0.3))
            HStack {
                statPill(value: String(format: "%.0f mL", calc.todayIntakeML), label: "Intake", color: ZDDesign.cyanAccent)
                statPill(value: String(format: "%.0f mL", calc.dailyNeedML), label: "Daily Need", color: .orange)
                statPill(value: String(format: "%.0f mL", calc.deficitML), label: "Deficit", color: calc.deficitML > 0 ? ZDDesign.signalRed : ZDDesign.successGreen)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TODAY'S PROGRESS").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", calc.hydrationPercentage * 100))
                    .font(.caption.bold()).foregroundColor(calc.risk.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(ZDDesign.darkCard.opacity(0.6)).frame(height: 16)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [.blue, ZDDesign.cyanAccent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(calc.hydrationPercentage), height: 16)
                }
            }
            .frame(height: 16).cornerRadius(6)

            // Hourly markers
            HStack {
                ForEach(0..<8, id: \.self) { i in
                    let mark = Double(i + 1) / 8.0
                    Rectangle()
                        .fill(calc.hydrationPercentage >= mark ? ZDDesign.cyanAccent.opacity(0.4) : Color.white.opacity(0.08))
                        .frame(height: 4)
                        .cornerRadius(2)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEXT DRINK").font(.caption.bold()).foregroundColor(.secondary)
            HStack {
                Image(systemName: "drop.fill").foregroundColor(.blue)
                Text(calc.nextDrinkMessage).font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Button("Log It") {
                    calc.logIntake(amountML: calc.nextDrinkReminderML)
                }
                .font(.caption.bold()).foregroundColor(.black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(ZDDesign.cyanAccent).cornerRadius(8)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROFILE & CONDITIONS").font(.caption.bold()).foregroundColor(.secondary)
            HStack {
                Text("Weight").font(.subheadline).foregroundColor(ZDDesign.mediumGray)
                Spacer()
                Stepper(String(format: "%.0f kg", calc.bodyWeightKg), value: $calc.bodyWeightKg, in: 40...150, step: 1)
                    .labelsHidden()
                Text(String(format: "%.0f kg", calc.bodyWeightKg)).font(.subheadline).foregroundColor(ZDDesign.pureWhite).frame(width: 55)
            }
            HStack {
                Text("Activity").font(.subheadline).foregroundColor(ZDDesign.mediumGray)
                Spacer()
                Picker("", selection: $calc.activity) {
                    ForEach(ActivityLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(ZDDesign.cyanAccent)
            }
            HStack {
                Text("Temp (°C)").font(.subheadline).foregroundColor(ZDDesign.mediumGray)
                Spacer()
                Stepper(String(format: "%.0f°C", calc.temperatureC), value: $calc.temperatureC, in: -20...50, step: 1)
                    .labelsHidden()
                Text(String(format: "%.0f°C", calc.temperatureC)).font(.subheadline).foregroundColor(ZDDesign.pureWhite).frame(width: 45)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INTAKE LOG").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Button("Clear Today") {
                    calc.clearToday()
                }
                .font(.caption2).foregroundColor(ZDDesign.signalRed)
            }
            let today = Calendar.current.startOfDay(for: Date())
            let todayLogs = calc.intakeLog.filter { $0.timestamp > today }
            if todayLogs.isEmpty {
                Text("No intake logged today").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(todayLogs.prefix(10)) { e in
                    HStack {
                        Image(systemName: "drop.fill").foregroundColor(.blue).font(.caption)
                        Text(String(format: "+%.0f mL", e.amountML))
                            .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                        Text(e.source).font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text(e.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2.monospaced()).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.caption.bold()).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Log Intake Sheet

struct LogIntakeSheet: View {
    @ObservedObject private var calc = HydrationCalculator.shared
    @State private var amountText: String = "500"
    @State private var source: String = "Water"
    @Environment(\.dismiss) private var dismiss

    private let quickAmounts: [Double] = [100, 250, 500, 750, 1000]

    var body: some View {
        NavigationStack {
            Form {
                Section("QUICK AMOUNTS") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickAmounts, id: \.self) { ml in
                                Button("\(Int(ml)) mL") { amountText = String(Int(ml)) }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(amountText == String(Int(ml)) ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                                    .foregroundColor(amountText == String(Int(ml)) ? .black : ZDDesign.pureWhite)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("AMOUNT (mL)") {
                    TextField("500", text: $amountText).keyboardType(.numberPad)
                }
                Section("SOURCE") {
                    TextField("Water, electrolyte drink, IV…", text: $source)
                }
            }
            .navigationTitle("Log Intake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log") {
                        guard let ml = Double(amountText), ml > 0 else { return }
                        calc.logIntake(amountML: ml, source: source.isEmpty ? "Water" : source)
                        dismiss()
                    }
                    .font(.body.bold()).foregroundColor(ZDDesign.cyanAccent)
                    .disabled(Double(amountText) == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
