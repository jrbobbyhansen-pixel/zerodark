// SitrepGenerator.swift — Structured SITREP from live system state
// Pulls real data from LocationManager, CheckInSystem, MeshRelay, WeatherService

import Foundation
import SwiftUI

// MARK: - SitrepGenerator

@MainActor
final class SitrepGenerator: ObservableObject {
    static let shared = SitrepGenerator()

    @Published var currentSitrep: String = ""
    @Published var isGenerating = false
    @Published var lastGenerated: Date?

    private init() {}

    // MARK: - Generate SITREP from Live Data

    func generateSitrep() {
        isGenerating = true
        defer {
            isGenerating = false
            lastGenerated = Date()
        }

        let dtg = formatDTG(Date())
        let callsign = AppConfig.deviceCallsign

        // Location (lastKnownLocation is CLLocationCoordinate2D?, not CLLocation)
        let locationLine: String
        if let coord = LocationManager.shared.lastKnownLocation {
            let mgrs = formatMGRS(lat: coord.latitude, lon: coord.longitude)
            locationLine = mgrs
        } else {
            locationLine = "GPS UNAVAILABLE"
        }

        // Team status
        let checkIns = CheckInSystem.shared.checkIns
        let overdue = CheckInSystem.shared.overdueCheckIns
        let teamLine: String
        if checkIns.isEmpty {
            teamLine = "No check-ins recorded"
        } else {
            let total = checkIns.count
            let overdueCount = overdue.count
            if overdueCount > 0 {
                let names = overdue.map { $0.callsign }.joined(separator: ", ")
                teamLine = "\(total) total, \(overdueCount) OVERDUE: \(names)"
            } else {
                teamLine = "\(total) check-ins, all current"
            }
        }

        // Comms
        let meshPeers = MeshRelay.shared.relayedPeers
        let channel = ChannelManager.shared.selectedChannel
        let commsLine = "Mesh peers: \(meshPeers.count), Channel: \(channel?.name ?? "None")"

        // Weather (cached)
        let weatherLine = WeatherService.shared.currentConditions?.description ?? "No weather data"

        // Assemble SITREP
        var sitrep = """
        ═══════════════════════════════════
        SITUATION REPORT (SITREP)
        ═══════════════════════════════════
        DTG: \(dtg)
        FROM: \(callsign)

        1. SITUATION
           Location: \(locationLine)
           Weather: \(weatherLine)

        2. PERSONNEL
           \(teamLine)

        3. COMMUNICATIONS
           \(commsLine)

        4. LOGISTICS
           Device battery: \(batteryLevel())%

        5. COMMANDER'S ASSESSMENT
           (Enter assessment)
        ═══════════════════════════════════
        """

        currentSitrep = sitrep
        AuditLogger.shared.log(.reportExported, detail: "SITREP generated")
    }

    // MARK: - Helpers

    private func formatDTG(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ddHHmm'Z' MMM yy"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: date).uppercased()
    }

    private func formatMGRS(lat: Double, lon: Double) -> String {
        // Simplified MGRS-like format — full conversion requires UTM library
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%@%.4f %@%.4f", latDir, abs(lat), lonDir, abs(lon))
    }

    private func batteryLevel() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? Int(level * 100) : -1
    }

    func exportSitrep() {
        guard !currentSitrep.isEmpty else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SITREP-\(Int(Date().timeIntervalSince1970)).txt")
        try? currentSitrep.write(to: tempURL, atomically: true, encoding: .utf8)

        let av = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }
}

// MARK: - SitrepView

struct SitrepView: View {
    @StateObject private var gen = SitrepGenerator.shared

    var body: some View {
        Form {
            Section {
                Button {
                    gen.generateSitrep()
                } label: {
                    Label("Generate SITREP", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.cyanAccent)
                .disabled(gen.isGenerating)
            }

            if !gen.currentSitrep.isEmpty {
                Section("Current SITREP") {
                    Text(gen.currentSitrep)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let last = gen.lastGenerated {
                    Section {
                        LabeledContent("Generated", value: last, format: .dateTime)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        gen.exportSitrep()
                    } label: {
                        Label("Export SITREP", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("SITREP Generator")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { SitrepView() }
}
