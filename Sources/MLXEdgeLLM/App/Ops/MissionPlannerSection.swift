// MissionPlannerSection.swift — Ops > Planner sub-section
// Composes: OpOrderBuilder, TimelinePlanner, ContingencyMatrix, SAR patterns

import SwiftUI

struct MissionPlannerSection: View {
    @State private var showSARTools = false
    @State private var showTacticalScanner = false

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
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
