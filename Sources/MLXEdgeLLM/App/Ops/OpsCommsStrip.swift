// OpsCommsStrip.swift — Persistent comms header for Ops tab
// Always visible: mesh status, PTT, SOS, alerts, expandable detail

import SwiftUI

struct OpsCommsStrip: View {
    @ObservedObject private var mesh = MeshService.shared
    @ObservedObject private var ptt = PTTController.shared
    @ObservedObject private var haptic = HapticComms.shared
    @ObservedObject private var hapticPTT = HapticPTTController.shared
    @ObservedObject private var activity = ActivityFeed.shared
    @ObservedObject private var dtnBuffer = DTNBuffer.shared
    @ObservedObject private var relay = MeshRelay.shared

    @State private var isExpanded = false
    @State private var showJoinSheet = false
    @State private var showHapticPicker = false
    @State private var showMessageQueue = false
    @State private var showChannelManager = false
    @State private var messageText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Compact bar — always visible
            compactBar

            // Expanded detail
            if isExpanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(ZDDesign.darkCard)
        .cornerRadius(ZDDesign.radiusMedium)
        .animation(.spring(response: 0.3), value: isExpanded)
        .sheet(isPresented: $showJoinSheet) {
            JoinMeshSheet()
        }
        .sheet(isPresented: $showHapticPicker) {
            HapticPickerSheet()
        }
        .sheet(isPresented: $showMessageQueue) {
            MessageQueueView()
        }
        .sheet(isPresented: $showChannelManager) {
            ChannelManagerView()
        }
    }

    // MARK: - Compact Bar

    private var compactBar: some View {
        HStack(spacing: 12) {
            // Connection status
            Button {
                if mesh.isActive {
                    withAnimation { isExpanded.toggle() }
                } else {
                    showJoinSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mesh.isActive ? ZDDesign.successGreen : ZDDesign.signalRed)
                        .frame(width: 10, height: 10)

                    if mesh.isActive {
                        Text("\(mesh.peers.count)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(ZDDesign.pureWhite)
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundColor(ZDDesign.mediumGray)
                    } else {
                        Text("Join")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }

            Spacer()

            if mesh.isActive {
                // Share location
                Button {
                    shareLocation()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(ZDDesign.cyanAccent)
                        .frame(width: 32, height: 32)
                        .background(ZDDesign.darkBackground)
                        .cornerRadius(8)
                }

                // Comms mode toggle (PTT/Haptic/Silent)
                Button {
                    hapticPTT.cycleMode()
                } label: {
                    Image(systemName: hapticPTT.mode.icon)
                        .font(.caption)
                        .foregroundColor(commsModeTint)
                        .frame(width: 32, height: 32)
                        .background(ZDDesign.darkBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(commsModeTint.opacity(0.5), lineWidth: 1)
                        )
                }

                // Context-aware comms button
                if hapticPTT.mode == .ptt {
                    // PTT press-and-hold
                    Button {} label: {
                        Image(systemName: ptt.isTransmitting ? "mic.fill" : "mic")
                            .font(.caption)
                            .foregroundColor(ptt.isTransmitting ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                            .frame(width: 32, height: 32)
                            .background(ptt.isTransmitting ? ZDDesign.signalRed.opacity(0.3) : ZDDesign.darkBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(ptt.isTransmitting ? ZDDesign.signalRed : Color.clear, lineWidth: 1)
                            )
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !ptt.isTransmitting { hapticPTT.startTransmit() }
                            }
                            .onEnded { _ in hapticPTT.stopTransmit() }
                    )
                } else if hapticPTT.mode == .haptic {
                    // Haptic picker
                    Button {
                        showHapticPicker = true
                    } label: {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption)
                            .foregroundColor(ZDDesign.cyanAccent)
                            .frame(width: 32, height: 32)
                            .background(ZDDesign.darkBackground)
                            .cornerRadius(8)
                    }
                }

                // SOS
                Button {
                    mesh.broadcastSOS()
                } label: {
                    Text("SOS")
                        .font(.caption2)
                        .fontWeight(.black)
                        .foregroundColor(ZDDesign.pureWhite)
                        .frame(width: 32, height: 32)
                        .background(ZDDesign.signalRed)
                        .cornerRadius(8)
                }
            }

            // Alert badge
            if alertCount > 0 {
                ZStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(ZDDesign.signalRed)
                    Text("\(alertCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ZDDesign.pureWhite)
                        .padding(3)
                        .background(ZDDesign.signalRed)
                        .clipShape(Circle())
                        .offset(x: 8, y: -8)
                }
            }

            // Expand chevron
            if mesh.isActive {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Expanded Detail

    private var expandedDetail: some View {
        VStack(spacing: 12) {
            Divider().background(ZDDesign.mediumGray.opacity(0.3))

            // PTT receiving indicator
            if ptt.isReceiving, let speaker = ptt.activeSpeaker {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(ZDDesign.successGreen)
                    Text("Receiving from \(speaker)")
                        .font(.caption)
                        .foregroundColor(ZDDesign.successGreen)
                }
            }

            // Alerts
            if !alerts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(alerts) { alert in
                        HStack {
                            Circle().fill(alert.color).frame(width: 6, height: 6)
                            Text(alert.message)
                                .font(.caption)
                                .foregroundColor(ZDDesign.pureWhite)
                            Spacer()
                            Text(alert.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                }
            }

            // Quick Channel Switch
            HStack {
                Text("CHANNEL")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Spacer()
                Button {
                    showChannelManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2).foregroundColor(ZDDesign.cyanAccent)
                }
            }
            QuickChannelSwitcher()

            // DTN Buffer
            HStack {
                Label("\(dtnBuffer.pendingCount) Pending", systemImage: "tray.full.fill")
                    .font(.caption)
                    .foregroundColor(dtnBuffer.pendingCount > 0 ? ZDDesign.safetyYellow : ZDDesign.mediumGray)
                Spacer()
                Label("\(dtnBuffer.deliveredCount) Delivered", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(ZDDesign.successGreen)
                Button {
                    showMessageQueue = true
                } label: {
                    Text("Queue")
                        .font(.caption2.bold())
                        .foregroundColor(ZDDesign.cyanAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(ZDDesign.cyanAccent.opacity(0.15))
                        .cornerRadius(6)
                }
            }

            // Recent activity
            if !activity.items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ZDDesign.mediumGray)
                    ForEach(activity.items.prefix(3)) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .font(.system(size: 10))
                                .foregroundColor(item.color)
                                .frame(width: 14)
                            Text(item.message)
                                .font(.caption2)
                                .foregroundColor(ZDDesign.pureWhite)
                                .lineLimit(1)
                            Spacer()
                            Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                }
            }

            // Messages
            if !mesh.messages.isEmpty {
                Divider().background(ZDDesign.mediumGray.opacity(0.3))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(mesh.messages.suffix(3).reversed()) { msg in
                        HStack(alignment: .top) {
                            Text(msg.senderName)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(ZDDesign.cyanAccent)
                            Text(msg.content)
                                .font(.caption2)
                                .foregroundColor(ZDDesign.pureWhite)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }

                // Message input
                HStack {
                    TextField("Message...", text: $messageText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .padding(8)
                        .background(ZDDesign.darkBackground)
                        .cornerRadius(8)
                        .foregroundColor(ZDDesign.pureWhite)

                    Button {
                        if !messageText.isEmpty {
                            mesh.sendText(messageText)
                            messageText = ""
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(messageText.isEmpty ? ZDDesign.mediumGray : ZDDesign.cyanAccent)
                    }
                    .disabled(messageText.isEmpty)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Computed

    private var commsModeTint: Color {
        switch hapticPTT.mode {
        case .ptt: return ZDDesign.cyanAccent
        case .haptic: return ZDDesign.safetyYellow
        case .silent: return ZDDesign.mediumGray
        }
    }

    private var alerts: [OpsAlert] {
        var result: [OpsAlert] = []
        if mesh.sosActive {
            result.append(OpsAlert(type: .sos, message: "SOS received", timestamp: Date()))
        }
        if let code = haptic.lastReceivedCode, code == .danger {
            result.append(OpsAlert(type: .danger, message: "DANGER from \(haptic.lastSender ?? "Unknown")", timestamp: Date()))
        }
        return result
    }

    private var alertCount: Int { alerts.count }

    private func shareLocation() {
        guard let location = LocationManager.shared.currentLocation else { return }
        let mgrs = MGRSConverter.toMGRS(coordinate: location, precision: 4)
        mesh.shareLocation(location)
        activity.log(.locationShared, message: "Location shared: \(mgrs)")
    }
}
