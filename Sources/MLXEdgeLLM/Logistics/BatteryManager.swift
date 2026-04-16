import Foundation
import SwiftUI

// MARK: - BatteryManager

final class BatteryManager: ObservableObject {
    @Published private(set) var batteryLevels: [Device: BatteryLevel] = [:]
    @Published private(set) var chargingQueue: [Device] = []

    private let proxy = BatteryProxy.shared
    private var syncTimer: Timer?

    init() {
        proxy.startSampling()

        // Sync phone battery from proxy
        Task { @MainActor in
            self.startSyncTimer()
        }
    }

    deinit {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Start periodic phone battery sync from BatteryProxy
    @MainActor
    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let level = self.proxy.currentLevel
                let minutesRemaining = self.proxy.estimatedMinutesRemaining
                self.batteryLevels[.phone(id: "local")] = BatteryLevel(
                    current: level,
                    predictedDepletion: minutesRemaining * 60  // convert to seconds
                )
            }
        }
    }

    func updateBatteryLevel(for device: Device, level: Double) {
        let depletion: TimeInterval
        switch device {
        case .phone:
            depletion = proxy.estimatedMinutesRemaining * 60
        default:
            // Linear estimate for external devices
            depletion = level > 0 ? (level / max(proxy.drainRatePerHour, 0.01)) * 3600 : 0
        }
        batteryLevels[device] = BatteryLevel(current: level, predictedDepletion: depletion)
    }

    func enqueueForCharging(device: Device) {
        guard !chargingQueue.contains(device) else { return }
        chargingQueue.append(device)
        chargingQueue.sort {
            (batteryLevels[$0]?.predictedDepletion ?? .infinity) <
            (batteryLevels[$1]?.predictedDepletion ?? .infinity)
        }
    }

    func dequeueFromCharging(device: Device) {
        chargingQueue.removeAll { $0 == device }
    }
}

// MARK: - BatteryLevel

struct BatteryLevel {
    let current: Double
    let predictedDepletion: TimeInterval
}

// MARK: - Device

enum Device: Identifiable, Hashable {
    case phone(id: String)
    case tablet(id: String)
    case drone(id: String)

    var id: String {
        switch self {
        case .phone(let id), .tablet(let id), .drone(let id):
            return id
        }
    }
}

// MARK: - BatteryManagerView

struct BatteryManagerView: View {
    @StateObject private var viewModel = BatteryManager()
    @ObservedObject private var proxy = BatteryProxy.shared

    var body: some View {
        VStack {
            // Phone battery with proxy trend data
            HStack {
                Image(systemName: proxy.isCharging ? "battery.100.bolt" : "battery.50")
                    .foregroundColor(proxy.currentLevel > 0.2 ? .green : .red)
                Text(String(format: "Phone: %.0f%%", proxy.currentLevel * 100))
                Spacer()
                Text(String(format: "%.0f min remaining", proxy.estimatedMinutesRemaining))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            if proxy.predictionAccuracy > 0.5 {
                HStack {
                    Text(String(format: "Drain: %.1f%%/hr", proxy.drainRatePerHour * 100))
                        .font(.caption)
                    Text(String(format: "R\u{00B2}: %.2f", proxy.predictionAccuracy))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            Divider()

            // External device list
            List(Array(viewModel.batteryLevels.keys.sorted(by: { $0.id < $1.id })), id: \.id) { device in
                if let level = viewModel.batteryLevels[device] {
                    HStack {
                        Text(device.id)
                        Spacer()
                        Text(String(format: "%.0f%%", level.current * 100))
                        Text(String(format: "~%dh", Int(level.predictedDepletion / 3600)))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}
