// MissionPlannerSection.swift — Ops > Planner sub-section
// Composes: OpOrderBuilder, TimelinePlanner, ContingencyMatrix, SAR patterns

import SwiftUI

struct MissionPlannerSection: View {
    @State private var showSARTools = false
    @State private var showTacticalScanner = false
    @ObservedObject private var clock = MissionClock.shared

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                // Mission Clock
                MissionClockCard(clock: clock)

                // Mission Planning
                OpsSectionHeader(icon: "flag.fill", title: "MISSION PLANNING", color: ZDDesign.cyanAccent)

                NavigationLink {
                    OpOrderBuilderView()
                } label: {
                    OpsSectionCard(
                        icon: "doc.text.fill",
                        title: "Op Order Builder",
                        subtitle: "5-paragraph OPORD with PDF & JSON export",
                        color: ZDDesign.cyanAccent
                    )
                }

                NavigationLink {
                    TimelinePlannerView()
                } label: {
                    OpsSectionCard(
                        icon: "clock.fill",
                        title: "Timeline Planner",
                        subtitle: "Phase tracking with NLT times",
                        color: ZDDesign.forestGreen
                    )
                }

                NavigationLink {
                    ContingencyMatrixView()
                } label: {
                    OpsSectionCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Contingency Matrix",
                        subtitle: "IF/THEN planning with trigger alerts",
                        color: ZDDesign.darkSage
                    )
                }

                // Tactical Tools
                OpsSectionHeader(icon: "wrench.and.screwdriver.fill", title: "TACTICAL TOOLS", color: ZDDesign.cyanAccent)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ToolButton(icon: "magnifyingglass", title: "SAR Patterns") {
                        showSARTools = true
                    }

                    ToolButton(icon: "qrcode.viewfinder", title: "Scanner") {
                        showTacticalScanner = true
                    }
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showSARTools) {
            SARToolsSheet()
        }
        .sheet(isPresented: $showTacticalScanner) {
            TacticalScannerView()
        }
    }
}

// MARK: - Mission Clock Card

private struct MissionClockCard: View {
    @ObservedObject var clock: MissionClock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("MISSION CLOCK")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ZDDesign.cyanAccent)
                Spacer()
                if clock.isCountdownActive {
                    Text("ACTIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            if clock.isCountdownActive, let end = clock.missionEndDate {
                let remaining = max(end.timeIntervalSince(clock.currentTime), 0)
                Text(formatDuration(remaining))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(remaining < 600 ? .red : .white)
                Text("remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Not started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                if clock.isCountdownActive {
                    Button("Stop Mission") {
                        clock.stopMission()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(8)
                } else {
                    Button("Start Mission") {
                        // Default 4-hour mission; TimelinePlanner sets end date for real ops
                        clock.startMission(startDate: Date(), endDate: Date().addingTimeInterval(4 * 3600))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ZDDesign.cyanAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(ZDDesign.cyanAccent.opacity(0.12))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
