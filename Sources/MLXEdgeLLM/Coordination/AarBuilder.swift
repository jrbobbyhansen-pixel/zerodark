// AarBuilder.swift — After Action Report builder
// Auto-generates from IncidentLog, TaskAssignment, CheckIn data.
// Supports manual decision/lesson entries. Exports Markdown + PDF.

import Foundation
import SwiftUI
import UIKit

// MARK: - AARSection

enum AARSection: String, CaseIterable, Codable, Identifiable {
    case timeline        = "Timeline"
    case decisions       = "Decisions Made"
    case outcomes        = "Outcomes"
    case lessonsLearned  = "Lessons Learned"
    case sustainImprove  = "Sustain / Improve"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timeline:       return "clock.fill"
        case .decisions:      return "arrow.triangle.branch"
        case .outcomes:       return "checkmark.seal.fill"
        case .lessonsLearned: return "lightbulb.fill"
        case .sustainImprove: return "arrow.up.arrow.down.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .timeline:       return .cyan
        case .decisions:      return .orange
        case .outcomes:       return .green
        case .lessonsLearned: return .yellow
        case .sustainImprove: return .purple
        }
    }
}

// MARK: - AAREntrySource

enum AAREntrySource: String, Codable {
    case auto   = "Auto"    // derived from IncidentLog / Tasks / CheckIns
    case manual = "Manual"  // entered by user
}

// MARK: - AAREntry

struct AAREntry: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var section: AARSection
    var content: String
    var addedBy: String
    var source: AAREntrySource = .manual
    var latitude: Double?
    var longitude: Double?
}

// MARK: - AfterActionReport

struct AfterActionReport: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var missionDate: Date
    var location: String
    var participants: [String]   // callsigns
    var entries: [AAREntry]
    var createdAt: Date = Date()
    var createdBy: String

    func entries(for section: AARSection) -> [AAREntry] {
        entries.filter { $0.section == section }.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - AARManager

@MainActor
final class AARManager: ObservableObject {
    static let shared = AARManager()

    @Published var reports: [AfterActionReport] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aar_reports.json")
    }()

    private init() { load() }

    // MARK: - Auto-generate

    /// Creates a new AAR seeded with auto-pulled data from active data sources.
    func generateAAR(title: String, missionDate: Date, location: String) -> AfterActionReport {
        var entries: [AAREntry] = []
        let callsign = AppConfig.deviceCallsign

        // Pull incidents → Timeline
        for incident in IncidentLogManager.shared.entries {
            entries.append(AAREntry(
                timestamp: incident.timestamp,
                section: .timeline,
                content: "[\(incident.category.rawValue)] \(incident.description) — reported by \(incident.reportedBy)",
                addedBy: incident.reportedBy,
                source: .auto,
                latitude: incident.latitude != 0 ? incident.latitude : nil,
                longitude: incident.longitude != 0 ? incident.longitude : nil
            ))
        }

        // Pull completed tasks → Outcomes
        for task in TaskAssignmentManager.shared.tasks where task.effectiveStatus == .complete {
            let ts = task.completedAt ?? task.dueDate
            entries.append(AAREntry(
                timestamp: ts,
                section: .outcomes,
                content: "[\(task.priority.rawValue.uppercased())] \(task.title) — completed by \(task.assignee)",
                addedBy: task.createdBy,
                source: .auto
            ))
        }

        // Pull overdue tasks → Lessons Learned
        for task in TaskAssignmentManager.shared.tasks where task.effectiveStatus == .overdue {
            entries.append(AAREntry(
                timestamp: task.dueDate,
                section: .lessonsLearned,
                content: "Task overdue: \(task.title) (assigned to \(task.assignee)) — consider resource/time allocation",
                addedBy: callsign,
                source: .auto
            ))
        }

        // Pull check-ins → Timeline
        for checkIn in CheckInSystem.shared.checkIns {
            entries.append(AAREntry(
                timestamp: checkIn.timestamp,
                section: .timeline,
                content: "Check-in: \(checkIn.callsign) at \(String(format: "%.4f, %.4f", checkIn.latitude, checkIn.longitude))",
                addedBy: checkIn.callsign,
                source: .auto,
                latitude: checkIn.latitude != 0 ? checkIn.latitude : nil,
                longitude: checkIn.longitude != 0 ? checkIn.longitude : nil
            ))
        }

        // Derive participants
        let callsigns: [String] = Array(Set(entries.map(\.addedBy))).sorted()

        let report = AfterActionReport(
            title: title,
            missionDate: missionDate,
            location: location,
            participants: callsigns.isEmpty ? [callsign] : callsigns,
            entries: entries,
            createdBy: callsign
        )
        return report
    }

    func save(_ report: AfterActionReport) {
        if let idx = reports.firstIndex(where: { $0.id == report.id }) {
            reports[idx] = report
        } else {
            reports.insert(report, at: 0)
        }
        persist()
    }

    func delete(_ report: AfterActionReport) {
        reports.removeAll { $0.id == report.id }
        persist()
    }

    // MARK: - Entry Management

    func addEntry(_ entry: AAREntry, to reportID: UUID) {
        guard let idx = reports.firstIndex(where: { $0.id == reportID }) else { return }
        reports[idx].entries.append(entry)
        persist()
    }

    func deleteEntry(_ entry: AAREntry, from reportID: UUID) {
        guard let idx = reports.firstIndex(where: { $0.id == reportID }) else { return }
        reports[idx].entries.removeAll { $0.id == entry.id }
        persist()
    }

    // MARK: - Export

    func exportMarkdown(_ report: AfterActionReport) -> URL? {
        var md = "# After Action Report: \(report.title)\n\n"
        md += "**Date:** \(report.missionDate.formatted(date: .long, time: .omitted))  \n"
        md += "**Location:** \(report.location)  \n"
        md += "**Participants:** \(report.participants.joined(separator: ", "))  \n"
        md += "**Prepared by:** \(report.createdBy)  \n"
        md += "**Generated:** \(report.createdAt.formatted())  \n\n"
        md += "---\n\n"

        for section in AARSection.allCases {
            let sectionEntries = report.entries(for: section)
            guard !sectionEntries.isEmpty else { continue }
            md += "## \(section.rawValue)\n\n"
            for entry in sectionEntries {
                let ts = entry.timestamp.formatted(date: .omitted, time: .shortened)
                let src = entry.source == .auto ? "_(auto)_" : "_(manual)_"
                md += "- **\(ts)** \(src) \(entry.content)"
                if let lat = entry.latitude, let lon = entry.longitude {
                    md += " `[\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))]`"
                }
                md += "\n"
            }
            md += "\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AAR_\(report.title.replacingOccurrences(of: " ", with: "_"))_\(Int(Date().timeIntervalSince1970)).md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportPDF(_ report: AfterActionReport) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let margin: CGFloat = 40
            var y: CGFloat = margin

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 20),
                .foregroundColor: UIColor.white
            ]
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 13),
                .foregroundColor: UIColor.systemCyan
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.black
            ]
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.darkGray
            ]
            let width = pageRect.width - margin * 2

            func drawText(_ str: String, attrs: [NSAttributedString.Key: Any], x: CGFloat = margin, maxWidth: CGFloat? = nil, extraSpacing: CGFloat = 4) {
                let nsStr = str as NSString
                let rect = CGRect(x: x, y: y, width: maxWidth ?? width, height: pageRect.height)
                let size = nsStr.boundingRect(with: rect.size, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                nsStr.draw(in: CGRect(x: x, y: y, width: maxWidth ?? width, height: size.height + 1), withAttributes: attrs)
                // Can't use inout for y, handled by assignment
            }

            // Draw title block
            ("After Action Report: " + report.title).draw(in: CGRect(x: margin, y: y, width: width, height: 30), withAttributes: titleAttrs)
            y += 28

            let meta = "Date: \(report.missionDate.formatted(date: .long, time: .omitted))  |  Location: \(report.location)  |  By: \(report.createdBy)"
            meta.draw(in: CGRect(x: margin, y: y, width: width, height: 16), withAttributes: metaAttrs)
            y += 20

            // Separator line
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: margin, y: y))
            linePath.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            UIColor.darkGray.setStroke()
            linePath.lineWidth = 0.5
            linePath.stroke()
            y += 8

            for section in AARSection.allCases {
                let sectionEntries = report.entries(for: section)
                guard !sectionEntries.isEmpty else { continue }

                // New page if near bottom
                if y > pageRect.height - 80 {
                    ctx.beginPage()
                    y = margin
                }

                section.rawValue.uppercased().draw(in: CGRect(x: margin, y: y, width: width, height: 18), withAttributes: headerAttrs)
                y += 18

                for entry in sectionEntries {
                    if y > pageRect.height - 60 {
                        ctx.beginPage()
                        y = margin
                    }
                    let ts = entry.timestamp.formatted(date: .omitted, time: .shortened)
                    let bullet = "  • [\(ts)] \(entry.content)"
                    let nsStr = bullet as NSString
                    let bounds = nsStr.boundingRect(with: CGSize(width: width - 10, height: 200), options: .usesLineFragmentOrigin, attributes: bodyAttrs, context: nil)
                    nsStr.draw(in: CGRect(x: margin + 4, y: y, width: width - 4, height: bounds.height + 1), withAttributes: bodyAttrs)
                    y += bounds.height + 2
                }
                y += 6
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AAR_\(report.title.replacingOccurrences(of: " ", with: "_"))_\(Int(Date().timeIntervalSince1970)).pdf")
        try? data.write(to: url)
        return url
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(reports) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([AfterActionReport].self, from: data) else { return }
        reports = loaded
    }
}

// MARK: - AARBuilderView

struct AARBuilderView: View {
    @ObservedObject private var manager = AARManager.shared
    @State private var showNewSheet = false
    @State private var selectedReport: AfterActionReport?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if manager.reports.isEmpty {
                    emptyState
                } else {
                    reportList
                }
            }
            .navigationTitle("After Action Reports")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewSheet = true
                    } label: {
                        Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showNewSheet) {
                NewAARSheet { report in
                    manager.save(report)
                    selectedReport = report
                    showNewSheet = false
                }
            }
            .sheet(item: $selectedReport) { report in
                AARDetailView(report: report)
                    .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 44)).foregroundColor(.secondary)
            Text("No AARs Yet").font(.headline)
            Text("Tap + to generate a new After Action Report.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var reportList: some View {
        List {
            ForEach(manager.reports) { report in
                Button {
                    selectedReport = report
                } label: {
                    AARRowView(report: report)
                }
                .listRowBackground(ZDDesign.darkCard)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        manager.delete(report)
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - AAR Row

struct AARRowView: View {
    let report: AfterActionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.title).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
            HStack(spacing: 12) {
                Label(report.missionDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption2).foregroundColor(.secondary)
                Label(report.location, systemImage: "mappin")
                    .font(.caption2).foregroundColor(.secondary)
                Label("\(report.entries.count) entries", systemImage: "list.bullet")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Text("By: \(report.createdBy)").font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AAR Detail View

struct AARDetailView: View {
    @State var report: AfterActionReport
    @ObservedObject private var manager = AARManager.shared
    @State private var selectedSection: AARSection = .timeline
    @State private var showAddEntry = false
    @State private var exportURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    sectionPicker
                    entryList
                }
            }
            .navigationTitle(report.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            Button("Export Markdown", systemImage: "doc.text") {
                                exportURL = manager.exportMarkdown(report)
                            }
                            Button("Export PDF", systemImage: "doc.richtext") {
                                exportURL = manager.exportPDF(report)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up").foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button {
                            showAddEntry = true
                        } label: {
                            Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddEntry) {
                AddAAREntrySheet(section: selectedSection, reportID: report.id) { entry in
                    manager.addEntry(entry, to: report.id)
                    // Refresh local state
                    if let updated = manager.reports.first(where: { $0.id == report.id }) {
                        report = updated
                    }
                    showAddEntry = false
                }
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AARSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: section.icon).font(.system(size: 9))
                            Text(section.rawValue).lineLimit(1)
                        }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(selectedSection == section ? section.color : ZDDesign.darkCard)
                    .foregroundColor(selectedSection == section ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var entryList: some View {
        let entries = report.entries(for: selectedSection)
        return Group {
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: selectedSection.icon).font(.system(size: 32)).foregroundColor(.secondary)
                    Text("No \(selectedSection.rawValue) entries").font(.subheadline).foregroundColor(.secondary)
                    Text("Tap + to add one manually.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(entries) { entry in
                        AAREntryRow(entry: entry, sectionColor: selectedSection.color)
                            .listRowBackground(ZDDesign.darkCard)
                            .swipeActions(edge: .trailing) {
                                if entry.source == .manual {
                                    Button(role: .destructive) {
                                        manager.deleteEntry(entry, from: report.id)
                                        if let updated = manager.reports.first(where: { $0.id == report.id }) {
                                            report = updated
                                        }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - AAR Entry Row

struct AAREntryRow: View {
    let entry: AAREntry
    let sectionColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle()
                    .fill(entry.source == .auto ? sectionColor.opacity(0.6) : sectionColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                Rectangle()
                    .fill(sectionColor.opacity(0.2))
                    .frame(width: 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.monospaced()).foregroundColor(.secondary)
                    Spacer()
                    Text(entry.source.rawValue)
                        .font(.caption2).foregroundColor(entry.source == .auto ? .secondary : sectionColor)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background((entry.source == .auto ? Color.secondary : sectionColor).opacity(0.15))
                        .cornerRadius(4)
                }
                Text(entry.content)
                    .font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                HStack(spacing: 8) {
                    Label(entry.addedBy, systemImage: "person").font(.caption2).foregroundColor(.secondary)
                    if let lat = entry.latitude, let lon = entry.longitude {
                        Label(String(format: "%.4f, %.4f", lat, lon), systemImage: "location")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New AAR Sheet

struct NewAARSheet: View {
    let onSave: (AfterActionReport) -> Void

    @State private var title: String = ""
    @State private var missionDate: Date = Date()
    @State private var location: String = ""
    @State private var isGenerating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Mission Details") {
                        TextField("AAR Title", text: $title)
                            .foregroundColor(ZDDesign.pureWhite)
                        DatePicker("Mission Date", selection: $missionDate, displayedComponents: .date)
                            .foregroundColor(ZDDesign.pureWhite)
                            .colorScheme(.dark)
                        TextField("Location / AO", text: $location)
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section {
                        HStack {
                            Image(systemName: "wand.and.stars").foregroundColor(ZDDesign.cyanAccent)
                            Text("Auto-pulls from Incident Log, Tasks, and Check-Ins")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New AAR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Generate") {
                        isGenerating = true
                        let report = AARManager.shared.generateAAR(
                            title: title.isEmpty ? "Mission AAR" : title,
                            missionDate: missionDate,
                            location: location.isEmpty ? "Unknown AO" : location
                        )
                        onSave(report)
                    }
                    .fontWeight(.bold)
                    .foregroundColor(title.isEmpty ? .secondary : ZDDesign.cyanAccent)
                    .disabled(title.isEmpty || isGenerating)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Add AAR Entry Sheet

struct AddAAREntrySheet: View {
    let section: AARSection
    let reportID: UUID
    let onSave: (AAREntry) -> Void

    @State private var content: String = ""
    @State private var selectedSection: AARSection
    @Environment(\.dismiss) private var dismiss

    init(section: AARSection, reportID: UUID, onSave: @escaping (AAREntry) -> Void) {
        self.section = section
        self.reportID = reportID
        self.onSave = onSave
        _selectedSection = State(initialValue: section)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Section") {
                        Picker("Section", selection: $selectedSection) {
                            ForEach(AARSection.allCases) { sec in
                                Label(sec.rawValue, systemImage: sec.icon).tag(sec)
                            }
                        }
                        .colorScheme(.dark)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Entry") {
                        TextField("What happened / was decided / was learned?", text: $content, axis: .vertical)
                            .lineLimit(3...8)
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let entry = AAREntry(
                            section: selectedSection,
                            content: content,
                            addedBy: AppConfig.deviceCallsign,
                            source: .manual
                        )
                        onSave(entry)
                    }
                    .fontWeight(.bold)
                    .disabled(content.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
