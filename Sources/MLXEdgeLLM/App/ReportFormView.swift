// ReportFormView.swift — Report Form UI for all tactical report types

import SwiftUI

struct ReportFormView: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    let reportType: ReportType

    // Report data
    @State private var sitrep = SITREPReport()
    @State private var medevac = MEDEVACReport()
    @State private var salute = SALUTEReport()
    @State private var contact = ContactReport()

    @ObservedObject private var mesh = MeshService.shared
    @ObservedObject private var activity = ActivityFeed.shared

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        switch reportType {
                        case .sitrep:
                            sitrepForm
                        case .medevac:
                            medevacForm
                        case .salute:
                            saluteForm
                        case .contact:
                            contactForm
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(reportType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendReport()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - SITREP Form

    var sitrepForm: some View {
        VStack(spacing: 16) {
            ReportSection(title: "BASIC INFO") {
                ReportTextField(label: "Unit Callsign", text: $sitrep.unitCallsign)
                ReportTextField(label: "Location (MGRS)", text: $sitrep.location)
                    .onAppear { autoFillLocation(into: $sitrep.location) }
            }

            ReportSection(title: "STATUS") {
                ReportTextArea(label: "Current Situation", text: $sitrep.situation)
                ReportTextArea(label: "Recent Activities", text: $sitrep.activities)
            }

            ReportSection(title: "LOGISTICS") {
                ReportTextField(label: "Casualties", text: $sitrep.casualties)
                ReportTextField(label: "Equipment Status", text: $sitrep.equipmentStatus)
                ReportTextField(label: "Supply Status", text: $sitrep.supplies)

                Picker("Morale", selection: $sitrep.morale) {
                    Text("Excellent").tag("Excellent")
                    Text("Good").tag("Good")
                    Text("Fair").tag("Fair")
                    Text("Poor").tag("Poor")
                }
                .pickerStyle(.segmented)
            }

            ReportSection(title: "PLANS") {
                ReportTextArea(label: "Intentions", text: $sitrep.intentions)
                ReportTextArea(label: "Remarks", text: $sitrep.remarks)
            }
        }
    }

    // MARK: - 9-Line MEDEVAC Form

    var medevacForm: some View {
        VStack(spacing: 16) {
            ReportSection(title: "LOCATION & COMMS") {
                HStack {
                    ReportTextField(label: "Line 1: Pickup Location (MGRS)", text: $medevac.line1_location)
                    Button {
                        autoFillLocation(into: $medevac.line1_location)
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
                ReportTextField(label: "Line 2: Radio Freq/Callsign", text: $medevac.line2_frequency)
            }

            ReportSection(title: "PATIENT INFO") {
                VStack(alignment: .leading) {
                    Text("Line 3: Patients by Precedence")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                    Text("A=Urgent, B=Priority, C=Routine")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                    TextField("e.g., 1A 2B", text: $medevac.line3_patients)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(ZDDesign.darkBackground)
                        .cornerRadius(8)
                        .foregroundColor(ZDDesign.pureWhite)
                }

                ReportTextField(label: "Line 5: Litter/Ambulatory (e.g., 1L 2A)", text: $medevac.line5_litter)
            }

            ReportSection(title: "EQUIPMENT & SECURITY") {
                Picker("Line 4: Special Equipment", selection: $medevac.line4_equipment) {
                    Text("A - None").tag("A")
                    Text("B - Hoist").tag("B")
                    Text("C - Extraction").tag("C")
                    Text("D - Ventilator").tag("D")
                }

                Picker("Line 6: Security at PZ", selection: $medevac.line6_security) {
                    Text("N - No enemy").tag("N")
                    Text("P - Possible enemy").tag("P")
                    Text("E - Enemy in area").tag("E")
                    Text("X - Armed escort required").tag("X")
                }
            }

            ReportSection(title: "MARKING & PATIENT TYPE") {
                Picker("Line 7: Marking Method", selection: $medevac.line7_marking) {
                    Text("A - Panels").tag("A")
                    Text("B - Pyrotechnic").tag("B")
                    Text("C - Smoke").tag("C")
                    Text("D - None").tag("D")
                    Text("E - Other").tag("E")
                }

                Picker("Line 8: Patient Nationality", selection: $medevac.line8_nationality) {
                    Text("A - US Military").tag("A")
                    Text("B - US Civilian").tag("B")
                    Text("C - Non-US Military").tag("C")
                    Text("D - Non-US Civilian").tag("D")
                    Text("E - EPW").tag("E")
                }
            }

            ReportSection(title: "HAZARDS") {
                ReportTextArea(label: "Line 9: NBC/Terrain Obstacles", text: $medevac.line9_terrain)
            }
        }
    }

    // MARK: - SALUTE Form

    var saluteForm: some View {
        VStack(spacing: 16) {
            ReportSection(title: "OBSERVATION") {
                ReportTextField(label: "S - Size (# personnel/vehicles)", text: $salute.size, placeholder: "e.g., 4 personnel, 2 vehicles")
                ReportTextArea(label: "A - Activity", text: $salute.activity, placeholder: "What are they doing?")
                HStack {
                    ReportTextField(label: "L - Location (MGRS)", text: $salute.location)
                    Button {
                        autoFillLocation(into: $salute.location)
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }

            ReportSection(title: "IDENTIFICATION") {
                ReportTextArea(label: "U - Unit (uniforms, insignia, markings)", text: $salute.unit)
                ReportTextArea(label: "E - Equipment (weapons, vehicles)", text: $salute.equipment)
            }
        }
    }

    // MARK: - Contact Report Form

    var contactForm: some View {
        VStack(spacing: 16) {
            ReportSection(title: "CONTACT LOCATION") {
                HStack {
                    ReportTextField(label: "Location (MGRS)", text: $contact.location)
                    Button {
                        autoFillLocation(into: $contact.location)
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }

            ReportSection(title: "ENEMY") {
                ReportTextField(label: "Enemy Size", text: $contact.enemySize, placeholder: "e.g., Squad-sized element")
                ReportTextArea(label: "Enemy Activity", text: $contact.enemyActivity)
                ReportTextField(label: "Direction of Travel/Fire", text: $contact.direction, placeholder: "e.g., Moving NW")
            }

            ReportSection(title: "RESPONSE") {
                ReportTextArea(label: "Actions Taken", text: $contact.actionsTaken)
                ReportTextArea(label: "Requested Support", text: $contact.requestedSupport)
                ReportTextField(label: "Casualties", text: $contact.casualties)
            }
        }
    }

    // MARK: - Actions

    func autoFillLocation(into binding: Binding<String>) {
        if let location = LocationManager.shared.currentLocation {
            binding.wrappedValue = MGRSConverter.toMGRS(coordinate: location, precision: 4)
        }
    }

    func sendReport() {
        let formattedReport: String

        switch reportType {
        case .sitrep:
            formattedReport = sitrep.formatted()
        case .medevac:
            formattedReport = medevac.formatted()
        case .salute:
            formattedReport = salute.formatted()
        case .contact:
            formattedReport = contact.formatted()
        }

        // Send via mesh
        mesh.shareIntel(formattedReport)

        // Log activity
        activity.log(.reportCreated, message: "\(reportType.rawValue) sent to mesh")
    }
}

// MARK: - Supporting Views

struct ReportSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(ZDDesign.mediumGray)

            content
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }
}

struct ReportTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(10)
                .background(ZDDesign.darkBackground)
                .cornerRadius(8)
                .foregroundColor(ZDDesign.pureWhite)
        }
    }
}

struct ReportTextArea: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
            TextEditor(text: $text)
                .frame(minHeight: 60)
                .padding(6)
                .background(ZDDesign.darkBackground)
                .cornerRadius(8)
                .foregroundColor(ZDDesign.pureWhite)
                .scrollContentBackground(.hidden)
        }
    }
}
