// MissionPlannerSection.swift — Ops > Planner sub-section
// Composes: MissionPlanner + FieldExercisePlanner + ControllerConsole + SAR tools

import SwiftUI

struct MissionPlannerSection: View {
    @State private var showSARTools = false
    @State private var showTacticalScanner = false
    @State private var showTacticalNavigation = false

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                // Mission Planning
                OpsSectionHeader(icon: "flag.fill", title: "MISSION PLANNING", color: ZDDesign.cyanAccent)

                NavigationLink {
                    MissionPlanner()
                } label: {
                    OpsSectionCard(
                        icon: "map.fill",
                        title: "Mission Planner",
                        subtitle: "Create missions, phases, objectives & risk assessment",
                        color: ZDDesign.cyanAccent
                    )
                }

                NavigationLink {
                    FieldExercisePlannerView()
                } label: {
                    OpsSectionCard(
                        icon: "figure.run",
                        title: "Field Exercise Planner",
                        subtitle: "Logistics, safety, objectives & evaluation criteria",
                        color: ZDDesign.forestGreen
                    )
                }

                NavigationLink {
                    ControllerConsoleView()
                } label: {
                    OpsSectionCard(
                        icon: "slider.horizontal.3",
                        title: "Controller Console",
                        subtitle: "Exercise control & scenario management",
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

                    ToolButton(icon: "arrow.triangle.turn.up.right.circle", title: "Navigation") {
                        showTacticalNavigation = true
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
        .sheet(isPresented: $showTacticalNavigation) {
            TacticalNavigationView()
        }
    }
}
