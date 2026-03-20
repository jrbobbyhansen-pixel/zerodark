// OpsTabView.swift — Unified Operations & Command Center
// Merges comms, team status, reports, weather, and tactical tools

import SwiftUI
import CoreLocation

struct OpsTabView: View {
    // MARK: - State Objects
    @StateObject private var mesh = MeshService.shared
    @StateObject private var ptt = PTTController.shared
    @StateObject private var haptic = HapticComms.shared
    @StateObject private var activity = ActivityFeed.shared
    @StateObject private var weather = WeatherService.shared
    @StateObject private var incidents = IncidentStore.shared
    @StateObject private var safetyMonitor = RuntimeSafetyMonitor.shared
    @StateObject private var dtnBuffer = DTNBuffer.shared

    // MARK: - State
    @State private var messageText = ""
    @State private var showJoinSheet = false
    @State private var showHapticPicker = false
    @State private var showReportPicker = false
    @State private var selectedReport: ReportType?
    @State private var showSARTools = false
    @State private var showTacticalScanner = false
    @State private var showTacticalNavigation = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: ZDDesign.spacing16) {
                        // Connection Status
                        connectionStatusCard

                        // PTT + Quick Actions
                        if mesh.isActive {
                            pttSection
                            quickActionsSection
                        } else {
                            joinMeshCard
                        }

                        // Alerts (if any)
                        if !alerts.isEmpty {
                            alertsSection
                        }

                        // Team Status
                        teamStatusSection

                        // Conditions (Weather + Sun)
                        conditionsSection

                        // Activity Feed
                        activityFeedSection

                        // Tools
                        toolsSection

                        // Safety Monitor
                        safetyMonitorSection
                            .padding(.bottom, 8)

                        // DTN Buffer
                        dtnBufferSection
                            .padding(.bottom, 8)

                        // Messages
                        if mesh.isActive {
                            messagesSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Operations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Incident", systemImage: "plus.circle") {
                            // Create incident
                        }
                        Button("Export Logs", systemImage: "square.and.arrow.up") {
                            exportURL = activity.exportLogs()
                        }
                        Divider()
                        if mesh.isActive {
                            Button("Leave Mesh", systemImage: "xmark.circle", role: .destructive) {
                                mesh.stop()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinMeshSheet()
            }
            .sheet(isPresented: $showHapticPicker) {
                HapticPickerSheet()
            }
            .sheet(isPresented: $showReportPicker) {
                ReportPickerSheet(selectedReport: $selectedReport)
            }
            .sheet(item: $selectedReport) { report in
                ReportFormView(reportType: report)
            }
            .sheet(isPresented: $showSARTools) {
                SARToolsSheet()
            }
            .sheet(isPresented: $showTacticalScanner) {
                TacticalScannerView()
            }
            .sheet(isPresented: $showTacticalNavigation) {
                TacticalNavigationView()
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Computed Properties

    var alerts: [OpsAlert] {
        var result: [OpsAlert] = []

        // SOS alerts from mesh
        if mesh.sosActive {
            result.append(OpsAlert(type: .sos, message: "SOS received from team member", timestamp: Date()))
        }

        // Incoming haptic alerts
        if let code = haptic.lastReceivedCode, code == .danger {
            result.append(OpsAlert(type: .danger, message: "DANGER signal from \(haptic.lastSender ?? "Unknown")", timestamp: Date()))
        }

        // Active incidents
        for incident in incidents.incidents.filter({ $0.status == .active && $0.priority == .critical }) {
            result.append(OpsAlert(type: .incident, message: incident.title, timestamp: incident.timestamp))
        }

        return result
    }

    // MARK: - View Components

    var connectionStatusCard: some View {
        HStack {
            Circle()
                .fill(mesh.isActive ? ZDDesign.successGreen : ZDDesign.signalRed)
                .frame(width: 12, height: 12)

            Text(mesh.isActive ? "Mesh Active" : "Mesh Offline")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            if mesh.isActive {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("\(mesh.peers.count)")
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var joinMeshCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(ZDDesign.mediumGray)

            Text("Join a mesh network to communicate with your team")
                .multilineTextAlignment(.center)
                .foregroundColor(ZDDesign.mediumGray)

            Button {
                showJoinSheet = true
            } label: {
                Text("Join Mesh Network")
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ZDDesign.cyanAccent)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var pttSection: some View {
        VStack(spacing: 12) {
            // PTT Button
            Button {
                // Handled by gesture
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: ptt.isTransmitting ? "mic.fill" : "mic")
                        .font(.system(size: 36))
                        .foregroundColor(ptt.isTransmitting ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                    Text(ptt.isTransmitting ? "TRANSMITTING" : "PUSH TO TALK")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(width: 100, height: 100)
                .background(
                    Circle()
                        .fill(ptt.isTransmitting ? ZDDesign.signalRed.opacity(0.3) : ZDDesign.darkCard)
                )
                .overlay(
                    Circle()
                        .stroke(ptt.isTransmitting ? ZDDesign.signalRed : ZDDesign.cyanAccent, lineWidth: 3)
                )
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !ptt.isTransmitting {
                            ptt.startTransmit()
                        }
                    }
                    .onEnded { _ in
                        ptt.stopTransmit()
                    }
            )

            // Receiving indicator
            if ptt.isReceiving, let speaker = ptt.activeSpeaker {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(ZDDesign.successGreen)
                    Text("Receiving from \(speaker)")
                        .font(.caption)
                        .foregroundColor(ZDDesign.successGreen)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK ACTIONS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(ZDDesign.mediumGray)

            HStack(spacing: 12) {
                OpsQuickActionButton(icon: "location.fill", title: "Share Loc", color: ZDDesign.cyanAccent) {
                    shareLocation()
                }

                OpsQuickActionButton(icon: "hand.tap.fill", title: "Haptic", color: ZDDesign.cyanAccent) {
                    showHapticPicker = true
                }

                OpsQuickActionButton(icon: "doc.text.fill", title: "Report", color: ZDDesign.safetyYellow) {
                    showReportPicker = true
                }

                OpsQuickActionButton(icon: "exclamationmark.triangle.fill", title: "SOS", color: ZDDesign.signalRed) {
                    mesh.broadcastSOS()
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var alertsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(ZDDesign.signalRed)
                Text("ALERTS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.signalRed)
            }

            ForEach(alerts) { alert in
                HStack {
                    Circle()
                        .fill(alert.color)
                        .frame(width: 8, height: 8)
                    Text(alert.message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(alert.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .padding()
        .background(ZDDesign.signalRed.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ZDDesign.signalRed, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    var teamStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("TEAM STATUS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            // Self
            TeamMemberRow(
                name: "You",
                status: .online,
                batteryLevel: getBatteryLevel(),
                isYou: true
            )

            // Peers
            if mesh.peers.isEmpty {
                Text("No other team members connected")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                    .padding(.vertical, 8)
            } else {
                ForEach(mesh.peers) { peer in
                    TeamMemberRow(
                        name: peer.name,
                        status: peer.status,
                        batteryLevel: peer.batteryLevel,
                        lastSeen: peer.lastSeen
                    )
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cloud.sun.fill")
                    .foregroundColor(ZDDesign.safetyYellow)
                Text("CONDITIONS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            if let conditions = weather.currentConditions {
                HStack(spacing: 20) {
                    // Temperature
                    VStack {
                        Text("\(conditions.temperature)°F")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text(conditions.description)
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }

                    Divider()
                        .frame(height: 40)
                        .background(ZDDesign.mediumGray)

                    // Wind
                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "wind")
                                .foregroundColor(ZDDesign.cyanAccent)
                            Text("\(conditions.windSpeed) mph")
                                .foregroundColor(.white)
                        }
                        Text(conditions.windDirection)
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }

                    Divider()
                        .frame(height: 40)
                        .background(ZDDesign.mediumGray)

                    // Sun times
                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "sunset.fill")
                                .foregroundColor(.orange)
                            Text(conditions.sunset.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.white)
                        }
                        Text("Sunset")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
            } else {
                HStack {
                    ProgressView()
                        .tint(ZDDesign.cyanAccent)
                    Text("Loading conditions...")
                        .foregroundColor(ZDDesign.mediumGray)
                }
                .onAppear {
                    weather.fetchConditions()
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("RECENT ACTIVITY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.mediumGray)
                Spacer()
                if !activity.items.isEmpty {
                    Text("\(activity.items.count)")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }

            if activity.items.isEmpty {
                Text("No recent activity")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                    .padding(.vertical, 8)
            } else {
                ForEach(activity.items.prefix(5)) { item in
                    HStack {
                        Image(systemName: item.icon)
                            .foregroundColor(item.color)
                            .frame(width: 20)
                        Text(item.message)
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                        Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("TOOLS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ToolButton(icon: "magnifyingglass", title: "SAR Patterns") {
                    showSARTools = true
                }

                ToolButton(icon: "cross.fill", title: "9-Line MEDEVAC") {
                    selectedReport = .medevac
                }

                ToolButton(icon: "eye.fill", title: "SALUTE Report") {
                    selectedReport = .salute
                }

                ToolButton(icon: "doc.plaintext", title: "SITREP") {
                    selectedReport = .sitrep
                }

                ToolButton(icon: "qrcode.viewfinder", title: "Scanner") {
                    showTacticalScanner = true
                }

                ToolButton(icon: "arrow.triangle.turn.up.right.circle", title: "Navigation") {
                    showTacticalNavigation = true
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    var safetyMonitorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SAFETY STATUS")
                    .font(.caption).foregroundColor(ZDDesign.mediumGray).textCase(.uppercase)
                Spacer()
                Circle()
                    .fill(safetyMonitor.unresolvedViolations.isEmpty ? ZDDesign.successGreen : ZDDesign.signalRed)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if safetyMonitor.unresolvedViolations.isEmpty {
                HStack {
                    Image(systemName: "checkmark.shield.fill").foregroundColor(ZDDesign.successGreen)
                    Text("All systems nominal").foregroundColor(ZDDesign.mediumGray).font(.subheadline)
                }
                .padding()
            } else {
                ForEach(safetyMonitor.unresolvedViolations.prefix(3)) { violation in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(violation.severity >= 2 ? ZDDesign.signalRed : ZDDesign.safetyYellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(violation.property).font(.subheadline).foregroundColor(.white)
                            Text(violation.details).font(.caption).foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            }
        }
        .background(ZDDesign.darkBackground)
    }

    var dtnBufferSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MESSAGE QUEUE")
                .font(.caption).foregroundColor(ZDDesign.mediumGray).textCase(.uppercase)
                .padding(.horizontal)
                .padding(.top, 8)

            HStack {
                Label("\(dtnBuffer.pendingCount) Pending", systemImage: "tray.full.fill")
                    .foregroundColor(dtnBuffer.pendingCount > 0 ? ZDDesign.safetyYellow : ZDDesign.mediumGray)
                Spacer()
                Label("\(dtnBuffer.deliveredCount) Delivered", systemImage: "checkmark.circle.fill")
                    .foregroundColor(ZDDesign.successGreen)
            }
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(8)
            .padding(.horizontal)
        }
        .background(ZDDesign.darkBackground)
    }

    var messagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("MESSAGES")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            if mesh.messages.isEmpty {
                Text("No messages yet")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
                    .padding(.vertical, 8)
            } else {
                ForEach(mesh.messages.suffix(5).reversed()) { msg in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(msg.senderName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(ZDDesign.cyanAccent)
                            Spacer()
                            Text(msg.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        Text(msg.content)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Message input
            HStack {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(ZDDesign.darkBackground)
                    .cornerRadius(8)
                    .foregroundColor(.white)

                Button {
                    if !messageText.isEmpty {
                        mesh.sendText(messageText)
                        messageText = ""
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? ZDDesign.mediumGray : ZDDesign.cyanAccent)
                }
                .disabled(messageText.isEmpty)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Actions

    func shareLocation() {
        guard let location = LocationManager.shared.currentLocation else { return }
        let mgrs = MGRSConverter.toMGRS(coordinate: location, precision: 4)
        mesh.shareLocation(location)
        activity.log(.locationShared, message: "Location shared: \(mgrs)")
    }

    func getBatteryLevel() -> Int {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int(UIDevice.current.batteryLevel * 100)
        #else
        return 100
        #endif
    }
}

// MARK: - Supporting Views

struct OpsQuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(ZDDesign.darkBackground)
            .cornerRadius(8)
        }
    }
}

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
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(ZDDesign.darkBackground)
            .cornerRadius(8)
        }
    }
}

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
                .foregroundColor(.white)

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
    @State private var showTrustedDevices = false
    @State private var editingNickname: ZDPeer?
    @State private var nicknameText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Status indicator
                        statusSection

                        if !mesh.isActive {
                            // Join section
                            joinSection
                        } else {
                            // Connected section
                            connectedSection
                        }

                        // Trusted devices
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

    // MARK: - Sections

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(mesh.isActive ? ZDDesign.successGreen : ZDDesign.mediumGray)
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.headline)
                .foregroundColor(.white)

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
            // Quick connect if saved
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

            // Manual entry
            VStack(alignment: .leading, spacing: 8) {
                Text("Group Passphrase")
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)

                SecureField("Enter shared passphrase", text: $groupKey)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }

            // Remember toggle
            Toggle(isOn: $rememberNetwork) {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("Remember this network")
                        .foregroundColor(.white)
                }
            }
            .tint(ZDDesign.cyanAccent)

            // Join button
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
                .foregroundColor(.white)
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
            // Online peers
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
                                .foregroundColor(.white)
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

                        // Trust/nickname button
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

            // Disconnect button
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
                    .foregroundColor(.white)
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
                    .foregroundColor(.white)

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
                Text("Tap the ⭐ on a connected peer to trust them")
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
                                .foregroundColor(.white)
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
    @Environment(\.dismiss) var dismiss
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
                        // Pattern picker
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

                        // Parameters
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PARAMETERS")
                                .font(.caption).fontWeight(.bold).foregroundColor(ZDDesign.mediumGray)
                            VStack(alignment: .leading) {
                                Text("Track Spacing: \(Int(trackSpacing))m")
                                    .foregroundColor(.white)
                                Slider(value: $trackSpacing, in: 10...200, step: 10)
                                    .tint(ZDDesign.cyanAccent)
                            }
                        }
                        .padding().background(ZDDesign.darkCard).cornerRadius(12)

                        // Share pattern
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

// MARK: - ReportPickerSheet

struct ReportPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedReport: ReportType?

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                VStack(spacing: 16) {
                    ForEach(ReportType.allCases) { type in
                        Button {
                            selectedReport = type
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: type.icon)
                                    .font(.title2)
                                    .foregroundColor(ZDDesign.cyanAccent)
                                    .frame(width: 40)

                                Text(type.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                            .padding()
                            .background(ZDDesign.darkCard)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

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
