// ReportsSection.swift — Ops > Reports sub-section

import SwiftUI

struct ReportsSection: View {
    @State private var selectedReport: ReportType?
    @State private var showAARSheet = false
    @State private var showSitrep = false

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                OpsSectionHeader(icon: "doc.text.fill", title: "FIELD REPORTS", color: ZDDesign.cyanAccent)

                NavigationLink {
                    ComingSoonView(title: "Field Report", icon: "doc.richtext", description: "Generate reports with maps, images, videos & PDF export")
                } label: {
                    OpsSectionCard(
                        icon: "doc.richtext",
                        title: "Field Report",
                        subtitle: "Generate reports with maps, images, videos & PDF export",
                        color: ZDDesign.cyanAccent
                    )
                }

                NavigationLink {
                    VoiceMemoView()
                } label: {
                    OpsSectionCard(
                        icon: "mic.fill",
                        title: "Voice Memos",
                        subtitle: "GPS-tagged audio memos; compressed & queued for DTN mesh relay",
                        color: .orange
                    )
                }

                NavigationLink {
                    CommsLogView()
                } label: {
                    OpsSectionCard(
                        icon: "text.bubble.fill",
                        title: "Comms Log",
                        subtitle: "All sent/received mesh messages — filter, search, export CSV/JSON",
                        color: ZDDesign.cyanAccent
                    )
                }

                OpsSectionHeader(icon: "shield.fill", title: "TACTICAL REPORTS", color: ZDDesign.safetyYellow)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ToolButton(icon: "doc.plaintext", title: "SITREP") {
                        showSitrep = true
                    }
                    ToolButton(icon: "cross.fill", title: "9-Line MEDEVAC") {
                        selectedReport = .medevac
                    }
                    ToolButton(icon: "eye.fill", title: "SALUTE") {
                        selectedReport = .salute
                    }
                    ToolButton(icon: "exclamationmark.bubble.fill", title: "Contact") {
                        selectedReport = .contact
                    }
                }

                OpsSectionHeader(icon: "tablecells.fill", title: "DATA COLLECTION", color: ZDDesign.forestGreen)

                NavigationLink {
                    ComingSoonView(title: "Census Tool", icon: "person.crop.rectangle.stack.fill", description: "Household resource tracking with AR & location scanning")
                } label: {
                    OpsSectionCard(
                        icon: "person.crop.rectangle.stack.fill",
                        title: "Census Tool",
                        subtitle: "Household resource tracking with AR & location scanning",
                        color: ZDDesign.forestGreen
                    )
                }

                NavigationLink {
                    ComingSoonView(title: "Data Validation", icon: "checkmark.diamond.fill", description: "Validate location, AR sessions & audio with scoring")
                } label: {
                    OpsSectionCard(
                        icon: "checkmark.diamond.fill",
                        title: "Data Validation",
                        subtitle: "Validate location, AR sessions & audio with scoring",
                        color: ZDDesign.darkSage
                    )
                }

                OpsSectionHeader(icon: "arrow.triangle.branch", title: "MESH RELAY", color: ZDDesign.cyanAccent)

                Button {
                    showAARSheet = true
                } label: {
                    OpsSectionCard(
                        icon: "doc.badge.clock.fill",
                        title: "AAR Report",
                        subtitle: "After Action Report queued for DTN mesh relay",
                        color: ZDDesign.cyanAccent
                    )
                }
            }
            .padding(.horizontal)
        }
        .sheet(item: $selectedReport) { report in
            ReportFormView(reportType: report)
        }
        .sheet(isPresented: $showSitrep) {
            NavigationStack { SitrepView() }
        }
        .sheet(isPresented: $showAARSheet) {
            NavigationStack {
                ComingSoonView(title: "AAR Report", icon: "doc.badge.clock.fill", description: "After Action Report with structured observations and mesh relay")
            }
        }
    }
}
