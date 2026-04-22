// IOTimeoutTests.swift — Coverage for PR-A1 I/O timeout wrapper.
//
// Verifies:
//   - withTimeout returns value when body completes in time
//   - withTimeout throws IOTimeoutError when body exceeds budget
//   - withTimeoutSync (DispatchSemaphore path) matches async semantics
//   - Timeout error carries the operation label

import XCTest
@testable import ZeroDark

final class IOTimeoutTests: XCTestCase {

    func test_withTimeout_completesOnTime() async throws {
        let result = try await withTimeout(seconds: 1.0, operation: "fast") {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return 7
        }
        XCTAssertEqual(result, 7)
    }

    func test_withTimeout_firesOnOverrun() async {
        do {
            _ = try await withTimeout(seconds: 0.05, operation: "slow") {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                return "never"
            }
            XCTFail("expected IOTimeoutError")
        } catch let err as IOTimeoutError {
            XCTAssertEqual(err.operation, "slow")
            XCTAssertEqual(err.seconds, 0.05, accuracy: 0.001)
            XCTAssertNotNil(err.errorDescription)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_withTimeoutSync_returnsValue() throws {
        let result: Int = try withTimeoutSync(seconds: 0.5, operation: "sync-ok") { done in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
                done(.success(3))
            }
        }
        XCTAssertEqual(result, 3)
    }

    func test_withTimeoutSync_firesOnOverrun() {
        do {
            let _: Int = try withTimeoutSync(seconds: 0.05, operation: "sync-slow") { done in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    done(.success(99))
                }
            }
            XCTFail("expected IOTimeoutError")
        } catch let err as IOTimeoutError {
            XCTAssertEqual(err.operation, "sync-slow")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_withTimeoutSync_propagatesCallbackError() {
        struct SensorFailed: Error {}
        do {
            let _: Int = try withTimeoutSync(seconds: 0.5, operation: "sync-err") { done in
                DispatchQueue.global().async {
                    done(.failure(SensorFailed()))
                }
            }
            XCTFail("expected SensorFailed")
        } catch is SensorFailed {
            // expected
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
