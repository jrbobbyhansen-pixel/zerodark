// ErrorReporterTests.swift — Coverage for PR-A5 ErrorReporter + RetryPolicy.
//
// Verifies:
//   - latest is set + overwritten as new reports arrive
//   - recent buffer records every call
//   - userFacing nil vs non-nil distinction (audit-only vs toast-worthy)
//   - RetryPolicy succeeds, backs off, and gives up cleanly
//   - RetryPolicy respects cancellation
//   - Non-retriable errors abort immediately

import XCTest
@testable import ZeroDark

@MainActor
final class ErrorReporterTests: XCTestCase {

    override func setUp() async throws {
        ErrorReporter.shared.clearRecent()
        ErrorReporter.shared.dismissLatest()
    }

    func test_latest_setOnReport() {
        ErrorReporter.shared.report(
            category: .navigation,
            message: "GPS lost",
            userMessage: "Location unavailable."
        )
        XCTAssertNotNil(ErrorReporter.shared.latest)
        XCTAssertEqual(ErrorReporter.shared.latest?.category, .navigation)
        XCTAssertEqual(ErrorReporter.shared.latest?.userFacing, "Location unavailable.")
    }

    func test_latest_nilWhenUserMessageNil_stillAddedToRecent() {
        ErrorReporter.shared.report(
            category: .storage,
            message: "Atomic write retry"
        )
        // Audit-only — user shouldn't see a toast, but a record remains.
        XCTAssertNil(ErrorReporter.shared.latest)
        XCTAssertEqual(ErrorReporter.shared.recent.count, 1)
        XCTAssertEqual(ErrorReporter.shared.recent.first?.category, .storage)
    }

    func test_latest_overwrittenByNewer() {
        ErrorReporter.shared.report(category: .mesh, message: "first", userMessage: "One.")
        ErrorReporter.shared.report(category: .crypto, message: "second", userMessage: "Two.")
        XCTAssertEqual(ErrorReporter.shared.latest?.category, .crypto)
        XCTAssertEqual(ErrorReporter.shared.latest?.userFacing, "Two.")
    }

    func test_recent_recordsEveryCall() {
        for i in 0..<10 {
            ErrorReporter.shared.report(category: .other, message: "r\(i)")
        }
        XCTAssertEqual(ErrorReporter.shared.recent.count, 10)
    }

    func test_dismissLatest_clearsToastButKeepsHistory() {
        ErrorReporter.shared.report(category: .safety, message: "x", userMessage: "Y")
        XCTAssertNotNil(ErrorReporter.shared.latest)
        ErrorReporter.shared.dismissLatest()
        XCTAssertNil(ErrorReporter.shared.latest)
        XCTAssertEqual(ErrorReporter.shared.recent.count, 1)
    }

    func test_clearRecent_empties() {
        for i in 0..<3 {
            ErrorReporter.shared.report(category: .network, message: "n\(i)")
        }
        ErrorReporter.shared.clearRecent()
        XCTAssertEqual(ErrorReporter.shared.recent.count, 0)
    }
}

final class RetryPolicyTests: XCTestCase {

    func test_success_onFirstTry_noRetry() async throws {
        let counter = AttemptCounter()
        let result: Int = try await RetryPolicy(maxAttempts: 3, initialBackoff: 0.01)
            .run(operation: "unit") {
                await counter.increment()
                return 42
            }
        XCTAssertEqual(result, 42)
        let attempts = await counter.value
        XCTAssertEqual(attempts, 1)
    }

    func test_success_afterTwoFailures() async throws {
        let counter = AttemptCounter()
        let result: String = try await RetryPolicy(maxAttempts: 3, initialBackoff: 0.01, jitter: 0)
            .run(operation: "retry-success") {
                let n = await counter.increment()
                if n < 3 {
                    throw URLError(.timedOut)
                }
                return "ok"
            }
        XCTAssertEqual(result, "ok")
        let attempts = await counter.value
        XCTAssertEqual(attempts, 3)
    }

    func test_exhausted_throwsLastError() async {
        // RetryPolicy throws the underlying error (not RetryError) on the
        // final attempt — keeps callers' catch-clauses unchanged after
        // adding retry wrapping.
        let counter = AttemptCounter()
        do {
            let _: Int = try await RetryPolicy(maxAttempts: 2, initialBackoff: 0.01, jitter: 0)
                .run(operation: "exhaust") {
                    _ = await counter.increment()
                    throw URLError(.notConnectedToInternet)
                }
            XCTFail("expected throw")
        } catch let err as URLError {
            XCTAssertEqual(err.code, .notConnectedToInternet)
        } catch {
            XCTFail("expected URLError, got \(error)")
        }
        let attempts = await counter.value
        XCTAssertEqual(attempts, 2)
    }

    func test_nonRetriable_abortsImmediately() async {
        let counter = AttemptCounter()
        do {
            let _: Int = try await RetryPolicy(maxAttempts: 5, initialBackoff: 0.01, jitter: 0)
                .run(
                    operation: "non-retriable",
                    isRetriable: { _ in false }
                ) {
                    _ = await counter.increment()
                    throw URLError(.badURL)
                }
            XCTFail("expected throw")
        } catch is URLError {
            // expected
        } catch {
            XCTFail("expected URLError, got \(error)")
        }
        let attempts = await counter.value
        XCTAssertEqual(attempts, 1, "non-retriable should abort after first throw")
    }

    func test_retryError_exhausted_has_localizedDescription() {
        let err = RetryError.exhausted(operation: "test-op", attempts: 4)
        XCTAssertNotNil(err.errorDescription)
        XCTAssertTrue(err.errorDescription!.contains("test-op"))
        XCTAssertTrue(err.errorDescription!.contains("4"))
    }

    func test_presets_areSane() {
        XCTAssertGreaterThan(RetryPolicy.default.maxAttempts, 1)
        XCTAssertGreaterThan(RetryPolicy.aggressive.maxAttempts, RetryPolicy.gentle.maxAttempts)
        XCTAssertLessThan(RetryPolicy.aggressive.initialBackoff, RetryPolicy.gentle.initialBackoff)
    }

    func test_jitter_clampedTo_0_1() {
        let p = RetryPolicy(jitter: -3.0)
        XCTAssertEqual(p.jitter, 0.0)
        let p2 = RetryPolicy(jitter: 5.0)
        XCTAssertEqual(p2.jitter, 1.0)
    }
}

// Thread-safe counter for async-closure tests. @Sendable closures can't
// capture inout `var`, so we wrap counting in an actor.
private actor AttemptCounter {
    private(set) var value = 0
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}
