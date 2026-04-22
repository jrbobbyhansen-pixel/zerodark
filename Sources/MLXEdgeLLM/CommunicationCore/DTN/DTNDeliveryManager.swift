// DTNDeliveryManager.swift — Manages bundle delivery with exponential backoff (NASA HDTN pattern)

import Foundation

/// Manages bundle delivery with exponential backoff (NASA HDTN pattern)
@MainActor
public class DTNDeliveryManager: ObservableObject {
    public static let shared = DTNDeliveryManager()

    @Published public private(set) var isRunning = false
    @Published public private(set) var lastDeliveryAttempt: Date?

    private var deliveryTask: Task<Void, Never>?
    private let buffer = DTNBuffer.shared

    // Exponential backoff settings (HDTN pattern)
    private let baseRetryInterval: TimeInterval = 5
    private let maxRetryInterval: TimeInterval = 300  // 5 minutes max
    /// Retry cap. Bumped from 10 → 25 in PR-C11 to match the audit's
    /// guidance — 25 attempts across the backoff ladder covers ~4 hours
    /// of brief mesh outages before we give up and dead-letter.
    private let maxAttempts = 25

    private init() {}

    /// Start the delivery manager background loop
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        deliveryTask = Task {
            await deliveryLoop()
        }

    }

    /// Stop the delivery manager
    public func stop() {
        deliveryTask?.cancel()
        deliveryTask = nil
        isRunning = false
    }

    /// Main delivery loop
    private func deliveryLoop() async {
        while !Task.isCancelled {
            await attemptDeliveries()

            // Wait before next cycle
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
        }
    }

    /// Attempt to deliver all pending bundles
    private func attemptDeliveries() async {
        lastDeliveryAttempt = Date()

        guard let bundles = try? await buffer.getPendingBundles() else {
            return
        }

        for bundle in bundles {
            // Retire bundles that have exhausted the retry ladder into the
            // dead-letter queue. They remain on disk until an operator
            // discards them from Settings.
            guard bundle.deliveryAttempts < maxAttempts else {
                try? await buffer.markDeadLettered(bundle.id,
                                                   reason: "retry_exhausted")
                continue
            }

            // Check if enough time has passed since last attempt (exponential backoff)
            if let lastAttempt = bundle.lastAttemptAt {
                let backoff = min(
                    baseRetryInterval * pow(2.0, Double(bundle.deliveryAttempts)),
                    maxRetryInterval
                )
                let nextAttemptTime = lastAttempt.addingTimeInterval(backoff)
                if Date() < nextAttemptTime {
                    continue
                }
            }

            // Attempt delivery
            await attemptDelivery(bundle)
        }
    }

    /// Attempt to deliver a single bundle
    private func attemptDelivery(_ bundle: DTNBundle) async {
        // Record the attempt
        try? await buffer.recordAttempt(bundle.id)

        // Check if destination is reachable
        // Integration point: HapticComms peer connectivity
        let isReachable = await checkReachability(bundle.destination)

        guard isReachable else {
            return
        }

        // Attempt actual delivery
        // Integration point: HapticComms.send()
        let success = await deliverPayload(bundle)

        if success {
            try? await buffer.markDelivered(bundle.id)
        }
    }

    /// Check if a destination is currently reachable via mesh
    private func checkReachability(_ destination: String) async -> Bool {
        let mesh = await MeshService.shared
        if destination == "all" {
            return mesh.isActive
        }
        return mesh.peers.contains { $0.id == destination && $0.status == .online }
    }

    /// Deliver the bundle payload to destination via mesh (supports binary + text)
    private func deliverPayload(_ bundle: DTNBundle) async -> Bool {
        let mesh = await MeshService.shared
        guard mesh.isActive else { return false }

        let destination = bundle.destination
        var success = false

        if destination == "all" || destination == "broadcast" {
            mesh.broadcastData(bundle.payload, type: .dtn)
            success = true
        } else {
            success = mesh.sendData(bundle.payload, to: destination, type: .dtn)
        }

        if success {
            ActivityFeed.shared.log(.dtnDelivered, message: "DTN delivered to \(destination)")
        }
        return success
    }
}
