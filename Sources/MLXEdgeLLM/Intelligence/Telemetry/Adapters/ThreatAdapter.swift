// ThreatAdapter.swift — Active threat level telemetry adapter

import Foundation

class ThreatTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?

    override init(objectType: TelemetryObjectType) {
        super.init(objectType: objectType)
    }

    override func start() {
        scheduleEmit()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.scheduleEmit()
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleEmit() {
        // Both sources are @MainActor — hop to main actor to read them
        Task { @MainActor [weak self] in
            guard let self else { return }
            let violations = RuntimeSafetyMonitor.shared.unresolvedViolations
            let anomalies = MeshAnomalyDetector.shared.alerts
                .filter { $0.severity >= .high }

            let level: Int
            if !violations.isEmpty && violations.contains(where: { $0.severity >= 3 }) {
                level = 3   // High
            } else if !violations.isEmpty || !anomalies.isEmpty {
                level = 2   // Medium
            } else {
                level = 0   // None
            }

            self.emit(.int(level))
        }
    }
}
