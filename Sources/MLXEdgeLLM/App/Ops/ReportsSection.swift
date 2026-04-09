// ReportsSection.swift — Ops > Reports sub-section
// Composes: FieldReport + Census + DataValidation + tactical report types

import SwiftUI

struct ReportsSection: View {
    @State private var selectedReport: ReportType?
    @State private var showAARSheet = false

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

                // AAR Report (v6.2 — DTN mesh relay)
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
            AARReportSheet()
        }
    }
}

// MARK: - AAR Report Sheet (v6.2)

struct AARReportSheet: View {
    @StateObject private var mesh = MeshService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    @State private var finding = ""
    @State private var findings: [String] = []
    @State private var recommendation = ""
    @State private var recommendations: [String] = []
    @State private var isSubmitting = false
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Summary
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SUMMARY")
                                .font(.caption).fontWeight(.bold).foregroundColor(ZDDesign.mediumGray)
                            TextField("Mission summary...", text: $summary, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(ZDDesign.darkCard)
                                .cornerRadius(8)
                                .foregroundColor(ZDDesign.pureWhite)
                        }

                        // Findings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FINDINGS")
                                .font(.caption).fontWeight(.bold).foregroundColor(ZDDesign.mediumGray)
                            ForEach(findings, id: \.self) { f in
                                HStack {
                                    Text("- \(f)")
                                        .font(.caption)
                                        .foregroundColor(ZDDesign.pureWhite)
                                    Spacer()
                                }
                            }
                            HStack {
                                TextField("Add finding...", text: $finding)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(ZDDesign.darkCard)
                                    .cornerRadius(8)
                                    .foregroundColor(ZDDesign.pureWhite)
                                Button {
                                    if !finding.isEmpty {
                                        findings.append(finding)
                                        finding = ""
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(ZDDesign.cyanAccent)
                                }
                            }
                        }

                        // Recommendations
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RECOMMENDATIONS")
                                .font(.caption).fontWeight(.bold).foregroundColor(ZDDesign.mediumGray)
                            ForEach(recommendations, id: \.self) { r in
                                HStack {
                                    Text("- \(r)")
                                        .font(.caption)
                                        .foregroundColor(ZDDesign.pureWhite)
                                    Spacer()
                                }
                            }
                            HStack {
                                TextField("Add recommendation...", text: $recommendation)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(ZDDesign.darkCard)
                                    .cornerRadius(8)
                                    .foregroundColor(ZDDesign.pureWhite)
                                Button {
                                    if !recommendation.isEmpty {
                                        recommendations.append(recommendation)
                                        recommendation = ""
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(ZDDesign.cyanAccent)
                                }
                            }
                        }

                        // Submit
                        Button {
                            submitAAR()
                        } label: {
                            HStack {
                                if isSubmitting {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "arrow.triangle.branch")
                                    Text(didSubmit ? "Queued for Relay" : "Queue for DTN Relay")
                                }
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(didSubmit ? ZDDesign.successGreen : ZDDesign.cyanAccent)
                            .cornerRadius(12)
                        }
                        .disabled(summary.isEmpty || isSubmitting || didSubmit)
                    }
                    .padding()
                }
            }
            .navigationTitle("AAR Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
        }
    }

    private func submitAAR() {
        isSubmitting = true
        let participants = mesh.peers.map(\.name) + ["You"]
        let aar = AARBundle(
            participants: participants,
            summary: summary,
            findings: findings,
            recommendations: recommendations
        )

        Task {
            if let bundle = try? aar.toDTNBundle() {
                try? await DTNBuffer.shared.store(bundle)
                ActivityFeed.shared.log(.aarCreated, message: "AAR queued: \(summary.prefix(40))")
            }
            isSubmitting = false
            didSubmit = true
        }
    }
}
