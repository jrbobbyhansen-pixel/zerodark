// ThreatFeedView.swift — Threat classification feed UI

import SwiftUI

struct ThreatFeedView: View {
    @StateObject private var classifier = ThreatClassifier.shared
    @State private var showSubmitForm = false
    @State private var reportText = ""
    @State private var reporterID = "SelfReport"

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Threats")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ZDDesign.pureWhite)

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(ZDDesign.successGreen)
                            .frame(width: 32, height: 32)

                        Text("\(classifier.unresolvedCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                }
                .padding()

                if classifier.reports.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()

                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundColor(ZDDesign.successGreen)

                        Text("No Threats Detected")
                            .font(.headline)
                            .foregroundColor(ZDDesign.pureWhite)

                        Text("All clear")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(classifier.reports.filter { !$0.resolved }.sorted { $0.timestamp > $1.timestamp }) { report in
                            ThreatRow(report: report, classifier: classifier)
                                .listRowBackground(ZDDesign.darkCard)
                        }
                    }
                    .listStyle(.plain)
                }

                // Submit button
                Button(action: { showSubmitForm = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Report Threat")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(ZDDesign.cyanAccent)
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showSubmitForm) {
            ThreatSubmitSheet(isPresented: $showSubmitForm, classifier: classifier, reportText: $reportText, reporterID: $reporterID)
        }
        .onAppear {
            classifier.loadReports()
        }
    }
}

struct ThreatRow: View {
    let report: ThreatReport
    let classifier: ThreatClassifier

    var category: ReportedThreatCategory {
        ReportedThreatCategory(rawValue: report.category) ?? .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(ZDDesign.pureWhite)

                    Text(report.source)
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(report.confidence * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(category.color)

                    Text(formatTime(report.timestamp))
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }

            Text(report.text)
                .font(.caption)
                .foregroundColor(ZDDesign.pureWhite)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let loc = report.location {
                    Label("\(String(format: "%.2f", loc.latitude)), \(String(format: "%.2f", loc.longitude))", systemImage: "location.fill")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                Spacer()

                Button(action: { Task { classifier.resolve(report) } }) {
                    Text("Resolve")
                        .font(.caption)
                        .padding(6)
                        .background(ZDDesign.successGreen.opacity(0.2))
                        .cornerRadius(4)
                        .foregroundColor(ZDDesign.successGreen)
                }
            }
        }
        .padding(8)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct ThreatSubmitSheet: View {
    @Binding var isPresented: Bool
    let classifier: ThreatClassifier
    @Binding var reportText: String
    @Binding var reporterID: String
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            ZDDesign.darkBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text("Report Threat")
                        .font(.headline)
                        .foregroundColor(ZDDesign.pureWhite)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
                .padding()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(ZDDesign.cyanAccent)

                    TextEditor(text: $reportText)
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .background(ZDDesign.darkCard)
                        .cornerRadius(8)
                        .foregroundColor(ZDDesign.pureWhite)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reporter ID")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(ZDDesign.cyanAccent)

                    TextField("", text: $reporterID)
                        .textFieldStyle(.roundedBorder)
                        .foregroundColor(ZDDesign.pureWhite)
                }
                .padding(.horizontal)

                Spacer()

                Button(action: submit) {
                    if isSubmitting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(ZDDesign.darkBackground)
                            Text("Classifying...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(ZDDesign.cyanAccent.opacity(0.5))
                        .cornerRadius(8)
                        .foregroundColor(ZDDesign.pureWhite)
                    } else {
                        Text("Submit Report")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(ZDDesign.cyanAccent)
                            .cornerRadius(8)
                            .foregroundColor(.black)
                    }
                }
                .disabled(reportText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                .padding()
            }
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            _ = await classifier.classify(text: reportText, source: reporterID)
            reportText = ""
            isSubmitting = false
            isPresented = false
        }
    }
}
