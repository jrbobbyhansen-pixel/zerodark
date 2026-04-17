// MeshAdapter.swift — Live mesh status telemetry adapter

import Foundation
import Combine

class MeshTelemetryAdapter: BaseTelemetryAdapter {
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
        // MeshService.$peers is @MainActor — hop to main to read it
        Task { @MainActor [weak self] in
            guard let self else { return }
            let onlineCount = MeshService.shared.peers.filter { $0.status != .offline }.count
            self.emit(.int(onlineCount))
        }
    }
}
