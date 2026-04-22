// RetryPolicy.swift — Exponential-backoff retry helper for network / I/O.
//
// Replaces the ad-hoc "try a few times then give up" patterns scattered
// across Services/Interop. Callers wrap a throwing async closure; the
// policy retries with exponential backoff + optional jitter until either
// success or max attempts exhausted.

import Foundation

public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var initialBackoff: TimeInterval
    public var maxBackoff: TimeInterval
    public var jitter: Double              // 0..1 — fraction of each delay randomized
    public var backoffMultiplier: Double

    public init(
        maxAttempts: Int = 3,
        initialBackoff: TimeInterval = 1.0,
        maxBackoff: TimeInterval = 60.0,
        jitter: Double = 0.2,
        backoffMultiplier: Double = 2.0
    ) {
        self.maxAttempts = maxAttempts
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
        self.jitter = max(0, min(1, jitter))
        self.backoffMultiplier = backoffMultiplier
    }

    public static let `default` = RetryPolicy()
    public static let aggressive = RetryPolicy(maxAttempts: 5, initialBackoff: 0.5, maxBackoff: 30)
    public static let gentle = RetryPolicy(maxAttempts: 2, initialBackoff: 2.0, maxBackoff: 10)

    /// Execute `body` with retry + backoff. On success returns the value;
    /// on exhaust throws the last error encountered.
    /// - Parameter isRetriable: optional predicate — return false on errors
    ///   that should NOT be retried (auth failures, client validation, etc.)
    public func run<T: Sendable>(
        operation name: String,
        isRetriable: @Sendable (Error) -> Bool = { _ in true },
        body: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await body()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if !isRetriable(error) || attempt == maxAttempts {
                    throw error
                }
                try await sleepForBackoff(attempt: attempt)
            }
        }
        throw lastError ?? RetryError.exhausted(operation: name, attempts: maxAttempts)
    }

    private func sleepForBackoff(attempt: Int) async throws {
        let exp = pow(backoffMultiplier, Double(attempt - 1))
        let base = min(initialBackoff * exp, maxBackoff)
        let jitterDelta = base * jitter * (Double.random(in: -1...1))
        let delay = max(0.0, base + jitterDelta)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

public enum RetryError: Error, LocalizedError {
    case exhausted(operation: String, attempts: Int)

    public var errorDescription: String? {
        switch self {
        case .exhausted(let op, let n): return "Retry exhausted for \(op) after \(n) attempts."
        }
    }
}
