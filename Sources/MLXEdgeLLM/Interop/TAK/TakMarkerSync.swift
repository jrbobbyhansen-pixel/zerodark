import Foundation
import SwiftUI
import CoreLocation

// MARK: - TakMarkerSync

class TakMarkerSync: ObservableObject {
    @Published private(set) var markers: [TakMarker] = []
    private var offlineQueue: [TakMarker] = []
    private let zeroDarkService: ZeroDarkService
    private let takService: TakService

    init(zeroDarkService: ZeroDarkService, takService: TakService) {
        self.zeroDarkService = zeroDarkService
        self.takService = takService
        Task {
            await syncMarkers()
        }
    }

    func addMarker(_ marker: TakMarker) {
        markers.append(marker)
        offlineQueue.append(marker)
        Task {
            await syncMarker(marker)
        }
    }

    func updateMarker(_ marker: TakMarker) {
        if let index = markers.firstIndex(where: { $0.id == marker.id }) {
            markers[index] = marker
            offlineQueue.append(marker)
            Task {
                await syncMarker(marker)
            }
        }
    }

    func removeMarker(_ marker: TakMarker) {
        markers.removeAll { $0.id == marker.id }
        offlineQueue.append(marker)
        Task {
            await syncMarker(marker)
        }
    }

    private func syncMarkers() async {
        do {
            let zeroDarkMarkers = try await zeroDarkService.fetchMarkers()
            let takMarkers = try await takService.fetchMarkers()

            let allMarkers = Set(zeroDarkMarkers + takMarkers)
            markers = Array(allMarkers)

            for marker in markers {
                offlineQueue.append(marker)
                await syncMarker(marker)
            }
        } catch {
            print("Failed to sync markers: \(error)")
        }
    }

    private func syncMarker(_ marker: TakMarker) async {
        do {
            if offlineQueue.contains(where: { $0.id == marker.id }) {
                try await zeroDarkService.updateMarker(marker)
                try await takService.updateMarker(marker)
                offlineQueue.removeAll { $0.id == marker.id }
            }
        } catch {
            print("Failed to sync marker \(marker.id): \(error)")
        }
    }
}

// MARK: - TakMarker

struct TakMarker: Identifiable, Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let type: String
    let attributes: [String: Any]
}

// MARK: - ZeroDarkService

actor ZeroDarkService {
    func fetchMarkers() async throws -> [TakMarker] {
        // Implementation to fetch markers from ZeroDark
        return []
    }

    func updateMarker(_ marker: TakMarker) async throws {
        // Implementation to update marker in ZeroDark
    }
}

// MARK: - TakService

actor TakService {
    func fetchMarkers() async throws -> [TakMarker] {
        // Implementation to fetch markers from TAK
        return []
    }

    func updateMarker(_ marker: TakMarker) async throws {
        // Implementation to update marker in TAK
    }
}