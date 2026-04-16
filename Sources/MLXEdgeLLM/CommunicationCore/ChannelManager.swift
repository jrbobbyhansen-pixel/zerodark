// ChannelManager.swift — Tactical communications channel management
// Full implementation: create channels with AES-256 keys, persist, broadcast mesh beacon

import Foundation
import SwiftUI
import CryptoKit

// MARK: - Channel

struct Channel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var encryptionKeyHex: String    // AES-256 key stored as hex (never plaintext password)
    var frequency: String?          // Radio frequency if applicable
    var description: String
    var createdAt: Date
    var isDefault: Bool

    init(name: String, encryptionKeyHex: String? = nil, frequency: String? = nil, description: String = "", isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.encryptionKeyHex = encryptionKeyHex ?? ChannelManager.generateKeyHex()
        self.frequency = frequency
        self.description = description
        self.createdAt = Date()
        self.isDefault = isDefault
    }

    var displayFrequency: String { frequency ?? "Mesh" }
}

// MARK: - ChannelManager

@MainActor
final class ChannelManager: ObservableObject {
    static let shared = ChannelManager()

    @Published var channels: [Channel] = []
    @Published var selectedChannel: Channel?

    private let persistURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        persistURL = docs.appendingPathComponent("channels.json")
        loadChannels()
        if channels.isEmpty { setupDefaultChannels() }
        selectedChannel = channels.first { $0.isDefault } ?? channels.first
    }

    // MARK: - Default Channels

    private func setupDefaultChannels() {
        channels = [
            Channel(name: "Command",   frequency: "155.340", description: "C2 command net",    isDefault: true),
            Channel(name: "Logistics", frequency: "155.400", description: "Supply and support"),
            Channel(name: "Medical",   frequency: "155.280", description: "MEDEVAC and TCCC"),
            Channel(name: "Mesh",      frequency: nil,       description: "Meshtastic default net"),
        ]
        saveChannels()
    }

    // MARK: - CRUD

    func selectChannel(_ channel: Channel) {
        selectedChannel = channel
        AuditLogger.shared.log(.meshJoined, detail: "channel_selected:\(channel.name)")
    }

    func addChannel(name: String, frequency: String? = nil, description: String = "") {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newChannel = Channel(name: name, frequency: frequency, description: description)
        channels.append(newChannel)
        saveChannels()

        // Broadcast channel join beacon over mesh
        broadcastChannelJoin(newChannel)

        AuditLogger.shared.log(.meshJoined, detail: "channel_created:\(name)")
    }

    func removeChannel(_ channel: Channel) {
        guard !channel.isDefault else { return }  // Never delete default channels
        channels.removeAll { $0.id == channel.id }
        if selectedChannel?.id == channel.id { selectedChannel = channels.first { $0.isDefault } }
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
                "packet": Data() // EncryptionManager handles actual key packaging
            ]
        )
    }

    // MARK: - Key Generation

    static func generateKeyHex() -> String {
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

// MARK: - ChannelView

struct ChannelView: View {
    @ObservedObject private var manager = ChannelManager.shared
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newFreq = ""
    @State private var newDesc = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(manager.channels) { channel in
                    ChannelRow(channel: channel, isSelected: manager.selectedChannel?.id == channel.id)
                        .contentShape(Rectangle())
                        .onTapGesture { manager.selectChannel(channel) }
                        .swipeActions(edge: .trailing) {
                            if !channel.isDefault {
                                Button(role: .destructive) { manager.removeChannel(channel) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            Button { manager.rotateKey(for: channel) } label: {
                                Label("Rotate Key", systemImage: "key.fill")
                            }.tint(.orange)
                        }
                }
            }
            .navigationTitle("Channels")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NavigationStack {
                    Form {
                        Section("Channel Info") {
                            TextField("Name", text: $newName)
                            TextField("Frequency (optional)", text: $newFreq)
                            TextField("Description", text: $newDesc)
                        }
                        Section("Encryption") {
                            Text("AES-256 key will be auto-generated and distributed to mesh peers.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .navigationTitle("New Channel")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showAddSheet = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Create") {
                                manager.addChannel(name: newName, frequency: newFreq.isEmpty ? nil : newFreq, description: newDesc)
                                newName = ""; newFreq = ""; newDesc = ""
                                showAddSheet = false
                            }
                            .disabled(newName.isEmpty)
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - ChannelRow

private struct ChannelRow: View {
    let channel: Channel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                .foregroundColor(isSelected ? ZDDesign.cyanAccent : .secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(channel.name).font(.headline)
                    if channel.isDefault {
                        Text("DEFAULT").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                Text(channel.displayFrequency)
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
            }
        }
        .accessibilityLabel("\(channel.name) channel, frequency \(channel.displayFrequency)\(isSelected ? ", selected" : "")")
    }
}
