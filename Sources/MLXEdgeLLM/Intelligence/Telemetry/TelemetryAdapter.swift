// TelemetryAdapter.swift — Base telemetry adapter pattern (Combine-based)

import Foundation
import Combine
import UIKit

/// Protocol for telemetry adapters
public protocol TelemetryAdapter {
    var objectType: TelemetryObjectType { get }
    var publisher: AnyPublisher<TelemetryDatum, Never> { get }
    func start()
    func stop()
}

/// Base class for telemetry adapters
open class BaseTelemetryAdapter: NSObject, TelemetryAdapter {
    public let objectType: TelemetryObjectType
    internal let subject = PassthroughSubject<TelemetryDatum, Never>()
    public var publisher: AnyPublisher<TelemetryDatum, Never> { subject.eraseToAnyPublisher() }

    // History of emitted values (last 100)
    internal var history: [TelemetryDatum] = []

    public init(objectType: TelemetryObjectType) {
        self.objectType = objectType
    }

    /// Emit a telemetry datum
    internal func emit(_ value: TelemetryValue) {
        let datum = TelemetryDatum(timestamp: Date(), value: value)
        subject.send(datum)
        history.append(datum)
        if history.count > 100 {
            history.removeFirst()
        }
    }

    open func start() {}
    open func stop() {}
}
