// OpsSharedViews.swift — Shared components for Ops tab sections
// Extracted from OpsTabView.swift for Deep Pack v7.0

import SwiftUI

// MARK: - Tool Button

struct ToolButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(ZDDesign.cyanAccent)
                Text(title)
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(ZDDesign.darkBackground)
            .cornerRadius(8)
        }
    }
}

// MARK: - Ops Section Card

struct OpsSectionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15))
                .cornerRadius(ZDDesign.radiusSmall)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ZDDesign.pureWhite)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
    }
}

// MARK: - Section Header

struct OpsSectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    init(icon: String, title: String, color: Color = ZDDesign.mediumGray) {
        self.icon = icon
        self.title = title
        self.color = color
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(ZDDesign.mediumGray)
        }
    }
}

// MARK: - Team Member Row

struct TeamMemberRow: View {
    let name: String
    let status: ZDPeer.PeerStatus
    var batteryLevel: Int? = nil
    var lastSeen: Date? = nil
    var isYou: Bool = false

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(name)
                .font(.subheadline)
                .foregroundColor(ZDDesign.pureWhite)

            if isYou {
                Text("(You)")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Spacer()

            if let battery = batteryLevel {
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon(battery))
                        .foregroundColor(batteryColor(battery))
                    Text("\(battery)%")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .padding(.vertical, 4)
    }

    var statusColor: Color {
        switch status {
        case .online: return ZDDesign.successGreen
        case .away: return ZDDesign.safetyYellow
        case .sos: return ZDDesign.signalRed
        case .offline: return ZDDesign.mediumGray
        }
    }

    func batteryIcon(_ level: Int) -> String {
        switch level {
        case 0..<20: return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<75: return "battery.50"
        case 75..<100: return "battery.75"
        default: return "battery.100"
        }
    }

    func batteryColor(_ level: Int) -> Color {
        if level < 20 { return ZDDesign.signalRed }
        if level < 50 { return ZDDesign.safetyYellow }
        return ZDDesign.successGreen
    }
}

// MARK: - Alert Model

struct OpsAlert: Identifiable {
    let id = UUID()
    let type: AlertType
    let message: String
    let timestamp: Date

    enum AlertType {
        case sos
        case danger
        case incident
    }

    var color: Color {
        switch type {
        case .sos: return ZDDesign.signalRed
        case .danger: return .orange
        case .incident: return ZDDesign.safetyYellow
        }
    }
}

// MARK: - JoinMeshSheet

struct JoinMeshSheet: View {
    @StateObject private var mesh = MeshService.shared
    @State private var groupKey = ""
    @State private var rememberNetwork = true
    @State private var editingNickname: ZDPeer?
    @State private var nicknameText = ""
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        statusSection
                        if !mesh.isActive {
                            joinSection
                        } else {
                            connectedSection
                        }
                        trustedDevicesSection
                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Mesh Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .alert("Set Nickname", isPresented: .init(
                get: { editingNickname != nil },
                set: { if !$0 { editingNickname = nil } }
            )) {
                TextField("Nickname", text: $nicknameText)
                Button("Save") {
                    if let peer = editingNickname {
                        mesh.trustPeer(peer, nickname: nicknameText)
                    }
                    editingNickname = nil
                }
                Button("Cancel", role: .cancel) {
                    editingNickname = nil
                }
            }
        }
    }

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(mesh.isActive ? ZDDesign.successGreen : ZDDesign.mediumGray)
                .frame(width: 12, height: 12)
            Text(statusText)
                .font(.headline)
                .foregroundColor(ZDDesign.pureWhite)
            Spacer()
            if mesh.isRemembered {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(ZDDesign.successGreen)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var statusText: String {
        switch mesh.connectionStatus {
        case .disconnected:
            return mesh.hasSavedNetwork ? "Saved Network Available" : "Not Connected"
        case .scanning:
            return "Scanning..."
        case .connected(let count):
            return "\(count) device\(count == 1 ? "" : "s") connected"
        }
    }

    private var joinSection: some View {
        VStack(spacing: 16) {
            if mesh.hasSavedNetwork {
                Button {
                    mesh.autoStart()
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Quick Connect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ZDDesign.cyanAccent)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
                Text("or enter a new network")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Group Passphrase")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                SecureField("Enter shared passphrase", text: $groupKey)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(8)
                    .foregroundColor(ZDDesign.pureWhite)
            }

            Toggle(isOn: $rememberNetwork) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("Remember this network")
                        .foregroundColor(ZDDesign.pureWhite)
                }
            }
            .tint(ZDDesign.cyanAccent)

            Button {
                guard !groupKey.isEmpty else { return }
                mesh.start(groupKey: groupKey)
                if rememberNetwork {
                    mesh.rememberNetwork(passphrase: groupKey)
                }
            } label: {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Join Network")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(groupKey.isEmpty ? ZDDesign.mediumGray : ZDDesign.forestGreen)
                .foregroundColor(ZDDesign.pureWhite)
                .cornerRadius(12)
            }
            .disabled(groupKey.isEmpty)
        }
        .padding()
        .background(ZDDesign.darkCard.opacity(0.5))
        .cornerRadius(16)
    }

    private var connectedSection: some View {
        VStack(spacing: 16) {
            if mesh.peers.isEmpty {
                Text("Waiting for peers...")
                    .foregroundColor(ZDDesign.mediumGray)
                    .italic()
            } else {
                ForEach(mesh.peers) { peer in
                    HStack {
                        Circle()
                            .fill(peer.status == .online ? ZDDesign.successGreen :
                                  peer.status == .sos ? ZDDesign.signalRed : ZDDesign.mediumGray)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mesh.displayName(for: peer))
                                .foregroundColor(ZDDesign.pureWhite)
                            Text(peer.name)
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }

                        Spacer()

                        if let battery = peer.batteryLevel {
                            HStack(spacing: 4) {
                                Image(systemName: batteryIcon(battery))
                                Text("\(battery)%")
                                    .font(.caption)
                            }
                            .foregroundColor(battery < 20 ? .red : ZDDesign.mediumGray)
                        }

                        Button {
                            nicknameText = mesh.displayName(for: peer)
                            editingNickname = peer
                        } label: {
                            Image(systemName: MeshKeychain.shared.isDeviceTrusted(id: peer.id) ? "star.fill" : "star")
                                .foregroundColor(ZDDesign.safetyYellow)
                        }
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(8)
                }
            }

            HStack(spacing: 12) {
                Button {
                    mesh.stop()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Disconnect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ZDDesign.signalRed.opacity(0.8))
                    .foregroundColor(ZDDesign.pureWhite)
                    .cornerRadius(12)
                }

                if mesh.isRemembered {
                    Button {
                        mesh.forgetNetwork()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Forget")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(ZDDesign.darkCard)
                        .foregroundColor(.red)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard.opacity(0.5))
        .cornerRadius(16)
    }

    private var trustedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trusted Devices")
                    .font(.headline)
                    .foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Text("\(mesh.trustedDevices.count)")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ZDDesign.darkCard)
                    .cornerRadius(8)
            }

            if mesh.trustedDevices.isEmpty {
                Text("Tap the star on a connected peer to trust them")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                    .italic()
            } else {
                ForEach(mesh.trustedDevices) { device in
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(ZDDesign.safetyYellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.nickname)
                                .foregroundColor(ZDDesign.pureWhite)
                            Text("Last seen: \(device.lastSeen.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        Spacer()
                        Button {
                            mesh.untrustPeer(id: device.id)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard.opacity(0.3))
        .cornerRadius(16)
        .onAppear {
            mesh.loadTrustedDevices()
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
}

// MARK: - SARToolsSheet

struct SARToolsSheet: View {
    @Environment(\.dismiss) var dismiss: DismissAction
    @StateObject private var mesh = MeshService.shared
    @StateObject private var activity = ActivityFeed.shared
    @State private var selectedType: String = "expandingSquare"
    @State private var trackSpacing: Double = 50

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SEARCH PATTERN")
                                .font(.caption).fontWeight(.bold).foregroundColor(ZDDesign.mediumGray)
                            Picker("Pattern", selection: $selectedType) {
                                Text("Expanding Square").tag("expandingSquare")
                                Text("Creeping Line").tag("creepingLine")
                                Text("Sector Sweep").tag("sectorSweep")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding().background(ZDDesign.darkCard).cornerRadius(12)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("PARAMETERS")
                                .font(.caption).fontWeight(.bold).foregroundColor(ZDDesign.mediumGray)
                            VStack(alignment: .leading) {
                                Text("Track Spacing: \(Int(trackSpacing))m")
                                    .foregroundColor(ZDDesign.pureWhite)
                                Slider(value: $trackSpacing, in: 10...200, step: 10)
                                    .tint(ZDDesign.cyanAccent)
                            }
                        }
                        .padding().background(ZDDesign.darkCard).cornerRadius(12)

                        Button {
                            let msg = "SAR PATTERN: \(selectedType) | Track Spacing: \(Int(trackSpacing))m"
                            mesh.shareIntel(msg)
                            activity.log(.patternGenerated, message: msg)
                            dismiss()
                        } label: {
                            Text("Broadcast to Team")
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(ZDDesign.cyanAccent)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("SAR Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - URL Identifiable conformance

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
