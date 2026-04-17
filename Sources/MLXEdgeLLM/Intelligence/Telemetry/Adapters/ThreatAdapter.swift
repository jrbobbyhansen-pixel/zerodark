// ThreatAdapter.swift — Active threat level telemetry adapter

import Foundation

class ThreatTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?

    override init(objectType: TelemetryObjectType) {
        super.init(objectType: objectType)
    }

    override func start() {
        emitCurrentLevel()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.emitCurrentLevel()
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func emitCurrentLevel() {
        // Derive threat level from active safety violations and mesh anomalies
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

        emit(.int(level))
    }
}
