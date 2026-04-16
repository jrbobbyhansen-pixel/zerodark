// VitalSignsLogger.swift — Vital signs tracking with real deterioration alerts
// Fires UNUserNotificationCenter + in-app banner when vitals cross thresholds

import Foundation
import SwiftUI
import UserNotifications

// MARK: - Vital Sign Entry

struct VitalSignEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var pulse: Int
    var respiration: Int
    var systolic: Int
    var diastolic: Int
    var spo2: Int
    var gcs: Int
    var pupils: PupilResponse
    var notes: String

    enum PupilResponse: String, CaseIterable, Codable {
        case equalReactive   = "PERRL"
        case leftFixed       = "Left Fixed"
        case rightFixed      = "Right Fixed"
        case bilateral       = "Bilateral Fixed"
        case unequal         = "Unequal"
    }

    init(pulse: Int = 0, respiration: Int = 0, systolic: Int = 0, diastolic: Int = 0, spo2: Int = 0, gcs: Int = 15, pupils: PupilResponse = .equalReactive, notes: String = "") {
        self.id = UUID()
        self.timestamp = Date()
        self.pulse = pulse
        self.respiration = respiration
        self.systolic = systolic
        self.diastolic = diastolic
        self.spo2 = spo2
        self.gcs = gcs
        self.pupils = pupils
        self.notes = notes
    }

    var bpFormatted: String { "\(systolic)/\(diastolic)" }
}

// MARK: - Alert

struct VitalAlert: Identifiable {
    let id = UUID()
    let message: String
    let severity: AlertSeverity
    let timestamp: Date

    enum AlertSeverity: String {
        case warning  = "warning"
        case critical = "critical"
    }
}

// MARK: - VitalSignsLogger

@MainActor
final class VitalSignsLogger: ObservableObject {
    static let shared = VitalSignsLogger()

    @Published var entries: [VitalSignEntry] = []
    @Published var alerts: [VitalAlert] = []
    @Published var patientLabel: String = "Patient 1"
    @Published var exportURL: URL?

    private init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .criticalAlert]) { _, _ in }
    }

    // MARK: - Record Entry

    func recordVitals(_ entry: VitalSignEntry) {
        entries.append(entry)
        checkForDeterioration(entry)
        AuditLogger.shared.log(.vitalsRecorded, detail: "HR:\(entry.pulse) SpO2:\(entry.spo2) BP:\(entry.bpFormatted)")
    }

    // MARK: - Deterioration Detection

    private func checkForDeterioration(_ entry: VitalSignEntry) {
        // SpO2 critical
        if entry.spo2 > 0 && entry.spo2 < 90 {
            fireAlert("SpO2 \(entry.spo2)% — CRITICAL HYPOXIA", severity: .critical)
        } else if entry.spo2 >= 90 && entry.spo2 < 94 {
            fireAlert("SpO2 \(entry.spo2)% — Hypoxia warning", severity: .warning)
        }

        // Heart rate
        if entry.pulse > 0 {
            if entry.pulse > 140 {
                fireAlert("HR \(entry.pulse) — Severe tachycardia", severity: .critical)
            } else if entry.pulse < 40 {
                fireAlert("HR \(entry.pulse) — Severe bradycardia", severity: .critical)
            } else if entry.pulse > 120 {
                fireAlert("HR \(entry.pulse) — Tachycardia", severity: .warning)
            }
        }

        // Respiration
        if entry.respiration > 0 {
            if entry.respiration > 30 || entry.respiration < 8 {
                fireAlert("RR \(entry.respiration) — Critical respiratory rate", severity: .critical)
            } else if entry.respiration > 24 || entry.respiration < 10 {
                fireAlert("RR \(entry.respiration) — Abnormal respiratory rate", severity: .warning)
            }
        }

        // Blood pressure
        if entry.systolic > 0 && entry.systolic < 80 {
            fireAlert("SBP \(entry.systolic) — Hypotension / shock", severity: .critical)
        }

        // GCS
        if entry.gcs > 0 && entry.gcs < 9 {
            fireAlert("GCS \(entry.gcs) — Severe brain injury", severity: .critical)
        } else if entry.gcs >= 9 && entry.gcs < 13 {
            fireAlert("GCS \(entry.gcs) — Moderate brain injury", severity: .warning)
        }

        // Pupils
        if entry.pupils == .bilateral {
            fireAlert("Bilateral fixed pupils — Brainstem compromise", severity: .critical)
        }

        // Trend: HR rising >20bpm from 2 entries ago
        if entries.count >= 3 {
            let prev = entries[entries.count - 3]
            if entry.pulse > 0 && prev.pulse > 0 && (entry.pulse - prev.pulse) > 20 {
                fireAlert("HR trend ↑\(entry.pulse - prev.pulse) bpm in \(Int(entry.timestamp.timeIntervalSince(prev.timestamp) / 60)) min", severity: .warning)
            }
        }
    }

    private func fireAlert(_ message: String, severity: VitalAlert.AlertSeverity) {
        let alert = VitalAlert(message: message, severity: severity, timestamp: Date())
        alerts.append(alert)

        // Local notification
        let content = UNMutableNotificationContent()
        content.title = severity == .critical ? "CRITICAL VITAL SIGN" : "Vital Sign Alert"
        content.body = "\(patientLabel): \(message)"
        content.sound = severity == .critical ? .defaultCritical : .default
        if severity == .critical { content.interruptionLevel = .critical }

        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }

        // In-app banner
        NotificationCenter.default.post(
            name: Notification.Name("ZD.inAppAlert"),
            object: nil,
            userInfo: [
                "title": content.title,
                "body": content.body,
                "severity": severity.rawValue
            ]
        )
    }

    // MARK: - Export

    func exportCSV() -> String {
        var csv = "Timestamp,HR,RR,SBP,DBP,SpO2,GCS,Pupils,Notes\n"
        let fmt = ISO8601DateFormatter()
        for e in entries {
            csv += "\(fmt.string(from: e.timestamp)),\(e.pulse),\(e.respiration),\(e.systolic),\(e.diastolic),\(e.spo2),\(e.gcs),\(e.pupils.rawValue),\"\(e.notes)\"\n"
        }
        return csv
    }

    func shareExport() {
        let csv = exportCSV()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vitals_\(patientLabel).csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        exportURL = tempURL
    }
}

// MARK: - VitalSignsLoggerView

struct VitalSignsLoggerView: View {
    @ObservedObject private var logger = VitalSignsLogger.shared
    @State private var showAddSheet = false

    var body: some View {
        Form {
            Section("Patient") {
                TextField("Patient Label", text: $logger.patientLabel)
            }

            // Alerts
            if !logger.alerts.isEmpty {
                Section("Alerts (\(logger.alerts.count))") {
                    ForEach(logger.alerts.suffix(5).reversed()) { alert in
                        HStack(spacing: 8) {
                            Image(systemName: alert.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(alert.severity == .critical ? ZDDesign.signalRed : ZDDesign.safetyYellow)
                            Text(alert.message).font(.caption)
                            Spacer()
                            Text(alert.timestamp, style: .time).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Latest vitals
            if let last = logger.entries.last {
                Section("Latest Vitals") {
                    HStack {
                        VitalCard(label: "HR", value: "\(last.pulse)", unit: "bpm", alert: last.pulse > 120 || last.pulse < 50)
                        VitalCard(label: "RR", value: "\(last.respiration)", unit: "/min", alert: last.respiration > 24 || last.respiration < 10)
                        VitalCard(label: "SpO2", value: "\(last.spo2)", unit: "%", alert: last.spo2 < 94)
                    }
                    HStack {
                        VitalCard(label: "BP", value: last.bpFormatted, unit: "mmHg", alert: last.systolic < 90)
                        VitalCard(label: "GCS", value: "\(last.gcs)", unit: "/15", alert: last.gcs < 13)
                        VitalCard(label: "Pupils", value: last.pupils.rawValue, unit: "", alert: last.pupils != .equalReactive)
                    }
                }
            }

            Section {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Record Vital Signs", systemImage: "heart.text.square.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.cyanAccent)
            }

            // History
            if !logger.entries.isEmpty {
                Section("History (\(logger.entries.count) entries)") {
                    ForEach(logger.entries.suffix(10).reversed()) { entry in
                        HStack {
                            Text(entry.timestamp, style: .time).font(.caption).frame(width: 60, alignment: .leading)
                            Text("HR:\(entry.pulse)").font(.caption2)
                            Text("SpO2:\(entry.spo2)").font(.caption2)
                            Text("BP:\(entry.bpFormatted)").font(.caption2)
                            Text("GCS:\(entry.gcs)").font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button {
                        logger.shareExport()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Vital Signs")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddSheet) {
            AddVitalsSheet(logger: logger)
        }
        .sheet(item: $logger.exportURL) { url in
            ShareSheet(items: [url])
        }
    }
}

// MARK: - Vital Card

private struct VitalCard: View {
    let label: String
    let value: String
    let unit: String
    let alert: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
            Text(value).font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(alert ? ZDDesign.signalRed : .primary)
            if !unit.isEmpty {
                Text(unit).font(.system(size: 8)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(alert ? Color.red.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - Add Vitals Sheet

private struct AddVitalsSheet: View {
    @ObservedObject var logger: VitalSignsLogger
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var pulse = ""
    @State private var resp = ""
    @State private var systolic = ""
    @State private var diastolic = ""
    @State private var spo2 = ""
    @State private var gcs = "15"
    @State private var pupils: VitalSignEntry.PupilResponse = .equalReactive
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Vitals") {
                    HStack { Text("Heart Rate"); Spacer(); TextField("bpm", text: $pulse).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    HStack { Text("Resp Rate"); Spacer(); TextField("/min", text: $resp).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    HStack { Text("SpO2"); Spacer(); TextField("%", text: $spo2).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80) }
                }
                Section("Blood Pressure") {
                    HStack {
                        TextField("Systolic", text: $systolic).keyboardType(.numberPad)
                        Text("/")
                        TextField("Diastolic", text: $diastolic).keyboardType(.numberPad)
                    }
                }
                Section("Neuro") {
                    HStack { Text("GCS"); Spacer(); TextField("/15", text: $gcs).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    Picker("Pupils", selection: $pupils) {
                        ForEach(VitalSignEntry.PupilResponse.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }
            }
            .navigationTitle("Record Vitals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let entry = VitalSignEntry(
                            pulse: Int(pulse) ?? 0,
                            respiration: Int(resp) ?? 0,
                            systolic: Int(systolic) ?? 0,
                            diastolic: Int(diastolic) ?? 0,
                            spo2: Int(spo2) ?? 0,
                            gcs: Int(gcs) ?? 15,
                            pupils: pupils,
                            notes: notes
                        )
                        logger.recordVitals(entry)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { VitalSignsLoggerView() }
}
