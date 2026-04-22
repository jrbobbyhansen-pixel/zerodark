// PeerDetailsSheet.swift — TAK peer detail view (extracted from TeamMapView)

import SwiftUI

struct PeerDetailsSheet: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    let event: CoTEvent

    var body: some View {
        NavigationStack {
            List {
                Section("Identity") {
                    LabeledContent("Callsign", value: event.detail?.contact?.callsign ?? "Unknown")
                    LabeledContent("UID", value: event.uid.prefix(16) + "...")
                }

                Section("Position") {
                    LabeledContent("Latitude", value: String(format: "%.6f", event.lat))
                    LabeledContent("Longitude", value: String(format: "%.6f", event.lon))

                    if event.hae != 9999999 {
                        LabeledContent("Altitude", value: String(format: "%.1f m", event.hae))
                    }

                    if event.ce != 9999999 {
                        LabeledContent("Accuracy (CE)", value: String(format: "±%.1f m", event.ce))
                    }
                }

                Section("Status") {
                    LabeledContent("Type", value: event.type)
                    LabeledContent("How", value: event.how)

                    if let battery = event.detail?.status?.battery {
                        HStack {
                            Text("Battery")
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon(battery))
                                    .foregroundColor(batteryColor(battery))
                                    .accessibilityHidden(true)
                                Text("\(battery)%")
                            }
                        }
                        .a11yStatus(label: "Battery", value: "\(battery) percent")
                    }

                    let formatter = ISO8601DateFormatter()
                    LabeledContent("Last Update", value: formatter.string(from: event.time))
                }

                Section("Movement") {
                    if let track = event.detail?.track {
                        LabeledContent("Speed", value: String(format: "%.1f m/s (%.1f km/h)", track.speed, track.speed * 3.6))
                        LabeledContent("Course", value: String(format: "%.0f°", track.course))
                    } else {
                        Text("No movement data")
                            .foregroundColor(Color(ZDDesign.mediumGray))
                    }
                }

                Section("Device") {
                    if let takv = event.detail?.takv {
                        LabeledContent("Device", value: takv.device)
                        LabeledContent("Platform", value: takv.platform)
                        LabeledContent("OS", value: takv.os)
                        LabeledContent("Version", value: takv.version)
                    } else {
                        Text("No device info")
                            .foregroundColor(Color(ZDDesign.mediumGray))
                    }
                }
            }
            .navigationTitle(event.detail?.contact?.callsign ?? "Unknown Peer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func batteryIcon(_ percent: Int) -> String {
        switch percent {
        case 75...100: return "battery.100"
        case 50...74: return "battery.75"
        case 25...49: return "battery.50"
        case 1...24: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryColor(_ percent: Int) -> Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }
}
