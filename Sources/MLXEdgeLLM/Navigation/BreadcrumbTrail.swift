// BreadcrumbTrail.swift — Backward-compatible wrapper synced from BreadcrumbEngine
// Combine-subscribed: trail + isRecording live-synced from EKF engine

import Foundation
import SwiftUI
import CoreLocation
import Combine

// MARK: - BreadcrumbTrail

@MainActor
class BreadcrumbTrail: ObservableObject {
    @Published var trail: [CLLocationCoordinate2D] = []
    @Published var isRecording = false
    @Published var backtrackingIndex = -1

    private var cancellables = Set<AnyCancellable>()

    init() {
        let engine = BreadcrumbEngine.shared
        engine.$trail
            .receive(on: DispatchQueue.main)
            .assign(to: &$trail)
        engine.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
    }

    func startRecording() {
        BreadcrumbEngine.shared.startRecording()
    }

    func stopRecording() {
        BreadcrumbEngine.shared.stopRecording()
    }

    func backtrack() {
        guard !trail.isEmpty else { return }
        if backtrackingIndex < 0 { backtrackingIndex = trail.count - 1 }
        if backtrackingIndex > 0 { backtrackingIndex -= 1 }
    }

    func forward() {
        guard backtrackingIndex >= 0 && backtrackingIndex < trail.count - 1 else { return }
        backtrackingIndex += 1
    }

    var backtrackCoordinate: CLLocationCoordinate2D? {
        guard backtrackingIndex >= 0 && backtrackingIndex < trail.count else { return nil }
        return trail[backtrackingIndex]
    }

    func exportGPX() -> Data {
        BreadcrumbEngine.shared.exportGPX()
    }
}
