// MenuBarApp.swift — macOS Menu Bar Status Menu
// Status indicator for mesh connectivity, TAK server, and model status

import SwiftUI

#if os(macOS)

@main
struct ZeroDarkMenuBarApp: App {
    @StateObject private var statusMonitor = MenuBarStatusMonitor()

    var body: some Scene {
        MenuBarExtra("ZeroDark", systemImage: "shield.fill") {
            MenuBarContentView()
                .environmentObject(statusMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Status Monitor

@MainActor
final class MenuBarStatusMonitor: ObservableObject {
    @Published var meshConnected = false
    @Published var meshPeerCount = 0
    @Published var takConnected = false
    @Published var modelLoaded = false
    @Published var threatLevel: ThreatLevel = .none
    @Published var alerts: [MeshAlert] = []

    private var cancellables = Set<AnyCancellable>()

    init() {
        subscribeToUpdates()
    }

    private func subscribeToUpdates() {
        // Mesh connectivity
        MeshService.shared.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.meshConnected = !peers.isEmpty
                self?.meshPeerCount = peers.count
            }
            .store(in: &cancellables)

        // TAK connectivity
        FreeTAKConnector.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: \.takConnected, on: self)
            .store(in: &cancellables)

        // Model status
        MLXInference.shared.$isModelReady
            .receive(on: DispatchQueue.main)
            .assign(to: \.modelLoaded, on: self)
            .store(in: &cancellables)

        // Threat level
        ThreatAnalyzer.shared.$threatLevel
            .receive(on: DispatchQueue.main)
            .assign(to: \.threatLevel, on: self)
            .store(in: &cancellables)

        // Mesh anomalies
        MeshAnomalyDetector.shared.$alerts
            .receive(on: DispatchQueue.main)
            .assign(to: \.alerts, on: self)
            .store(in: &cancellables)
    }
}

// MARK: - Menu Bar Content

struct MenuBarContentView: View {
    @Environment(\.openURL) var openURL
    @EnvironmentObject var monitor: MenuBarStatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "shield.fill")
                    .font(.title3)
                    .foregroundColor(.cyan)
                Text("ZeroDark")
                    .fontWeight(.semibold)
                Spacer()
                Text(monitor.threatLevel.description)
                    .font(.caption)
                    .foregroundColor(threatColor)
            }
            .padding(.bottom, 4)

            Divider()

            // Status Section
            VStack(alignment: .leading, spacing: 6) {
                StatusRow(
                    icon: "wifi",
                    title: "Mesh",
                    status: monitor.meshConnected ? "\(monitor.meshPeerCount) peers" : "Offline",
                    isActive: monitor.meshConnected,
                    color: .blue
                )

                StatusRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "TAK Server",
                    status: monitor.takConnected ? "Connected" : "Disconnected",
                    isActive: monitor.takConnected,
                    color: .red
                )

                StatusRow(
                    icon: "cpu",
                    title: "Model",
                    status: monitor.modelLoaded ? "Ready" : "Loading",
                    isActive: monitor.modelLoaded,
                    color: .cyan
                )

                if !monitor.alerts.isEmpty {
                    StatusRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Alerts",
                        status: "\(monitor.alerts.count) active",
                        isActive: true,
                        color: .orange
                    )
                }
            }

            Divider()

            // Actions Section
            VStack(alignment: .leading, spacing: 4) {
                MenuBarAction(title: "Open ZeroDark", icon: "square.and.arrow.up") {
                    openApp()
                }

                MenuBarAction(title: "Share Location", icon: "location.fill") {
                    shareLocation()
                }

                MenuBarAction(title: "Emergency SOS", icon: "exclamationmark.circle.fill") {
                    broadcastSOS()
                }

                Divider()

                MenuBarAction(title: "Quit ZeroDark", icon: "xmark.circle") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 240)
    }

    private var threatColor: Color {
        switch monitor.threatLevel {
        case .none: return .green
        case .low: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    private func openApp() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            NSWorkspace.shared.open(
                NSWorkspace.AccessoryType.app,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    private func shareLocation() {
        Task {
            let coordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            await FreeTAKConnector.shared.sendPresence(
                coordinate: coordinate,
                callsign: "ZeroDark-Mac"
            )
        }
    }

    private func broadcastSOS() {
        Task {
            let coordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
            await FreeTAKConnector.shared.sendSOS(
                coordinate: coordinate,
                callsign: "ZeroDark-Mac-SOS"
            )
            await MeshService.shared.broadcastSOS()
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let icon: String
    let title: String
    let status: String
    let isActive: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? color : .gray)
                .frame(width: 8, height: 8)

            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(status)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Menu Bar Action

struct MenuBarAction: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#endif
