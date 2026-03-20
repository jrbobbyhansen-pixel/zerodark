import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var haptic = HapticComms.shared

    var body: some View {
        ZStack {
            TabView(selection: $appState.selectedTab) {
                TeamMapView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(AppTab.map)

                LiDARTabView()
                    .tabItem { Label("LiDAR", systemImage: "cube.fill") }
                    .tag(AppTab.lidar)

                IntelTabView()
                    .tabItem { Label("Intel", systemImage: "brain") }
                    .tag(AppTab.intel)

                OpsTabView()
                    .tabItem { Label("Ops", systemImage: "shield.checkered") }
                    .tag(AppTab.ops)
            }

            // Incoming haptic notification banner
            if let code = haptic.lastReceivedCode, let sender = haptic.lastSender {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: code.icon)
                            .font(.title2)
                            .foregroundColor(code == .danger ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(code.displayName)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("from \(sender)")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(ZDDesign.darkCard)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(.horizontal)
                    .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: haptic.lastReceivedCode != nil)
                .zIndex(1)
            }

            SettingsFAB()
        }
        .preferredColorScheme(.dark)
        .environmentObject(appState)
        .environmentObject(NavigationViewModel())
        .task {
            if LocalInferenceEngine.shared.modelFileExists {
                await LocalInferenceEngine.shared.loadModel()
            }
            if VisionInferenceEngine.shared.modelFileExists {
                try? await VisionInferenceEngine.shared.loadModel()
            }

            // Start Phase 1 systems
            RuntimeSafetyMonitor.shared.start()
            DTNDeliveryManager.shared.start()
            Task {
                _ = await SessionKeyManager.shared.generateSessionKey()
            }

            // Start Phase 2 systems
            GeofenceMonitor.shared.start()
            _ = TelemetryStore.shared  // Triggers adapter registration
        }
    }
}

#Preview {
    ContentView()
}
