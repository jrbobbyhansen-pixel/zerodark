// MeshAdapter.swift — Live mesh status telemetry adapter

import Foundation
import Combine

class MeshTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    override init(objectType: TelemetryObjectType) {
        super.init(objectType: objectType)
    }

    override func start() {
        // Emit immediately on first tick
        emitCurrentStatus()

        // Subscribe to peer list changes for real-time updates
        cancellable = MeshService.shared.$peers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in
                let onlineCount = peers.filter { $0.status != .offline }.count
                self?.emit(.int(onlineCount))
            }

        // Fallback timer at 10s in case publisher doesn't fire
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.emitCurrentStatus()
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
        cancellable = nil
    }

    private func emitCurrentStatus() {
        let onlineCount = MeshService.shared.peers.filter { $0.status != .offline }.count
        emit(.int(onlineCount))
    }
}
