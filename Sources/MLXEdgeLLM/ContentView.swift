import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var haptic = HapticComms.shared
    @State private var bootComplete = false

    var body: some View {
        ZStack {
            if bootComplete {
                mainTabView
                    .transition(.opacity.animation(.easeIn(duration: 0.4)))
            } else {
                ZeroDarkBootView {
                    bootComplete = true
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.5), value: bootComplete)
    }

    // MARK: - Main Tab View

    private var mainTabView: some View {
        ZStack {
            TabView(selection: $appState.selectedTab) {
                MapTabView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(AppTab.map)

                NavTabView()
                    .tabItem { Label("Nav", systemImage: "location.north.fill") }
                    .tag(AppTab.nav)

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

            // Incoming haptic/notification banner
            if let code = haptic.lastReceivedCode, let sender = haptic.lastSender {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: code.icon)
                            .font(.title2)
                            .foregroundColor(code == .danger ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(code.displayName)
                                .font(.headline)
                                .foregroundColor(ZDDesign.pureWhite)
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
                    .accessibilityLabel("\(code.displayName) alert from \(sender)")
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: haptic.lastReceivedCode != nil)
                .zIndex(1)
            }

            SettingsFAB()
        }
        .environmentObject(appState)
    }
}

#Preview {
    ContentView()
}
