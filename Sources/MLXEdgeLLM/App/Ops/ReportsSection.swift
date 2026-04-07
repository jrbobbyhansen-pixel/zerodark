// ReportsSection.swift — Ops > Reports sub-section
// Composes: FieldReport + Census + DataValidation + tactical report types

import SwiftUI

struct ReportsSection: View {
    @State private var selectedReport: ReportType?

    var body: some View {
        ScrollView {
            VStack(spacing: ZDDesign.spacing16) {
                // Field Reports
                OpsSectionHeader(icon: "doc.text.fill", title: "FIELD REPORTS", color: ZDDesign.cyanAccent)

                NavigationLink {
                    FieldReportView()
                } label: {
                    OpsSectionCard(
                        icon: "doc.richtext",
                        title: "Field Report",
                        subtitle: "Generate reports with maps, images, videos & PDF export",
                        color: ZDDesign.cyanAccent
                    )
                }

                // Tactical Report Quick Access
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

                // Data Collection
                OpsSectionHeader(icon: "tablecells.fill", title: "DATA COLLECTION", color: ZDDesign.forestGreen)

                NavigationLink {
                    CensusToolView()
                } label: {
                    OpsSectionCard(
                        icon: "person.crop.rectangle.stack.fill",
                        title: "Census Tool",
                        subtitle: "Household resource tracking with AR & location scanning",
                        color: ZDDesign.forestGreen
                    )
                }

                NavigationLink {
                    DataValidationView()
                } label: {
                    OpsSectionCard(
                        icon: "checkmark.diamond.fill",
                        title: "Data Validation",
                        subtitle: "Validate location, AR sessions & audio with scoring",
                        color: ZDDesign.darkSage
                    )
                }
            }
            .padding(.horizontal)
        }
        .sheet(item: $selectedReport) { report in
            ReportFormView(reportType: report)
        }
    }
}
