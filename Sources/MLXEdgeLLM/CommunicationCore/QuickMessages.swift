// QuickMessages.swift — Pre-composed tactical message library
// One-tap send with auto-fill: MGRS location, Zulu time, callsign.
// Built-in: SITREP, MEDEVAC 9-line, SALUTE, Contact Report, Rally, Check-In.
// Custom templates: add, edit, delete. Send via MeshService.

import Foundation
import SwiftUI

// MARK: - QuickMessageCategory

enum QuickMessageCategory: String, CaseIterable, Codable, Identifiable {
    case status     = "Status"
    case medical    = "Medical"
    case contact    = "Contact"
    case navigation = "Navigation"
    case custom     = "Custom"

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .status:     return ZDDesign.cyanAccent
        case .medical:    return .red
        case .contact:    return .orange
        case .navigation: return .green
        case .custom:     return .purple
        }
    }
    var icon: String {
        switch self {
        case .status:     return "doc.plaintext.fill"
        case .medical:    return "cross.case.fill"
        case .contact:    return "exclamationmark.bubble.fill"
        case .navigation: return "mappin.and.ellipse"
        case .custom:     return "pencil.circle.fill"
        }
    }
}

// MARK: - QuickMessageTemplate

struct QuickMessageTemplate: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var body: String    // Supports: {CALLSIGN} {MGRS} {TIME} {DATE} {LAT} {LON} {BATTERY}
    var category: QuickMessageCategory
    var isBuiltIn: Bool = false

    /// Resolves placeholders with live data. Call from @MainActor context.
    @MainActor func resolved() -> String {
        let loc = LocationManager.shared.currentLocation
        let mgrs = loc.map { MGRSConverter.toMGRS(coordinate: $0, precision: 4) } ?? "UNKNOWN"
        let lat = loc.map { String(format: "%.4f", $0.latitude) } ?? "?"
        let lon = loc.map { String(format: "%.4f", $0.longitude) } ?? "?"

        let now = Date()
        let zuluFmt = DateFormatter()
        zuluFmt.dateFormat = "HHmm'Z'"
        zuluFmt.timeZone = TimeZone(identifier: "UTC")
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "ddMMMyyyy"
        dateFmt.timeZone = TimeZone(identifier: "UTC")

        var result = body
        result = result.replacingOccurrences(of: "{CALLSIGN}", with: AppConfig.deviceCallsign)
        result = result.replacingOccurrences(of: "{MGRS}", with: mgrs)
        result = result.replacingOccurrences(of: "{LAT}", with: lat)
        result = result.replacingOccurrences(of: "{LON}", with: lon)
        result = result.replacingOccurrences(of: "{TIME}", with: zuluFmt.string(from: now))
        result = result.replacingOccurrences(of: "{DATE}", with: dateFmt.string(from: now))
        result = result.replacingOccurrences(of: "{BATTERY}", with: "\(batteryPercent)%")
        return result
    }

    private var batteryPercent: Int {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int(UIDevice.current.batteryLevel * 100)
        #else
        return 100
        #endif
    }
}

// MARK: - QuickMessageManager

@MainActor
final class QuickMessageManager: ObservableObject {
    static let shared = QuickMessageManager()

    @Published var templates: [QuickMessageTemplate] = []
    @Published var recentSent: [String] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("quick_messages.json")
    }()

    private init() {
        load()
        ensureBuiltIns()
    }

    // MARK: - Send

    func send(_ template: QuickMessageTemplate) {
        let text = template.resolved()
        MeshService.shared.sendText(text)
        recentSent.insert(text, at: 0)
        if recentSent.count > 20 { recentSent = Array(recentSent.prefix(20)) }
        AuditLogger.shared.log(.observationLogged, detail: "quick_msg_sent:\(template.title)")
    }

    func sendRaw(_ text: String) {
        guard !text.isEmpty else { return }
        MeshService.shared.sendText(text)
        recentSent.insert(text, at: 0)
        if recentSent.count > 20 { recentSent = Array(recentSent.prefix(20)) }
    }

    // MARK: - CRUD

    func addTemplate(_ template: QuickMessageTemplate) {
        var t = template
        t.isBuiltIn = false
        templates.append(t)
        save()
    }

    func delete(_ template: QuickMessageTemplate) {
        guard !template.isBuiltIn else { return }
        templates.removeAll { $0.id == template.id }
        save()
    }

    // MARK: - Built-in Templates

    private func ensureBuiltIns() {
        let existingBuiltInIDs = Set(templates.filter(\.isBuiltIn).map(\.title))
        for t in builtIns where !existingBuiltInIDs.contains(t.title) {
            templates.append(t)
        }
        save()
    }

    private var builtIns: [QuickMessageTemplate] {
        [
            QuickMessageTemplate(
                title: "SITREP Short",
                body: "SITREP {CALLSIGN} — LOC: {MGRS} — TIME: {TIME} — Status: All secure, no casualties.",
                category: .status, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "SITREP Full",
                body: """
SITREP — {DATE} {TIME}Z
1. UNIT: {CALLSIGN}
2. LOC: {MGRS}
3. FRIENDLY: No casualties. All mission-capable.
4. ENEMY: No contact.
5. WEATHER: Unknown.
6. NEXT INT: TBD.
7. NOTES: —
""",
                category: .status, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "Check-In",
                body: "{CALLSIGN} — Check-in @ {TIME}Z — LOC: {MGRS} — Battery: {BATTERY} — Status: Green.",
                category: .status, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "All Clear",
                body: "{CALLSIGN} — ALL CLEAR @ {TIME}Z — LOC: {MGRS}. No threats. Moving as planned.",
                category: .status, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "I'm OK",
                body: "{CALLSIGN} — OK @ {TIME}Z — LOC: {MGRS} — Battery: {BATTERY}.",
                category: .status, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "Moving to Rally",
                body: "{CALLSIGN} — Moving to rally point. ETA unknown. LOC: {MGRS} @ {TIME}Z.",
                category: .navigation, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "At Rally",
                body: "{CALLSIGN} — At rally point @ {TIME}Z — LOC: {MGRS}. Waiting for team.",
                category: .navigation, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "Contact Report (SALUTE)",
                body: """
CONTACT — {CALLSIGN} @ {TIME}Z
SIZE: [enemy count]
ACTIVITY: [what they're doing]
LOCATION: {MGRS}
UNIT: [unit ID if known]
TIME: {TIME}Z
EQUIPMENT: [weapons/vehicles]
""",
                category: .contact, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "9-Line MEDEVAC",
                body: """
9-LINE MEDEVAC — {TIME}Z
1. LOCATION: {MGRS}
2. FREQ/CALLSIGN: [freq] / {CALLSIGN}
3. # PATIENTS: [A-urgent / B-priority / C-routine]
4. SPECIAL EQUIP: None
5. # PATIENTS: [litter/ambulatory]
6. SECURITY: [hot/cold/LZ color]
7. METHOD MARK: [smoke/panel/lights]
8. NATIONALITY: Friendly
9. CBRNE: None
""",
                category: .medical, isBuiltIn: true
            ),
            QuickMessageTemplate(
                title: "Request Resupply",
                body: "{CALLSIGN} — RESUPPLY REQUEST @ {TIME}Z — LOC: {MGRS} — Need: [water/food/ammo/batteries] — Priority: [URGENT/ROUTINE].",
                category: .status, isBuiltIn: true
            ),
        ]
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(templates) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([QuickMessageTemplate].self, from: data) else { return }
        templates = loaded
    }
}

// MARK: - QuickMessagesView

struct QuickMessagesView: View {
    @ObservedObject private var manager = QuickMessageManager.shared
    @State private var selectedCategory: QuickMessageCategory? = nil
    @State private var previewTemplate: QuickMessageTemplate? = nil
    @State private var showAddSheet = false
    @Environment(\.dismiss) private var dismiss

    private var filtered: [QuickMessageTemplate] {
        guard let cat = selectedCategory else { return manager.templates }
        return manager.templates.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    categoryFilter
                    templateList
                }
            }
            .navigationTitle("Quick Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(item: $previewTemplate) { template in
                MessagePreviewSheet(template: template) {
                    manager.send(template)
                    previewTemplate = nil
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NewTemplateSheet { template in
                    manager.addTemplate(template)
                    showAddSheet = false
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All") { selectedCategory = nil }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(selectedCategory == nil ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                    .foregroundColor(selectedCategory == nil ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)

                ForEach(QuickMessageCategory.allCases) { cat in
                    Button {
                        selectedCategory = selectedCategory == cat ? nil : cat
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cat.icon).font(.system(size: 9))
                            Text(cat.rawValue)
                        }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(selectedCategory == cat ? cat.color : ZDDesign.darkCard)
                    .foregroundColor(selectedCategory == cat ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        List {
            ForEach(filtered) { template in
                QuickMessageRow(template: template)
                    .contentShape(Rectangle())
                    .onTapGesture { previewTemplate = template }
                    .listRowBackground(ZDDesign.darkCard)
                    .swipeActions(edge: .leading) {
                        Button {
                            manager.send(template)
                        } label: {
                            Label("Send", systemImage: "paperplane.fill")
                        }
                        .tint(ZDDesign.cyanAccent)
                    }
                    .swipeActions(edge: .trailing) {
                        if !template.isBuiltIn {
                            Button(role: .destructive) {
                                manager.delete(template)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Quick Message Row

struct QuickMessageRow: View {
    let template: QuickMessageTemplate

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(template.category.color.opacity(0.2)).frame(width: 36, height: 36)
                Image(systemName: template.category.icon)
                    .font(.caption.bold()).foregroundColor(template.category.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(template.title).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    if template.isBuiltIn {
                        Text("BUILT-IN")
                            .font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15)).cornerRadius(3)
                    }
                }
                Text(template.body.prefix(80) + (template.body.count > 80 ? "..." : ""))
                    .font(.caption2).foregroundColor(.secondary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "paperplane").font(.caption).foregroundColor(ZDDesign.cyanAccent)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Message Preview Sheet

struct MessagePreviewSheet: View {
    let template: QuickMessageTemplate
    let onSend: () -> Void

    @State private var preview: String = ""
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: template.category.icon).foregroundColor(template.category.color)
                            Text(template.title).font(.headline).foregroundColor(ZDDesign.pureWhite)
                        }
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(ZDDesign.pureWhite)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(12)

                    Button {
                        onSend()
                        sent = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
                    } label: {
                        Label(sent ? "Sent!" : "Send via Mesh", systemImage: sent ? "checkmark" : "paperplane.fill")
                            .font(.headline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(sent ? ZDDesign.successGreen : ZDDesign.cyanAccent)
                            .cornerRadius(12)
                    }
                    .disabled(sent)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
            .onAppear { preview = template.resolved() }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - New Template Sheet

struct NewTemplateSheet: View {
    let onSave: (QuickMessageTemplate) -> Void

    @State private var title: String = ""
    @State private var messageBody: String = ""
    @State private var category: QuickMessageCategory = .custom
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Template Info") {
                        TextField("Title", text: $title).foregroundColor(ZDDesign.pureWhite)
                        Picker("Category", selection: $category) {
                            ForEach(QuickMessageCategory.allCases) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                            }
                        }
                        .colorScheme(.dark)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Body") {
                        TextField("Message body", text: $messageBody, axis: .vertical)
                            .lineLimit(4...10)
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Placeholders") {
                        Text("{CALLSIGN} {MGRS} {TIME} {DATE} {LAT} {LON} {BATTERY}")
                            .font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(QuickMessageTemplate(title: title, body: messageBody, category: category))
                    }
                    .fontWeight(.bold)
                    .disabled(title.isEmpty || messageBody.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
