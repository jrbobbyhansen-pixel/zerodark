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
    private let maxAttempts = 10

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
            // Skip if too many attempts
            guard bundle.deliveryAttempts < maxAttempts else {
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

    /// Check if a destination is currently reachable
    private func checkReachability(_ destination: String) async -> Bool {
        // return HapticComms.shared.isReachable(destination)

        // Placeholder: assume reachable for broadcast
        if destination == "all" {
            return true
        }

        // For specific peer, check connectivity
        // return HapticComms.shared.connectedPeers.contains(destination)
        return false
    }

    /// Deliver the bundle payload to destination
    private func deliverPayload(_ bundle: DTNBundle) async -> Bool {
        // return await HapticComms.shared.send(bundle.payload, to: bundle.destination)

        // Placeholder
        return false
    }
}
