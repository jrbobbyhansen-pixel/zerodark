// CommsLog.swift — Timestamped log of all sent/received mesh messages
// Filter by sender, channel, message type. Full-text search. Export CSV/JSON.

import Foundation
import SwiftUI

// MARK: - CommsMessageType

enum CommsMessageType: String, CaseIterable, Codable, Identifiable {
    case text      = "Text"
    case beacon    = "Beacon"
    case location  = "Location"
    case task      = "Task"
    case checkin   = "Check-In"
    case rally     = "Rally"
    case resource  = "Resource"
    case sar       = "SAR"
    case dtn       = "DTN"
    case other     = "Other"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .text:     return "text.bubble"
        case .beacon:   return "dot.radiowaves.left.and.right"
        case .location: return "location.fill"
        case .task:     return "checklist"
        case .checkin:  return "checkmark.shield.fill"
        case .rally:    return "mappin.and.ellipse"
        case .resource: return "bag.fill"
        case .sar:      return "magnifyingglass.circle"
        case .dtn:      return "tray.full"
        case .other:    return "ellipsis.circle"
        }
    }
    var color: Color {
        switch self {
        case .text:     return ZDDesign.cyanAccent
        case .beacon:   return ZDDesign.successGreen
        case .location: return .blue
        case .task:     return .orange
        case .checkin:  return .green
        case .rally:    return .yellow
        case .resource: return .purple
        case .sar:      return .red
        case .dtn:      return .indigo
        case .other:    return .gray
        }
    }
}

// MARK: - CommsDirection

enum CommsDirection: String, Codable { case sent, received }

// MARK: - CommsLogEntry

struct CommsLogEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var sender: String
    var channel: String
    var messageType: CommsMessageType
    var direction: CommsDirection
    var content: String

    static func classify(_ text: String) -> CommsMessageType {
        if text.hasPrefix("[beacon]")       { return .beacon }
        if text.hasPrefix("[checkin")       { return .checkin }
        if text.hasPrefix("[rally]")        { return .rally }
        if text.hasPrefix("[task-assign]") || text.hasPrefix("[task-complete]") { return .task }
        if text.hasPrefix("[resource-low]") { return .resource }
        if text.hasPrefix("[search-assign]") { return .sar }
        if text.hasPrefix("[dtn]")          { return .dtn }
        if text.hasPrefix("[loc]") || text.hasPrefix("LOC:") { return .location }
        return .text
    }
}

// MARK: - CommsLogManager

@MainActor
final class CommsLogManager: ObservableObject {
    static let shared = CommsLogManager()

    @Published var entries: [CommsLogEntry] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("comms_log.json")
    }()
    private let maxEntries = 2000

    private init() {
        load()
        subscribeMesh()
    }

    // MARK: - Add

    func logSent(_ text: String) {
        append(CommsLogEntry(
            sender: AppConfig.deviceCallsign,
            channel: ChannelManager.shared.selectedChannel?.name ?? "Mesh",
            messageType: CommsLogEntry.classify(text),
            direction: .sent,
            content: text
        ))
    }

    func logReceived(_ text: String, from sender: String) {
        append(CommsLogEntry(
            sender: sender,
            channel: ChannelManager.shared.selectedChannel?.name ?? "Mesh",
            messageType: CommsLogEntry.classify(text),
            direction: .received,
            content: text
        ))
    }

    private func append(_ entry: CommsLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    // MARK: - Filtering

    func filtered(
        search: String,
        sender: String?,
        channel: String?,
        type: CommsMessageType?
    ) -> [CommsLogEntry] {
        entries.filter { e in
            (search.isEmpty || e.content.localizedCaseInsensitiveContains(search) || e.sender.localizedCaseInsensitiveContains(search))
            && (sender == nil || e.sender == sender)
            && (channel == nil || e.channel == channel)
            && (type == nil || e.messageType == type)
        }
    }

    var allSenders: [String] { Array(Set(entries.map(\.sender))).sorted() }
    var allChannels: [String] { Array(Set(entries.map(\.channel))).sorted() }

    // MARK: - Export

    func exportCSV() -> URL? {
        var csv = "ID,Timestamp,Direction,Sender,Channel,Type,Content\n"
        let fmt = ISO8601DateFormatter()
        for e in entries {
            let row = [
                e.id.uuidString, fmt.string(from: e.timestamp),
                e.direction.rawValue, e.sender, e.channel, e.messageType.rawValue,
                "\"\(e.content.replacingOccurrences(of: "\"", with: "\"\""))\""
            ].joined(separator: ",")
            csv += row + "\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("comms_log_\(Int(Date().timeIntervalSince1970)).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportJSON() -> URL? {
        guard let data = try? JSONEncoder().encode(entries) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("comms_log_\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Mesh Subscribe

    private func subscribeMesh() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.meshMessage"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            let sender = (note.userInfo?["sender"] as? String)
                ?? (note.userInfo?["peerName"] as? String)
                ?? "Unknown"
            Task { @MainActor [weak self] in
                self?.logReceived(text, from: sender)
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("ZD.messageSent"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.logSent(text)
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([CommsLogEntry].self, from: data) else { return }
        entries = loaded
    }
}

// MARK: - CommsLogView

struct CommsLogView: View {
    @ObservedObject private var manager = CommsLogManager.shared
    @State private var searchText: String = ""
    @State private var filterSender: String? = nil
    @State private var filterChannel: String? = nil
    @State private var filterType: CommsMessageType? = nil
    @State private var exportURL: URL? = nil
    @Environment(\.dismiss) private var dismiss

    private var filtered: [CommsLogEntry] {
        manager.filtered(search: searchText, sender: filterSender, channel: filterChannel, type: filterType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    typeFilter
                    if filtered.isEmpty { emptyState } else { logList }
                }
            }
            .navigationTitle("Comms Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu("Filter Sender") {
                            Button("All Senders") { filterSender = nil }
                            ForEach(manager.allSenders, id: \.self) { s in Button(s) { filterSender = s } }
                        }
                        Menu("Filter Channel") {
                            Button("All Channels") { filterChannel = nil }
                            ForEach(manager.allChannels, id: \.self) { c in Button(c) { filterChannel = c } }
                        }
                        Divider()
                        Button("Export CSV", systemImage: "tablecells") { exportURL = manager.exportCSV() }
                        Button("Export JSON", systemImage: "doc.text") { exportURL = manager.exportJSON() }
                        Divider()
                        Button("Clear Log", systemImage: "trash", role: .destructive) { manager.entries.removeAll() }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
        }
        .preferredColorScheme(.dark)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search messages, senders...", text: $searchText)
                .foregroundColor(ZDDesign.pureWhite)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
        .padding(.horizontal).padding(.top, 8)
    }

    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All") { filterType = nil }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(filterType == nil ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                    .foregroundColor(filterType == nil ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                ForEach(CommsMessageType.allCases) { type in
                    Button { filterType = filterType == type ? nil : type } label: {
                        HStack(spacing: 4) {
                            Image(systemName: type.icon).font(.system(size: 9))
                            Text(type.rawValue)
                        }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(filterType == type ? type.color : ZDDesign.darkCard)
                    .foregroundColor(filterType == type ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var logList: some View {
        List {
            ForEach(filtered) { entry in
                CommsLogRow(entry: entry)
                    .listRowBackground(ZDDesign.darkCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.bubble").font(.system(size: 40)).foregroundColor(.secondary)
            Text(searchText.isEmpty && filterType == nil ? "No messages logged yet." : "No matching messages.")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Comms Log Row

struct CommsLogRow: View {
    let entry: CommsLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 3) {
                Image(systemName: entry.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(entry.direction == .sent ? ZDDesign.cyanAccent : ZDDesign.successGreen)
                    .font(.caption)
                Image(systemName: entry.messageType.icon)
                    .foregroundColor(entry.messageType.color)
                    .font(.system(size: 9))
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.sender).font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text("·").foregroundColor(.secondary)
                    Text(entry.channel).font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospaced()).foregroundColor(.secondary)
                }
                Text(entry.content).font(.caption).foregroundColor(ZDDesign.mediumGray).lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }
}
