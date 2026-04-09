// ReportsSection.swift — Ops > Reports sub-section

import SwiftUI

struct ReportsSection: View {
    @State private var selectedReport: ReportType?
    @State private var showAARSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                OpsSectionHeader(icon: "doc.text.fill", title: "FIELD REPORTS", color: ZDDesign.cyanAccent)

                NavigationLink {
                    Text("Field Report — Coming Soon").padding()
                } label: {
                    OpsSectionCard(
                        icon: "doc.richtext",
                        title: "Field Report",
                        subtitle: "Generate reports with maps, images, videos & PDF export",
                        color: ZDDesign.cyanAccent
                    )
                }

                OpsSectionHeader(icon: "shield.fill", title: "TACTICAL REPORTS", color: ZDDesign.safetyYellow)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ToolButton(icon: "doc.plaintext", title: "SITREP") {
                        selectedReport = .sitrep
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
                    Text("Census Tool — Coming Soon").padding()
                } label: {
                    OpsSectionCard(
                        icon: "person.crop.rectangle.stack.fill",
                        title: "Census Tool",
                        subtitle: "Household resource tracking with AR & location scanning",
                        color: ZDDesign.forestGreen
                    )
                }

                NavigationLink {
                    Text("Data Validation — Coming Soon").padding()
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
        .sheet(isPresented: $showAARSheet) {
            NavigationStack {
                Text("AAR Report — Coming Soon")
                    .padding()
                    .navigationTitle("AAR Report")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
