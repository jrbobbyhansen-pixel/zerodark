// ThreatFeedView.swift — Threat classification feed UI

import SwiftUI

struct ThreatFeedView: View {
    @ObservedObject private var classifier = ThreatClassifier.shared
    @State private var showSubmitForm = false
    @State private var reportText = ""
    @State private var selectedCategory: ReportedThreatCategory = .none

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
                            .fill(classifier.unresolvedCount == 0 ? ZDDesign.successGreen : ZDDesign.signalRed)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Resolve", role: .destructive) {
                                        Task { classifier.resolve(report) }
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }

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
            ThreatSubmitSheet(
                isPresented: $showSubmitForm,
                classifier: classifier,
                reportText: $reportText,
                selectedCategory: $selectedCategory
            )
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

                    Text(relativeTime(report.timestamp))
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }

            Text(report.text)
                .font(.caption)
                .foregroundColor(ZDDesign.pureWhite)
                .lineLimit(2)

            if let loc = report.location {
                Label("\(String(format: "%.2f", loc.latitude)), \(String(format: "%.2f", loc.longitude))", systemImage: "location.fill")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
            }
        }
        .padding(8)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct ThreatSubmitSheet: View {
    @Binding var isPresented: Bool
    let classifier: ThreatClassifier
    @Binding var reportText: String
    @Binding var selectedCategory: ReportedThreatCategory
    @State private var reporterID = AppConfig.deviceCallsign
    @State private var isSubmitting = false
    @State private var confirmationMessage = ""
    @State private var showConfirmation = false

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
                        Image(systemName: "xmark").foregroundColor(ZDDesign.mediumGray)
                    }
                }
                .padding()

                // Category picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(ZDDesign.cyanAccent)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(ReportedThreatCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ZDDesign.cyanAccent)
                }
                .padding(.horizontal)

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

                if showConfirmation {
                    Text(confirmationMessage)
                        .font(.caption)
                        .foregroundColor(ZDDesign.successGreen)
                        .padding(.horizontal)
                }

                Spacer()

                Button(action: submit) {
                    if isSubmitting {
                        HStack(spacing: 8) {
                            ProgressView().tint(ZDDesign.darkBackground)
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
        let category = selectedCategory
        Task {
            _ = await classifier.classify(text: reportText, source: reporterID)
            await MainActor.run {
                reportText = ""
                isSubmitting = false
                confirmationMessage = "Reported as \(category.displayName)"
                showConfirmation = true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                isPresented = false
            }
        }
    }
}
