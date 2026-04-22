// IOTimeout.swift — Generic I/O timeout wrapper for hardware operations.
//
// Every hardware I/O (drone MAVLink, thermal camera frame, anemometer, LiDAR
// measure) must be bounded — a disconnected device should not hang the app
// forever. This file provides a tiny `withTimeout` helper and a typed
// `IOTimeoutError` that callers can catch and surface to the operator.

import Foundation

public struct IOTimeoutError: Error, LocalizedError {
    public let seconds: TimeInterval
    public let operation: String

    public var errorDescription: String? {
        "I/O timeout after \(String(format: "%.1f", seconds))s: \(operation)"
    }
}

/// Run `body` with a hard time budget. If `body` does not complete within
/// `seconds`, the enclosing Task group is cancelled and `IOTimeoutError`
/// is thrown. Callers should catch the error and mark the device as
/// unreachable / offline rather than letting a disconnected peripheral
/// hang a field operation.
public func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: String,
    _ body: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw IOTimeoutError(seconds: seconds, operation: operation)
        }
        // The first task to complete wins. Cancel the other.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

/// Sync convenience for callbacks that still use DispatchQueue. Wraps a
/// semaphore-signalled call with a bounded wait. Prefer the async version
/// above for new code.
public func withTimeoutSync<T>(
    seconds: TimeInterval,
    operation: String,
    _ body: (@escaping (Result<T, Error>) -> Void) -> Void
) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    body { r in
        result = r
        semaphore.signal()
    }
    let deadline = DispatchTime.now() + seconds
    switch semaphore.wait(timeout: deadline) {
    case .success:
        switch result {
        case .success(let value): return value
        case .failure(let err):   throw err
        case .none:               throw IOTimeoutError(seconds: seconds, operation: operation)
        }
    case .timedOut:
        throw IOTimeoutError(seconds: seconds, operation: operation)
    }
}
