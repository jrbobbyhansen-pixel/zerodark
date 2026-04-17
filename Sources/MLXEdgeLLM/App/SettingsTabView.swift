// SettingsTabView.swift — App Settings + TAK/AI Configuration
// Credentials stored in Keychain (not @State/UserDefaults)
// Form validation enforced before connect attempts

import SwiftUI

struct SettingsTabView: View {
    // Identity
    @State private var callsign: String = ZDKeychain.load(key: ZDKeychain.Keys.callsign) ?? AppConfig.deviceCallsign
    @State private var isEditingCallsign = false

    // TAK — loaded from Keychain on appear
    @State private var takHost    = ""
    @State private var takPort    = "\(AppConfig.defaultTAKPort)"
    @State private var takTLSPort = "\(AppConfig.defaultTAKTLSPort)"
    @State private var takHostValid = true
    @State private var takPortValid = true

    @ObservedObject private var takConnector = FreeTAKConnector.shared
    @ObservedObject private var engine       = LocalInferenceEngine.shared
    @ObservedObject private var modelMgr     = ModelManager.shared

    @State private var toast: ToastMessage? = nil
    @State private var showAuditLog = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Identity
                Section("Identity") {
                    if isEditingCallsign {
                        HStack {
                            TextField("Callsign", text: $callsign)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                            Button("Save") {
                                AppConfig.deviceCallsign = callsign
                                ZDKeychain.save(callsign, key: ZDKeychain.Keys.callsign)
                                isEditingCallsign = false
                                showToast("Callsign saved", symbol: "checkmark.circle.fill", color: .green)
                                AuditLogger.shared.log(.credentialUpdated, detail: "callsign updated")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ZDDesign.cyanAccent)
                        }
                    } else {
                        HStack {
                            LabeledContent("Callsign", value: callsign)
                                .font(.subheadline)
                            Spacer()
                            Button("Edit") { isEditingCallsign = true }
                                .font(.caption)
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }

                // MARK: TAK Server
                Section("TAK Server") {
                    ValidatedTextField("Host / IP", text: $takHost, isValid: $takHostValid) {
                        isValidHost($0)
                    }
                    ValidatedTextField("TCP Port", text: $takPort, isValid: $takPortValid) {
                        isValidPort($0)
                    }
                    .keyboardType(.numberPad)
                    ValidatedTextField("TLS Port", text: $takTLSPort, isValid: .constant(true)) {
                        isValidPort($0)
                    }
                    .keyboardType(.numberPad)

                    if takConnector.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(ZDDesign.successGreen)
                            .accessibilityLabel("TAK server connected")
                    } else if let error = takConnector.lastError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundColor(ZDDesign.signalRed)
                            .font(.caption)
                    }

                    VStack(spacing: 8) {
                        Button("Connect (TCP)") {
                            saveTAKCredentials()
                            if let port = UInt16(takPort) {
                                takConnector.connect(host: takHost, port: port)
                                AuditLogger.shared.log(.peerConnected, detail: "TAK TCP \(takHost):\(port)")
                            }
                        }
                        .disabled(!canConnect)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("Connect to TAK server over TCP")

                        Button("Connect (TLS)") {
                            saveTAKCredentials()
                            if let port = UInt16(takTLSPort) {
                                takConnector.connectTLS(host: takHost, port: port)
                                AuditLogger.shared.log(.peerConnected, detail: "TAK TLS \(takHost):\(port)")
                            }
                        }
                        .disabled(!canConnect)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("Connect to TAK server over TLS (encrypted)")

                        if takConnector.isConnected {
                            Button("Disconnect", role: .destructive) {
                                takConnector.disconnect()
                                AuditLogger.shared.log(.peerDisconnected, detail: "TAK disconnect")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Text("Host must be an IP or hostname. Ports 1–65535.")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                }

                // MARK: Local AI Model
                Section("Local AI Model") {
                    switch engine.modelState {
                    case .notLoaded:
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(ZDDesign.signalRed)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Model Not Downloaded")
                                    .font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                                Text("Phi-3.5-mini (2.2 GB) — powers fully offline AI answers. Download over WiFi once.")
                                    .font(.caption2).foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                        Button {
                            Task { await LocalInferenceEngine.shared.loadModel() }
                        } label: {
                            Label("Download Model", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ZDDesign.cyanAccent)

                    case .loading:
                        HStack {
                            ProgressView().tint(ZDDesign.safetyYellow)
                            Text("Loading model…").font(.caption).foregroundColor(ZDDesign.mediumGray)
                        }
                        ProgressView(value: engine.loadProgress).tint(ZDDesign.safetyYellow)

                    case .ready:
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ZDDesign.successGreen)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phi-3.5-mini — On Device")
                                    .font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                                Text("\(modelMgr.installedModelSize) • A18 Pro • CPU/NEON")
                                    .font(.caption2).foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                        Button { engine.unloadModel() } label: {
                            Label("Unload Model", systemImage: "trash.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(ZDDesign.signalRed)

                    case .error(let msg):
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(ZDDesign.signalRed).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Model Error").font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                                Text(msg).font(.caption2).foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                        Button { Task { await engine.loadModel() } } label: {
                            Label("Retry", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // MARK: Remote AI Servers
                Section("Remote AI Servers") {
                    Text("Used when on-device model is unavailable or for vision tasks.")
                        .font(.caption2).foregroundColor(ZDDesign.mediumGray)

                    serverRow(label: "Text (Phi-3.5)", client: TextInferenceClient.shared) {
                        TextField("Text Server URL", text: Binding(
                            get: { TextInferenceClient.shared.serverURL },
                            set: { TextInferenceClient.shared.serverURL = $0 }
                        )).keyboardType(.URL).autocapitalization(.none)
                        Button("Test") { Task { await TextInferenceClient.shared.checkConnection() } }
                    }

                    Divider()

                    serverRow(label: "Vision (moondream2)", client: VisionInferenceClient.shared) {
                        TextField("Vision Server URL", text: Binding(
                            get: { VisionInferenceClient.shared.serverURL },
                            set: { VisionInferenceClient.shared.serverURL = $0 }
                        )).keyboardType(.URL).autocapitalization(.none)
                        Button("Test") { Task { await VisionInferenceClient.shared.checkConnection() } }
                    }

                    Text("Mac server scripts: ~/Desktop/start-bitnet-server.sh")
                        .font(.caption2).foregroundColor(ZDDesign.mediumGray)
                }

                // MARK: Maps
                Section("Maps") {
                    NavigationLink("Offline Maps") { TileDownloadView() }
                }

                // MARK: Security
                Section("Security") {
                    Button("Export Audit Log") {
                        AuditLogger.shared.log(.logsExported, detail: "audit CSV export")
                        if let url = AuditLogger.shared.exportCSVToFile() {
                            shareURL = url
                        }
                    }
                    .foregroundColor(ZDDesign.cyanAccent)
                    NavigationLink("View Audit Log") { AuditLogView() }
                }

                // MARK: Device Info
                Section("Device Info") {
                    LabeledContent("Device", value: UIDevice.current.name)
                    LabeledContent("OS", value: UIDevice.current.systemVersion)
                    LabeledContent("Model", value: UIDevice.current.modelName)
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "government-ready")
                }
            }
            .navigationTitle("Settings")
            .onAppear { loadTAKCredentials() }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation(.easeOut(duration: 0.3)) { self.toast = nil }
                            }
                        }
                        .padding(.bottom, 20)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: toast?.id)
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Helpers

    private var canConnect: Bool {
        !takHost.isEmpty && takHostValid && takPortValid
    }

    private func isValidHost(_ host: String) -> Bool {
        !host.isEmpty && host.count <= 253
    }

    private func isValidPort(_ port: String) -> Bool {
        guard let p = Int(port) else { return false }
        return p >= 1 && p <= 65535
    }

    private func saveTAKCredentials() {
        ZDKeychain.save(takHost, key: ZDKeychain.Keys.takHost)
        ZDKeychain.save(takPort, key: ZDKeychain.Keys.takPort)
        ZDKeychain.save(takTLSPort, key: ZDKeychain.Keys.takTLSPort)
        AuditLogger.shared.log(.credentialUpdated, detail: "TAK credentials saved to Keychain")
    }

    private func loadTAKCredentials() {
        takHost    = ZDKeychain.load(key: ZDKeychain.Keys.takHost) ?? ""
        takPort    = ZDKeychain.load(key: ZDKeychain.Keys.takPort) ?? "\(AppConfig.defaultTAKPort)"
        takTLSPort = ZDKeychain.load(key: ZDKeychain.Keys.takTLSPort) ?? "\(AppConfig.defaultTAKTLSPort)"
    }

    private func showToast(_ message: String, symbol: String, color: Color) {
        withAnimation(.spring()) {
            toast = ToastMessage(message: message, symbol: symbol, color: color)
        }
    }

    @ViewBuilder
    private func serverRow<Content: View>(label: String, client: some AnyObject, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill((client as? TextInferenceClient)?.isConnected == true || (client as? VisionInferenceClient)?.isConnected == true ? ZDDesign.successGreen : ZDDesign.warmGray)
                    .frame(width: 8, height: 8)
                Text(label).font(.caption)
            }
            content()
        }
    }
}

// MARK: - ValidatedTextField

private struct ValidatedTextField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isValid: Bool
    let validate: (String) -> Bool

    init(_ placeholder: String, text: Binding<String>, isValid: Binding<Bool>, validate: @escaping (String) -> Bool) {
        self.placeholder = placeholder
        self._text = text
        self._isValid = isValid
        self.validate = validate
    }

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
                .onChange(of: text) { _, new in isValid = validate(new) }
            if !text.isEmpty && !isValid {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(ZDDesign.signalRed)
                    .font(.caption)
            }
        }
    }
}

// MARK: - ToastMessage

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
    let color: Color
}

// MARK: - ToastView

struct ToastView: View {
    let toast: ToastMessage
    var body: some View {
        Label(toast.message, systemImage: toast.symbol)
            .font(.subheadline.weight(.medium))
            .foregroundColor(toast.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4)
    }
}

// MARK: - AuditLogView

struct AuditLogView: View {
    @State private var entries: [AuditEntry] = []
    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.type.rawValue)
                        .font(.caption.monospaced())
                        .foregroundColor(ZDDesign.cyanAccent)
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Audit Log")
        .onAppear { entries = AuditLogger.shared.recentEntries(limit: 500) }
    }
}

// MARK: - UIDevice Extension

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

#Preview {
    SettingsTabView()
}
