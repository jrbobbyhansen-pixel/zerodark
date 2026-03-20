import SwiftUI
import CryptoKit
import CoreLocation

/// CommsTabView handles mesh networking, TAK protocol, LoRa, and acoustic modulation
struct CommsTabView: View {
    @StateObject private var mesh = MeshService.shared
    @StateObject private var ptt = PTTController.shared
    @StateObject private var meshtastic = MeshtasticBridge.shared
    @StateObject private var hammer = HAMMERAcousticModem.shared
    @State private var messageText = ""
    @State private var showJoinSheet = false
    @State private var groupKey = ""
    @State private var hammerMessage = ""
    @State private var hammerLog: [String] = []
    @State private var locationManager = CLLocationManager()
    @StateObject private var haptic = HapticComms.shared
    @State private var showHapticPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Connection Status Bar
                    connectionStatusBanner

                    if mesh.isActive {
                        // Active Mesh UI
                        VStack(spacing: ZDDesign.spacing16) {
                            // PTT Button
                            pttButton

                            // Quick Actions
                            HStack(spacing: ZDDesign.spacing12) {
                                GroupActionButton(icon: "location.fill", title: "Share", action: {
                                    locationManager.requestWhenInUseAuthorization()
                                    if let location = locationManager.location?.coordinate {
                                        let mgrs = MGRSConverter.toMGRS(coordinate: location, precision: 4)
                                        let msg = "My position: \(mgrs) (\(String(format: "%.5f", location.latitude)), \(String(format: "%.5f", location.longitude)))"
                                        mesh.shareIntel(msg)
                                    }
                                })
                                GroupActionButton(icon: "doc.text.fill", title: "Intel", action: {
                                    mesh.shareIntel("Scan data from current location")
                                })
                                GroupActionButton(icon: "exclamationmark.triangle.fill", title: "SOS", color: ZDDesign.signalRed, action: {
                                    mesh.broadcastSOS()
                                })
                                GroupActionButton(icon: "hand.tap.fill", title: "Haptic", action: {
                                    showHapticPicker = true
                                })
                            }
                            .padding(.horizontal)

                            // Messages + Peers List
                            List {
                                Section("Mesh Network (\(mesh.peers.count) peers)") {
                                    ForEach(mesh.peers) { peer in
                                        MeshPeerRow(peer: peer)
                                    }
                                    if mesh.peers.isEmpty {
                                        HStack {
                                            ProgressView()
                                                .tint(ZDDesign.cyanAccent)
                                            Text("Scanning for peers...")
                                                .foregroundColor(ZDDesign.mediumGray)
                                        }
                                    }
                                }
                                .listRowBackground(ZDDesign.darkCard)

                                Section("Messages") {
                                    if mesh.messages.isEmpty {
                                        HStack {
                                            Image(systemName: "bubble.left.fill")
                                                .foregroundColor(ZDDesign.mediumGray)
                                            Text("No messages yet")
                                                .foregroundColor(ZDDesign.mediumGray)
                                        }
                                    } else {
                                        ForEach(mesh.messages) { msg in
                                            MeshMessageRow(message: msg)
                                        }
                                    }
                                }
                                .listRowBackground(ZDDesign.darkCard)

                                Section("Meshtastic LoRa Mesh") {
                                    HStack {
                                        Circle()
                                            .fill(meshtastic.isConnected ? ZDDesign.successGreen : (meshtastic.isScanning ? ZDDesign.safetyYellow : ZDDesign.signalRed))
                                            .frame(width: 10, height: 10)
                                        Text(meshtastic.isConnected ? "Connected: \(meshtastic.connectedDevice ?? "")" : (meshtastic.isScanning ? "Scanning..." : "Not connected"))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Button(meshtastic.isScanning ? "Stop" : "Scan") {
                                            meshtastic.isScanning ? meshtastic.stopScan() : meshtastic.startScan()
                                        }
                                        .font(.caption)
                                    }

                                    if !meshtastic.discoveredDevices.isEmpty {
                                        ForEach(meshtastic.discoveredDevices, id: \.identifier) { device in
                                            Button(device.name ?? device.identifier.uuidString) {
                                                meshtastic.connect(to: device)
                                            }
                                            .foregroundColor(ZDDesign.cyanAccent)
                                        }
                                    }

                                    if !meshtastic.meshNodes.isEmpty {
                                        Text("\(meshtastic.meshNodes.count) nodes on mesh")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        ForEach(meshtastic.meshNodes) { node in
                                            HStack {
                                                Text(node.shortName)
                                                    .bold()
                                                    .foregroundColor(.white)
                                                Spacer()
                                                if let bat = node.batteryLevel {
                                                    Text("\(bat)%").font(.caption).foregroundColor(.secondary)
                                                }
                                                if let snr = node.snr {
                                                    Text("SNR \(String(format: "%.1f", snr))").font(.caption).foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                }
                                .listRowBackground(ZDDesign.darkCard)

                                Section("Acoustic Modem (HAMMER)") {
                                    HStack {
                                        Image(systemName: hammer.isKeySet ? "lock.fill" : "lock.open")
                                            .foregroundColor(hammer.isKeySet ? ZDDesign.successGreen : ZDDesign.safetyYellow)
                                        Text(hammer.isKeySet ? "Session key active" : "No key — tap to generate")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Button("Generate New Session Key") {
                                        let key = SymmetricKey(size: .bits256)
                                        hammer.setSessionKey(key)
                                    }
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.cyanAccent)

                                    HStack(spacing: ZDDesign.spacing8) {
                                        TextField("Message to transmit acoustically", text: $hammerMessage)
                                            .textFieldStyle(.plain)
                                            .padding(ZDDesign.spacing8)
                                            .background(ZDDesign.darkCard)
                                            .cornerRadius(ZDDesign.radiusSmall)

                                        Button {
                                            guard !hammerMessage.isEmpty else { return }
                                            let msg = hammerMessage
                                            hammerMessage = ""
                                            Task {
                                                do {
                                                    try await hammer.transmit(message: msg)
                                                    hammerLog.append("TX [\(Date().formatted(date: .omitted, time: .shortened))]: \(msg)")
                                                } catch {
                                                    hammerLog.append("TX ERROR: \(error.localizedDescription)")
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(hammer.isKeySet && !hammerMessage.isEmpty ? ZDDesign.forestGreen : ZDDesign.mediumGray)
                                        }
                                        .disabled(!hammer.isKeySet || hammerMessage.isEmpty)
                                    }

                                    if !hammerLog.isEmpty {
                                        Divider()
                                        ForEach(hammerLog.suffix(5), id: \.self) { entry in
                                            Text(entry)
                                                .font(.caption.monospaced())
                                                .foregroundColor(entry.hasPrefix("TX") ? ZDDesign.cyanAccent : ZDDesign.safetyYellow)
                                        }
                                    }
                                }
                                .listRowBackground(ZDDesign.darkCard)
                            }
                            .scrollContentBackground(.hidden)
                            .listStyle(.insetGrouped)
                            .onAppear {
                                HAMMERAcousticModem.shared.startListening { message in
                                    hammerLog.append("RX [\(Date().formatted(date: .omitted, time: .shortened))]: \(message)")
                                }
                            }
                            .onDisappear {
                                HAMMERAcousticModem.shared.stopListening()
                            }

                            // Message Input
                            messageInputBar
                        }
                    } else {
                        // Join/Create Mesh UI
                        joinMeshView
                    }
                }
            }
            .navigationTitle("Comms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if mesh.isActive {
                        Button {
                            mesh.stop()
                        } label: {
                            Text("Leave")
                                .foregroundColor(ZDDesign.signalRed)
                        }
                    }
                }
            }
            .sheet(isPresented: $showHapticPicker) {
                HapticPickerSheet()
            }
        }
    }

    // MARK: - Subviews

    private var connectionStatusBanner: some View {
        VStack(spacing: 8) {
            // Mesh Status
            HStack {
                switch mesh.connectionStatus {
                case .disconnected:
                    Image(systemName: "wifi.slash")
                        .foregroundColor(ZDDesign.mediumGray)
                    Text("Mesh: Not Connected")
                        .foregroundColor(ZDDesign.mediumGray)
                case .scanning:
                    ProgressView()
                        .tint(ZDDesign.cyanAccent)
                    Text("Mesh: Scanning...")
                        .foregroundColor(ZDDesign.cyanAccent)
                case .connected(let count):
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(ZDDesign.successGreen)
                    Text("Mesh: \(count) peer\(count == 1 ? "" : "s")")
                        .foregroundColor(ZDDesign.successGreen)
                }
                Spacer()
                if mesh.isActive {
                    Image(systemName: "lock.fill")
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("AES-256")
                        .font(.caption)
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
        }
        .font(.caption)
        .padding()
        .background(ZDDesign.darkCard)
    }

    private var pttButton: some View {
        ZStack {
            VStack(spacing: ZDDesign.spacing8) {
                Image(systemName: ptt.isTransmitting ? "mic.fill" : "mic")
                    .font(.system(size: 40))
                    .foregroundColor(ptt.isTransmitting ? ZDDesign.signalRed : ZDDesign.forestGreen)
                Text(ptt.isTransmitting ? "TRANSMITTING" : "HOLD TO TALK")
                    .font(.caption.bold())
                    .foregroundColor(ptt.isTransmitting ? ZDDesign.signalRed : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ZDDesign.spacing24)
            .background(ptt.isTransmitting ? ZDDesign.signalRed.opacity(0.2) : ZDDesign.darkCard)
            .cornerRadius(ZDDesign.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: ZDDesign.radiusMedium)
                    .stroke(ptt.isTransmitting ? ZDDesign.signalRed : Color.clear, lineWidth: 2)
            )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !ptt.isTransmitting {
                        ptt.startTransmit()
                        let impact = UIImpactFeedbackGenerator(style: .heavy)
                        impact.impactOccurred()
                    }
                }
                .onEnded { _ in
                    ptt.stopTransmit()
                }
        )
        .padding(.horizontal)
    }

    private var messageInputBar: some View {
        HStack(spacing: ZDDesign.spacing12) {
            TextField("Message...", text: $messageText)
                .textFieldStyle(.plain)
                .padding(ZDDesign.spacing12)
                .background(ZDDesign.darkCard)
                .cornerRadius(ZDDesign.radiusMedium)
                .foregroundColor(.white)

            Button {
                guard !messageText.isEmpty else { return }
                mesh.sendText(messageText)
                messageText = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.isEmpty ? ZDDesign.mediumGray : ZDDesign.forestGreen)
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(ZDDesign.charcoal)
    }

    private var joinMeshView: some View {
        VStack(spacing: ZDDesign.spacing24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(ZDDesign.forestGreen)

            Text("Mesh Network")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Create or join an encrypted peer-to-peer network. All communication is AES-256-GCM encrypted.")
                .font(.subheadline)
                .foregroundColor(ZDDesign.mediumGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: ZDDesign.spacing16) {
                TextField("Group Key (passphrase)", text: $groupKey)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(ZDDesign.radiusMedium)
                    .foregroundColor(.white)

                Button {
                    guard !groupKey.isEmpty else { return }
                    mesh.start(groupKey: groupKey)
                } label: {
                    Text("Join / Create Network")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(groupKey.isEmpty ? ZDDesign.mediumGray : ZDDesign.forestGreen)
                        .cornerRadius(ZDDesign.radiusMedium)
                }
                .disabled(groupKey.isEmpty)
            }
            .padding(.horizontal, ZDDesign.spacing24)

            Spacer()
        }
    }
}

// MARK: - Components

struct GroupActionButton: View {
    let icon: String
    let title: String
    var color: Color = ZDDesign.forestGreen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(ZDDesign.darkCard)
            .cornerRadius(ZDDesign.radiusSmall)
        }
    }
}

// MARK: - Mesh Components

struct MeshPeerRow: View {
    let peer: ZDPeer

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading) {
                Text(peer.name)
                    .foregroundColor(.white)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Spacer()

            if peer.status == .sos {
                Text("SOS")
                    .font(.caption.bold())
                    .foregroundColor(ZDDesign.signalRed)
            }
        }
    }

    private var statusColor: Color {
        switch peer.status {
        case .online: return ZDDesign.successGreen
        case .away: return ZDDesign.safetyYellow
        case .sos: return ZDDesign.signalRed
        case .offline: return ZDDesign.mediumGray
        }
    }

    private var statusText: String {
        switch peer.status {
        case .online: return "Online"
        case .away: return "Away"
        case .sos: return "EMERGENCY"
        case .offline: return "Offline"
        }
    }
}

struct MeshMessageRow: View {
    let message: MeshService.DecryptedMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.senderName)
                    .font(.caption.bold())
                    .foregroundColor(message.type == .sos ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                Spacer()
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
            }
            Text(message.content)
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Haptic Picker Sheet

struct HapticPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var haptic = HapticComms.shared
    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(TacticalHapticCode.allCases, id: \.self) { code in
                            Button {
                                haptic.send(code)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: code.icon)
                                        .font(.title)
                                        .foregroundColor(code == .danger ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                                    Text(code.displayName)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(ZDDesign.darkCard)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Send Haptic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CommsTabView()
}
