import SwiftUI

struct SettingsTabView: View {
    @State private var callsign = AppConfig.deviceCallsign
    @State private var takHost = ""
    @State private var takPort = "\(AppConfig.defaultTAKPort)"
    @State private var takTLSPort = "\(AppConfig.defaultTAKTLSPort)"
    @StateObject private var takConnector = FreeTAKConnector.shared
    @StateObject private var engine = LocalInferenceEngine.shared
    @StateObject private var modelMgr = ModelManager.shared
    @State private var showCopiedToast = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Callsign", value: callsign)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Section("TAK Server") {
                    TextField("Host", text: $takHost)
                        .keyboardType(.default)
                    TextField("TCP Port", text: $takPort)
                        .keyboardType(.numberPad)
                    TextField("TLS Port", text: $takTLSPort)
                        .keyboardType(.numberPad)

                    if takConnector.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(ZDDesign.successGreen)
                    } else if let error = takConnector.lastError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundColor(ZDDesign.signalRed)
                            .font(.caption)
                    }

                    VStack(spacing: 8) {
                        Button("Connect (TCP)") {
                            if let port = UInt16(takPort) {
                                takConnector.connect(host: takHost, port: port)
                            }
                        }
                        .disabled(takHost.isEmpty)

                        Button("Connect (TLS)") {
                            if let port = UInt16(takTLSPort) {
                                takConnector.connectTLS(host: takHost, port: port)
                            }
                        }
                        .disabled(takHost.isEmpty)

                        if takConnector.isConnected {
                            Button("Disconnect", role: .destructive) {
                                takConnector.disconnect()
                            }
                        }
                    }
                }

                Section("Local AI Model") {
                    switch engine.modelState {
                    case .notLoaded:
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(ZDDesign.signalRed)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Phi-3.5-mini Not Installed")
                                    .font(.subheadline)
                                    .foregroundColor(ZDDesign.pureWhite)
                                Text("The on-device model enables fully offline AI responses.\nModel: Phi-3.5-mini (2.2GB) — no internet required after install")
                                    .font(.caption2)
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                        Button(action: { Task { await modelMgr.installFromBundle() } }) {
                            Label("Install from Bundle", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!modelMgr.modelInstalled)
                        .buttonStyle(.bordered)
                        Button(action: {
                            UIPasteboard.general.string = """
                            ZeroDark Model Setup:
                            1. Download phi-3.5-mini.gguf from HuggingFace
                            2. Connect iPhone via USB
                            3. Open Finder → iPhone → Files → ZeroDark
                            4. Copy model file to Models folder
                            5. Restart app
                            """
                            showCopiedToast = true
                        }) {
                            Label("Copy Instructions", systemImage: "doc.on.doc.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    case .loading:
                        HStack {
                            ProgressView()
                                .tint(ZDDesign.safetyYellow)
                            Text("Loading Phi-3.5-mini...")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        ProgressView(value: engine.loadProgress)
                            .tint(ZDDesign.safetyYellow)
                    case .ready:
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ZDDesign.successGreen)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phi-3.5-mini — On Device")
                                    .font(.subheadline)
                                    .foregroundColor(ZDDesign.pureWhite)
                                Text("\(modelMgr.installedModelSize) • Running on A18 Pro • CPU/NEON")
                                    .font(.caption2)
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                        Button(action: { engine.unloadModel() }) {
                            Label("Unload Model", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(ZDDesign.signalRed)
                    case .error(let msg):
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(ZDDesign.signalRed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Model Error")
                                    .font(.subheadline)
                                    .foregroundColor(ZDDesign.pureWhite)
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                        Button(action: { Task { await engine.loadModel() } }) {
                            Label("Retry", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Remote AI Servers") {
                    Text("Used when on-device model is unavailable or for vision analysis.")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.mediumGray)
                    HStack {
                        Circle().fill(TextInferenceClient.shared.isConnected ? ZDDesign.successGreen : ZDDesign.warmGray)
                            .frame(width: 8, height: 8)
                        Text("Phi-3.5-mini (Text)").font(.caption).foregroundColor(TextInferenceClient.shared.isConnected ? ZDDesign.successGreen : .secondary)
                    }
                    TextField("Text Server URL", text: Binding(
                        get: { TextInferenceClient.shared.serverURL },
                        set: { TextInferenceClient.shared.serverURL = $0 }
                    )).keyboardType(.URL).autocapitalization(.none)
                    Button("Test Text Connection") { Task { await TextInferenceClient.shared.checkConnection() } }

                    Divider()

                    HStack {
                        Circle().fill(VisionInferenceClient.shared.isConnected ? ZDDesign.successGreen : ZDDesign.warmGray)
                            .frame(width: 8, height: 8)
                        Text("moondream2 (Vision)").font(.caption).foregroundColor(VisionInferenceClient.shared.isConnected ? ZDDesign.successGreen : .secondary)
                    }
                    TextField("Vision Server URL", text: Binding(
                        get: { VisionInferenceClient.shared.serverURL },
                        set: { VisionInferenceClient.shared.serverURL = $0 }
                    )).keyboardType(.URL).autocapitalization(.none)
                    Button("Test Vision Connection") { Task { await VisionInferenceClient.shared.checkConnection() } }

                    Text("Start servers on Mac: see ~/Desktop/start-bitnet-server.sh")
                        .font(.caption2).foregroundColor(ZDDesign.mediumGray)
                }

                Section("Maps") {
                    NavigationLink("Offline Map Downloads") {
                        TileDownloadView()
                    }
                }

                Section("Device Info") {
                    LabeledContent("Device", value: UIDevice.current.name)
                    LabeledContent("OS", value: UIDevice.current.systemVersion)
                    LabeledContent("Model", value: UIDevice.current.modelName)
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Bundle ID", value: "com.bobbyhansen.zerodark")
                }
            }
            .navigationTitle("Settings")
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    Text("Copied to clipboard")
                        .font(.caption)
                        .padding(8)
                        .background(ZDDesign.darkCard)
                        .cornerRadius(8)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showCopiedToast = false }
                            }
                        }
                        .padding()
                }
            }
        }
    }
}

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

#Preview {
    SettingsTabView()
}
