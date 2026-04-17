// TelemetryStore.swift — Central telemetry store with adapter management

import Foundation
import Combine
import UIKit
import CoreLocation

/// Battery telemetry adapter
class BatteryTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?

    override init(objectType: TelemetryObjectType) {
        super.init(objectType: objectType)
    }

    override func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            let level = UIDevice.current.batteryLevel
            self?.emit(.double(Double(level)))
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Central telemetry store singleton
@MainActor
public class TelemetryStore: NSObject, ObservableObject {
    public static let shared = TelemetryStore()

    @Published public var objects: [TelemetryObject] = []
    private var adapters: [TelemetryAdapter] = []
    private var subscriptions: Set<AnyCancellable> = []

    private override init() {
        super.init()
        registerDefaultAdapters()
    }

    /// Register default adapters
    private func registerDefaultAdapters() {
        registerAdapter(BatteryTelemetryAdapter(objectType: .battery))
        registerAdapter(MeshTelemetryAdapter(objectType: .mesh))
        registerAdapter(LocationTelemetryAdapter(objectType: .position))
        registerAdapter(TeamTelemetryAdapter(objectType: .team))
        registerAdapter(ThreatTelemetryAdapter(objectType: .threat))

        // Create objects for all types
        for type in TelemetryObjectType.allCases {
            let obj = TelemetryObject(type: type)
            objects.append(obj)
        }

        // Subscribe to adapters and forward to objects
        for adapter in adapters {
            adapter.publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] datum in
                    self?.updateObject(type: adapter.objectType, with: datum)
                }
                .store(in: &subscriptions)
        }

        // Start adapters
        adapters.forEach { $0.start() }
    }

    /// Register an adapter
    public func registerAdapter(_ adapter: TelemetryAdapter) {
        adapters.append(adapter)
    }

    /// Update object with new datum
    private func updateObject(type: TelemetryObjectType, with datum: TelemetryDatum) {
        if let index = objects.firstIndex(where: { $0.type == type }) {
            objects[index].add(datum)
        }
    }

    /// Get object by type
    public func object(for type: TelemetryObjectType) -> TelemetryObject? {
        objects.first { $0.type == type }
    }

    deinit {
        adapters.forEach { $0.stop() }
    }
}
