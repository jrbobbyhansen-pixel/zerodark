// IntegrationHealthMonitorTests.swift — Coverage for PR-B5 health monitor.
//
// Does not hit the network. Uses synthetic probe closures to drive the
// state machine deterministically.

import XCTest
@testable import ZeroDark

@MainActor
final class IntegrationHealthMonitorTests: XCTestCase {

    override func setUp() async throws {
        IntegrationHealthMonitor.shared._resetForTesting()
    }

    override func tearDown() async throws {
        IntegrationHealthMonitor.shared._resetForTesting()
    }

    func test_initialState_allUnknown() {
        let monitor = IntegrationHealthMonitor.shared
        for service in IntegrationService.allCases {
            XCTAssertEqual(monitor.health(for: service).status, .unknown)
        }
    }

    func test_probeNow_success_marksHealthy() async {
        let monitor = IntegrationHealthMonitor.shared
        monitor.register(.srtm) {
            // immediate success
            return
        }
        await monitor.probeNow(.srtm)
        let h = monitor.health(for: .srtm)
        XCTAssertEqual(h.status, .healthy)
        XCTAssertNotNil(h.lastSuccess)
        XCTAssertEqual(h.consecutiveFailures, 0)
    }

    func test_probeNow_failure_marksUnreachable() async {
        let monitor = IntegrationHealthMonitor.shared
        struct ProbeFailed: Error {}
        monitor.register(.weather) {
            throw ProbeFailed()
        }
        await monitor.probeNow(.weather)
        let h = monitor.health(for: .weather)
        XCTAssertEqual(h.status, .unreachable)
        XCTAssertNotNil(h.lastFailure)
        XCTAssertEqual(h.consecutiveFailures, 1)
    }

    func test_failure_thenSuccess_clearsFailureCount() async {
        let monitor = IntegrationHealthMonitor.shared
        struct FlakyError: Error {}
        let flag = ProbeFlag()

        monitor.register(.tak) {
            if await flag.shouldFail {
                throw FlakyError()
            }
        }

        await flag.setFailing(true)
        await monitor.probeNow(.tak)
        XCTAssertEqual(monitor.health(for: .tak).consecutiveFailures, 1)
        XCTAssertEqual(monitor.health(for: .tak).status, .unreachable)

        await flag.setFailing(false)
        await monitor.probeNow(.tak)
        XCTAssertEqual(monitor.health(for: .tak).consecutiveFailures, 0)
        XCTAssertEqual(monitor.health(for: .tak).status, .healthy)
    }

    func test_overallStatus_reflectsWorstChild() async {
        let monitor = IntegrationHealthMonitor.shared

        monitor.register(.srtm)    { /* ok */ }
        monitor.register(.weather) { /* ok */ }
        struct Down: Error {}
        monitor.register(.tak)     { throw Down() }

        await monitor.probeNow(.srtm)
        await monitor.probeNow(.weather)
        await monitor.probeNow(.tak)

        XCTAssertEqual(monitor.overallStatus, .unreachable)
    }

    func test_slowProbe_markedDegraded() async {
        let monitor = IntegrationHealthMonitor.shared
        monitor.register(.srtm) {
            // 3.1s latency trips the degraded threshold.
            try? await Task.sleep(nanoseconds: 3_100_000_000)
        }
        await monitor.probeNow(.srtm)
        XCTAssertEqual(monitor.health(for: .srtm).status, .degraded)
    }
}

private actor ProbeFlag {
    var shouldFail: Bool = false
    func setFailing(_ value: Bool) { shouldFail = value }
}
