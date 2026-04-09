// MedevacRequest.swift — NATO 9-Line MEDEVAC Request
// Auto-fills location from GPS, callsign from config, transmits over mesh

import Foundation
import SwiftUI

// MARK: - 9-Line MEDEVAC Data

struct MedevacData: Identifiable, Codable {
    let id: UUID
    var line1Location: String          // MGRS 8-digit grid
    var line2Frequency: String         // Radio freq + callsign
    var line3Precedence: Precedence    // Urgency
    var line3Count: Int                // Number of casualties
    var line4Equipment: SpecialEquip
    var line5Litter: Int               // Litter patients
    var line5Ambulatory: Int           // Walking patients
    var line6Security: SecurityAtSite
    var line7Marking: MarkingMethod
    var line8Nationality: PatientNationality
    var line9NBC: NBCContamination
    var createdAt: Date
    var transmitted: Bool

    init() {
        self.id = UUID()
        self.line1Location = ""
        self.line2Frequency = ""
        self.line3Precedence = .urgent
        self.line3Count = 1
        self.line4Equipment = .none
        self.line5Litter = 1
        self.line5Ambulatory = 0
        self.line6Security = .noEnemy
        self.line7Marking = .smoke
        self.line8Nationality = .usMilitary
        self.line9NBC = .none
        self.createdAt = Date()
        self.transmitted = false
    }

    enum Precedence: String, CaseIterable, Codable {
        case urgent         = "A - Urgent (1 hr)"
        case urgentSurgical = "B - Urgent Surgical (2 hr)"
        case priority       = "C - Priority (4 hr)"
        case routine        = "D - Routine (24 hr)"
        case convenience    = "E - Convenience"
    }

    enum SpecialEquip: String, CaseIterable, Codable {
        case none        = "N - None"
        case hoist       = "A - Hoist"
        case extraction  = "B - Extraction Equipment"
        case ventilator  = "C - Ventilator"
    }

    enum SecurityAtSite: String, CaseIterable, Codable {
        case noEnemy     = "N - No Enemy"
        case possible    = "P - Possible Enemy"
        case inArea      = "E - Enemy in Area"
        case armedEscort = "X - Armed Escort Required"
    }

    enum MarkingMethod: String, CaseIterable, Codable {
        case panels     = "A - Panels"
        case pyro       = "B - Pyrotechnics"
        case smoke      = "C - Smoke"
        case none       = "D - None"
        case other      = "E - Other"
    }

    enum PatientNationality: String, CaseIterable, Codable {
        case usMilitary   = "A - US Military"
        case alliedMil    = "B - Allied Military"
        case civilian     = "C - Civilian"
        case epw          = "D - EPW"
    }

    enum NBCContamination: String, CaseIterable, Codable {
        case none      = "None"
        case nuclear   = "N - Nuclear"
        case biological = "B - Biological"
        case chemical  = "C - Chemical"
    }

    // MARK: - Formatted Output

    var formattedNineLine: String {
        """
        ═══════════════════════════════════
        9-LINE MEDEVAC REQUEST
        ═══════════════════════════════════
        LINE 1: \(line1Location)
        LINE 2: \(line2Frequency)
        LINE 3: \(line3Count) × \(line3Precedence.rawValue)
        LINE 4: \(line4Equipment.rawValue)
        LINE 5: \(line5Litter)L / \(line5Ambulatory)A
        LINE 6: \(line6Security.rawValue)
        LINE 7: \(line7Marking.rawValue)
        LINE 8: \(line8Nationality.rawValue)
        LINE 9: \(line9NBC.rawValue)
        ═══════════════════════════════════
        DTG: \(DateFormatter.localizedString(from: createdAt, dateStyle: .short, timeStyle: .short))
        STATUS: \(transmitted ? "TRANSMITTED" : "PENDING")
        """
    }
}

// MARK: - MedevacViewModel

@MainActor
final class MedevacViewModel: ObservableObject {
    @Published var request = MedevacData()
    @Published var history: [MedevacData] = []
    @Published var transmitStatus: String?

    init() {
        autoFillLocation()
        autoFillCallsign()
    }

    private func autoFillLocation() {
        if let loc = LocationService.shared.lastKnownLocation {
            let lat = loc.coordinate.latitude
            let lon = loc.coordinate.longitude
            let latDir = lat >= 0 ? "N" : "S"
            let lonDir = lon >= 0 ? "E" : "W"
            request.line1Location = String(format: "%@%.5f %@%.5f", latDir, abs(lat), lonDir, abs(lon))
        } else {
            request.line1Location = "GPS UNAVAILABLE"
        }
    }

    private func autoFillCallsign() {
        let callsign = AppConfig.deviceCallsign
        let channel = ChannelManager.shared.selectedChannel
        let freq = channel?.frequency ?? "MESH"
        request.line2Frequency = "\(freq) / \(callsign)"
    }

    func transmit() {
        request.transmitted = true

        // Broadcast over mesh
        NotificationCenter.default.post(
            name: Notification.Name("ZD.broadcastMeshMessage"),
            object: nil,
            userInfo: [
                "type": "MEDEVAC_9LINE",
                "payload": request.formattedNineLine,
                "priority": "URGENT"
            ]
        )

        history.append(request)
        transmitStatus = "Transmitted at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
        AuditLogger.shared.log(.reportExported, detail: "MEDEVAC 9-line transmitted")

        // Reset for next request
        var newReq = MedevacData()
        newReq.line1Location = request.line1Location
        newReq.line2Frequency = request.line2Frequency
        request = newReq
    }

    func export() {
        let text = request.formattedNineLine
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("MEDEVAC-9LINE.txt")
        try? text.write(to: tempURL, atomically: true, encoding: .utf8)
        let av = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(av, animated: true)
    }
}

// MARK: - MedevacView

struct MedevacView: View {
    @StateObject private var vm = MedevacViewModel()

    var body: some View {
        Form {
            Section("Line 1 — Pickup Location") {
                TextField("MGRS / coordinates", text: $vm.request.line1Location)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Line 2 — Frequency / Callsign") {
                TextField("Freq / callsign", text: $vm.request.line2Frequency)
            }

            Section("Line 3 — Precedence") {
                Picker("Precedence", selection: $vm.request.line3Precedence) {
                    ForEach(MedevacData.Precedence.allCases, id: \.self) { Text($0.rawValue) }
                }
                Stepper("Casualties: \(vm.request.line3Count)", value: $vm.request.line3Count, in: 1...50)
            }

            Section("Line 4 — Special Equipment") {
                Picker("Equipment", selection: $vm.request.line4Equipment) {
                    ForEach(MedevacData.SpecialEquip.allCases, id: \.self) { Text($0.rawValue) }
                }
            }

            Section("Line 5 — Patient Type") {
                Stepper("Litter: \(vm.request.line5Litter)", value: $vm.request.line5Litter, in: 0...50)
                Stepper("Ambulatory: \(vm.request.line5Ambulatory)", value: $vm.request.line5Ambulatory, in: 0...50)
            }

            Section("Line 6 — Security") {
                Picker("Security", selection: $vm.request.line6Security) {
                    ForEach(MedevacData.SecurityAtSite.allCases, id: \.self) { Text($0.rawValue) }
                }
            }

            Section("Line 7 — Marking") {
                Picker("Marking", selection: $vm.request.line7Marking) {
                    ForEach(MedevacData.MarkingMethod.allCases, id: \.self) { Text($0.rawValue) }
                }
            }

            Section("Line 8 — Nationality") {
                Picker("Nationality", selection: $vm.request.line8Nationality) {
                    ForEach(MedevacData.PatientNationality.allCases, id: \.self) { Text($0.rawValue) }
                }
            }

            Section("Line 9 — NBC") {
                Picker("Contamination", selection: $vm.request.line9NBC) {
                    ForEach(MedevacData.NBCContamination.allCases, id: \.self) { Text($0.rawValue) }
                }
            }

            if let status = vm.transmitStatus {
                Section {
                    Label(status, systemImage: "checkmark.circle.fill")
                        .foregroundColor(ZDDesign.successGreen)
                }
            }

            Section {
                Button {
                    vm.transmit()
                } label: {
                    Label("TRANSMIT 9-LINE", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.signalRed)

                Button {
                    vm.export()
                } label: {
                    Label("Export / Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("9-Line MEDEVAC")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { MedevacView() }
}
