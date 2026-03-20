// TeamAdapter.swift — Team member count telemetry adapter

import Foundation

class TeamTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?

    override init(objectType: TelemetryObjectType) {
        super.init(objectType: objectType)
    }

    override func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            let peerCount = MeshService.shared.peers.count
            self?.emit(.int(peerCount))
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }
}
