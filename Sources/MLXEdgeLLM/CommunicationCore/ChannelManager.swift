// ChannelManager.swift — Tactical communications channel management
// Configure Meshtastic/LoRa channels, AES-256 keys, purpose naming, quick switch.

import Foundation
import SwiftUI
import CryptoKit

// MARK: - ChannelPurpose

enum ChannelPurpose: String, CaseIterable, Codable, Identifiable {
    case command    = "Command"
    case logistics  = "Logistics"
    case medical    = "Medical"
    case mesh       = "Mesh"
    case intel      = "Intel"
    case search     = "Search"
    case admin      = "Admin"
    case custom     = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .command:   return "star.fill"
        case .logistics: return "shippingbox.fill"
        case .medical:   return "cross.case.fill"
        case .mesh:      return "antenna.radiowaves.left.and.right"
        case .intel:     return "eye.fill"
        case .search:    return "magnifyingglass.circle.fill"
        case .admin:     return "doc.text.fill"
        case .custom:    return "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .command:   return ZDDesign.cyanAccent
        case .logistics: return .green
        case .medical:   return .red
        case .mesh:      return .purple
        case .intel:     return .orange
        case .search:    return .yellow
        case .admin:     return .gray
        case .custom:    return ZDDesign.pureWhite
        }
    }
}

// MARK: - Channel

struct Channel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var purpose: ChannelPurpose
    var encryptionKeyHex: String    // AES-256 key stored as hex
    var frequency: String?          // Radio frequency if applicable
    var description: String
    var createdAt: Date
    var isDefault: Bool

    init(
        name: String,
        purpose: ChannelPurpose = .custom,
        encryptionKeyHex: String? = nil,
        frequency: String? = nil,
        description: String = "",
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.purpose = purpose
        self.encryptionKeyHex = encryptionKeyHex ?? ChannelManager.generateKeyHex()
        self.frequency = frequency
        self.description = description
        self.createdAt = Date()
        self.isDefault = isDefault
    }

    var displayFrequency: String { frequency ?? "Mesh" }
    var keyPreview: String { String(encryptionKeyHex.prefix(8)) + "..." }
}

// MARK: - ChannelManager

@MainActor
final class ChannelManager: ObservableObject {
    static let shared = ChannelManager()

    @Published var channels: [Channel] = []
    @Published var selectedChannel: Channel?

    private let persistURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("channels.json")
    }()

    private init() {
        loadChannels()
        if channels.isEmpty { setupDefaultChannels() }
        selectedChannel = channels.first { $0.isDefault } ?? channels.first
    }

    // MARK: - Default Channels

    private func setupDefaultChannels() {
        channels = [
            Channel(name: "Command",   purpose: .command,   frequency: "155.340", description: "C2 command net",    isDefault: true),
            Channel(name: "Logistics", purpose: .logistics, frequency: "155.400", description: "Supply and support"),
            Channel(name: "Medical",   purpose: .medical,   frequency: "155.280", description: "MEDEVAC and TCCC"),
            Channel(name: "Mesh",      purpose: .mesh,      frequency: nil,       description: "Meshtastic default net"),
        ]
        saveChannels()
    }

    // MARK: - CRUD

    func selectChannel(_ channel: Channel) {
        selectedChannel = channel
        broadcastChannelJoin(channel)
        AuditLogger.shared.log(.meshJoined, detail: "channel_selected:\(channel.name)")
    }

    func addChannel(name: String, purpose: ChannelPurpose = .custom, frequency: String? = nil, description: String = "") {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let ch = Channel(name: name, purpose: purpose, frequency: frequency, description: description)
        channels.append(ch)
        saveChannels()
        broadcastChannelJoin(ch)
        AuditLogger.shared.log(.meshJoined, detail: "channel_created:\(name)")
    }

    func removeChannel(_ channel: Channel) {
        guard !channel.isDefault else { return }
        channels.removeAll { $0.id == channel.id }
        if selectedChannel?.id == channel.id {
            selectedChannel = channels.first { $0.isDefault } ?? channels.first
        }
        saveChannels()
        AuditLogger.shared.log(.meshLeft, detail: "channel_removed:\(channel.name)")
    }

    func rotateKey(for channel: Channel) {
        guard let idx = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        channels[idx].encryptionKeyHex = ChannelManager.generateKeyHex()
        saveChannels()
        broadcastKeyRotation(channels[idx])
        AuditLogger.shared.log(.keyRotated, detail: "channel_key_rotated:\(channel.name)")
    }

    // MARK: - Mesh Beacon

    private func broadcastChannelJoin(_ channel: Channel) {
        NotificationCenter.default.post(
            name: Notification.Name("ZD.broadcastChannelBeacon"),
            object: nil,
            userInfo: [
                "type": "channel_join",
                "channelName": channel.name,
                "channelID": channel.id.uuidString,
                "frequency": channel.frequency ?? "mesh"
            ]
        )
    }

    private func broadcastKeyRotation(_ channel: Channel) {
        NotificationCenter.default.post(
            name: Notification.Name("ZD.broadcastKeyDistribution"),
            object: nil,
            userInfo: [
                "channelID": channel.id.uuidString,
                "packet": Data()
            ]
        )
    }

    // MARK: - Key Generation

    nonisolated static func generateKeyHex() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    }

    // MARK: - Persistence

    private func saveChannels() {
        guard let data = try? JSONEncoder().encode(channels) else { return }
        try? data.write(to: persistURL, options: [.atomic, .completeFileProtection])
    }

    private func loadChannels() {
        guard let data = try? Data(contentsOf: persistURL),
              let loaded = try? JSONDecoder().decode([Channel].self, from: data) else { return }
        channels = loaded
    }
}

// MARK: - ChannelManagerView

struct ChannelManagerView: View {
    @ObservedObject private var manager = ChannelManager.shared
    @State private var showAddSheet = false
    @State private var showKeySheet: Channel? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    activeChannelBanner
                    channelList
                }
            }
            .navigationTitle("Channel Manager")
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
            .sheet(isPresented: $showAddSheet) {
                NewChannelSheet { name, purpose, freq, desc in
                    manager.addChannel(name: name, purpose: purpose, frequency: freq, description: desc)
                    showAddSheet = false
                }
            }
            .sheet(item: $showKeySheet) { channel in
                ChannelKeySheet(channel: channel)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Active Channel Banner

    private var activeChannelBanner: some View {
        Group {
            if let active = manager.selectedChannel {
                HStack(spacing: 10) {
                    Image(systemName: active.purpose.icon)
                        .foregroundColor(active.purpose.color)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("ACTIVE").font(.system(size: 9, weight: .black)).foregroundColor(.secondary)
                            Text(active.name).font(.headline.bold()).foregroundColor(ZDDesign.pureWhite)
                        }
                        Text(active.displayFrequency)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.caption2).foregroundColor(ZDDesign.successGreen)
                        Text("AES-256").font(.caption2.bold()).foregroundColor(ZDDesign.successGreen)
                    }
                }
                .padding(12)
                .background(active.purpose.color.opacity(0.12))
                .overlay(
                    Rectangle().frame(height: 2).foregroundColor(active.purpose.color),
                    alignment: .bottom
                )
            }
        }
    }

    // MARK: - Channel List

    private var channelList: some View {
        List {
            ForEach(manager.channels) { channel in
                ChannelRow(channel: channel, isSelected: manager.selectedChannel?.id == channel.id)
                    .contentShape(Rectangle())
                    .onTapGesture { manager.selectChannel(channel) }
                    .listRowBackground(ZDDesign.darkCard)
                    .swipeActions(edge: .leading) {
                        Button {
                            showKeySheet = channel
                        } label: {
                            Label("Key", systemImage: "key.fill")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        if !channel.isDefault {
                            Button(role: .destructive) {
                                manager.removeChannel(channel)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        Button {
                            manager.rotateKey(for: channel)
                        } label: {
                            Label("Rotate Key", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(.purple)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Quick Channel Switcher (compact, for embedding)

struct QuickChannelSwitcher: View {
    @ObservedObject private var manager = ChannelManager.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(manager.channels) { channel in
                    Button {
                        manager.selectChannel(channel)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: channel.purpose.icon).font(.system(size: 10))
                            Text(channel.name).lineLimit(1)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(manager.selectedChannel?.id == channel.id
                            ? channel.purpose.color
                            : ZDDesign.darkCard)
                        .foregroundColor(manager.selectedChannel?.id == channel.id ? .black : ZDDesign.pureWhite)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: Channel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isSelected ? channel.purpose.color.opacity(0.2) : Color.clear)
                    .frame(width: 36, height: 36)
                Image(systemName: channel.purpose.icon)
                    .foregroundColor(isSelected ? channel.purpose.color : .secondary)
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.name).font(.headline).foregroundColor(ZDDesign.pureWhite)
                    if channel.isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                    if isSelected {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold)).foregroundColor(channel.purpose.color)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(channel.purpose.color.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                HStack(spacing: 8) {
                    Label(channel.displayFrequency, systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption2).foregroundColor(.secondary)
                    if !channel.description.isEmpty {
                        Text(channel.description).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.system(size: 8)).foregroundColor(ZDDesign.successGreen)
                Text(channel.keyPreview)
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Channel Sheet

struct NewChannelSheet: View {
    let onSave: (String, ChannelPurpose, String?, String) -> Void

    @State private var name: String = ""
    @State private var purpose: ChannelPurpose = .custom
    @State private var frequency: String = ""
    @State private var description: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Channel Info") {
                        TextField("Channel Name", text: $name).foregroundColor(ZDDesign.pureWhite)
                        Picker("Purpose", selection: $purpose) {
                            ForEach(ChannelPurpose.allCases) { p in
                                Label(p.rawValue, systemImage: p.icon).tag(p)
                            }
                        }
                        .colorScheme(.dark)
                        TextField("Frequency (e.g. 155.340)", text: $frequency).foregroundColor(ZDDesign.pureWhite)
                        TextField("Description", text: $description).foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Encryption") {
                        HStack {
                            Image(systemName: "lock.fill").foregroundColor(ZDDesign.successGreen)
                            Text("AES-256 key auto-generated and distributed to mesh peers.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        onSave(name, purpose, frequency.isEmpty ? nil : frequency, description)
                    }
                    .fontWeight(.bold)
                    .disabled(name.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Channel Key Sheet

struct ChannelKeySheet: View {
    let channel: Channel
    @ObservedObject private var manager = ChannelManager.shared
    @State private var showCopied = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    // Key display
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "lock.fill").foregroundColor(ZDDesign.successGreen)
                            Text("AES-256 Channel Key").font(.caption.bold()).foregroundColor(.secondary)
                        }
                        Text(formatKey(channel.encryptionKeyHex))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ZDDesign.pureWhite)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(ZDDesign.darkCard)
                            .cornerRadius(8)

                        Button {
                            UIPasteboard.general.string = channel.encryptionKeyHex
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopied = false }
                        } label: {
                            Label(showCopied ? "Copied!" : "Copy Key", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption.bold())
                                .foregroundColor(showCopied ? ZDDesign.successGreen : ZDDesign.cyanAccent)
                        }
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(12)

                    // Rotate key action
                    Button {
                        manager.rotateKey(for: channel)
                        dismiss()
                    } label: {
                        Label("Rotate Key", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.orange)
                            .cornerRadius(10)
                    }

                    Text("Rotating the key broadcasts a new key to mesh peers. All team members must be connected to receive the update.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle(channel.name + " Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func formatKey(_ hex: String) -> String {
        // Format as groups of 8 chars for readability
        stride(from: 0, to: hex.count, by: 8).map { i -> String in
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: min(8, hex.count - i))
            return String(hex[start..<end])
        }.joined(separator: " ")
    }
}
