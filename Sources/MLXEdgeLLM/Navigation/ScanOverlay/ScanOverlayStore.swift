// ScanOverlayStore.swift — Per-scan overlay persistence + mesh broadcast.
//
// Storage convention: overlay.json sidecar inside each scan directory
//   Documents/LiDARScans/<scan-uuid>/overlay.json
// mirroring the metadata.json pattern in ScanStorage.swift.

import Foundation
import simd
import Combine

@MainActor
final class ScanOverlayStore: ObservableObject {
    static let shared = ScanOverlayStore()

    /// scanID → ordered list of overlays. Order reflects creation order.
    @Published var overlays: [UUID: [ScanOverlay]] = [:]
    @Published var lastError: String?

    private init() {}

    // MARK: - File IO

    private func overlayURL(for scan: SavedScan) -> URL {
        scan.scanDir.appendingPathComponent("overlay.json")
    }

    /// Load overlay.json from the scan directory. Silent if file is absent (fresh scan).
    func load(for scan: SavedScan) {
        let url = overlayURL(for: scan)
        guard FileManager.default.fileExists(atPath: url.path) else {
            overlays[scan.id] = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let list = try decoder.decode([ScanOverlay].self, from: data)
            overlays[scan.id] = list
        } catch {
            lastError = "Overlay load failed: \(error.localizedDescription)"
            overlays[scan.id] = []
        }
    }

    /// Atomic write of the current overlay list for a scan.
    private func save(for scan: SavedScan) {
        let list = overlays[scan.id] ?? []
        let url = overlayURL(for: scan)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(list)
            try data.write(to: url, options: .atomic)
        } catch {
            lastError = "Overlay save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD

    func list(for scanID: UUID) -> [ScanOverlay] {
        overlays[scanID] ?? []
    }

    func add(_ overlay: ScanOverlay, to scan: SavedScan) {
        var list = overlays[scan.id] ?? []
        list.append(overlay)
        overlays[scan.id] = list
        save(for: scan)
        broadcast(for: scan)
    }

    func update(_ overlay: ScanOverlay, in scan: SavedScan) {
        guard var list = overlays[scan.id],
              let idx = list.firstIndex(where: { $0.id == overlay.id }) else { return }
        list[idx] = overlay
        overlays[scan.id] = list
        save(for: scan)
        broadcast(for: scan)
    }

    func remove(_ id: UUID, from scan: SavedScan) {
        guard var list = overlays[scan.id] else { return }
        list.removeAll { $0.id == id }
        overlays[scan.id] = list
        save(for: scan)
        broadcast(for: scan)
    }

    // MARK: - Mesh Broadcast

    /// Broadcast the full overlay set for `scan` to all peers.
    /// Sending the full set (not a delta) lets late-joining peers catch up with one message.
    func broadcast(for scan: SavedScan) {
        let payload = OverlayBroadcastPayload(
            scanID: scan.id,
            overlays: overlays[scan.id] ?? [],
            senderCallsign: AppConfig.deviceCallsign,
            timestamp: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        MeshService.shared.broadcastData(data, type: .scanOverlay)
    }

    // MARK: - Incoming

    /// Handle an overlay payload received from a peer. Merges by scanID; the peer's
    /// set is authoritative for overlays it authored — we replace the whole set for
    /// simplicity (last-writer-wins), matching the broadcast convention.
    func applyIncoming(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(OverlayBroadcastPayload.self, from: data) else { return }
        overlays[payload.scanID] = payload.overlays

        // Persist to disk if we already know this scan.
        if let scan = ScanStorage.shared.savedScans.first(where: { $0.id == payload.scanID }) {
            let url = overlayURL(for: scan)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let encoded = try? encoder.encode(payload.overlays) {
                try? encoded.write(to: url, options: .atomic)
            }
        }
    }
}
