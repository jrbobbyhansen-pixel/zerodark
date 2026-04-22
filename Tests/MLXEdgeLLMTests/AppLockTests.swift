// AppLockTests.swift — Coverage for PR-B4 hardening.
//
// Exercises PIN validation policy (min length, trivial-sequence rejection)
// and the lockout ladder behavior via the manager's publicly-visible state.
// Does NOT touch the Keychain — enrollment/submission are covered by UI.

import XCTest
@testable import ZeroDark

@MainActor
final class AppLockPinPolicyTests: XCTestCase {

    // Minimum length enforced.
    func test_rejects_pin_shorterThanMin() {
        XCTAssertFalse(AppLockManager.isAcceptablePin("12345"))
    }

    func test_accepts_pin_atMinLength() {
        // 6 digits, not trivial
        XCTAssertTrue(AppLockManager.isAcceptablePin("173946"))
    }

    func test_rejects_pin_longerThanMax() {
        let tooLong = String(repeating: "1", count: AppLockManager.maxPinLength + 1)
        XCTAssertFalse(AppLockManager.isAcceptablePin(tooLong))
    }

    func test_rejects_nonNumeric() {
        XCTAssertFalse(AppLockManager.isAcceptablePin("abcdef"))
        XCTAssertFalse(AppLockManager.isAcceptablePin("1a2b3c4d"))
    }

    func test_rejects_allSameDigit() {
        XCTAssertFalse(AppLockManager.isAcceptablePin("000000"))
        XCTAssertFalse(AppLockManager.isAcceptablePin("999999"))
    }

    func test_rejects_ascendingSequence() {
        XCTAssertFalse(AppLockManager.isAcceptablePin("123456"))
        XCTAssertFalse(AppLockManager.isAcceptablePin("234567"))
    }

    func test_rejects_descendingSequence() {
        XCTAssertFalse(AppLockManager.isAcceptablePin("654321"))
        XCTAssertFalse(AppLockManager.isAcceptablePin("987654"))
    }

    func test_accepts_nonTrivialPin() {
        XCTAssertTrue(AppLockManager.isAcceptablePin("849213"))
        XCTAssertTrue(AppLockManager.isAcceptablePin("71539264"))
    }
}

@MainActor
final class AppLockLockoutTests: XCTestCase {

    override func setUp() async throws {
        AppLockManager.shared._clearLockoutForTesting()
    }

    override func tearDown() async throws {
        AppLockManager.shared._clearLockoutForTesting()
    }

    func test_initialState_noLockout() {
        XCTAssertEqual(AppLockManager.shared.consecutiveFailures, 0)
        XCTAssertNil(AppLockManager.shared.lockoutUntil)
        XCTAssertEqual(AppLockManager.shared.lockoutSecondsRemaining, 0)
    }

    func test_submitPin_whenNoPinEnrolled_returnsMismatchAndIncrements() async {
        // With no PIN enrolled, any submission is mismatch — but the manager
        // should still increment the failure counter.
        let before = AppLockManager.shared.consecutiveFailures
        let result = await AppLockManager.shared.submitPin("999999")
        XCTAssertEqual(result, .mismatch)
        XCTAssertGreaterThan(AppLockManager.shared.consecutiveFailures, before)
    }

    func test_lockout_triggersAfterFiveFailures() async {
        for _ in 0..<5 {
            _ = await AppLockManager.shared.submitPin("999999")
        }
        XCTAssertNotNil(AppLockManager.shared.lockoutUntil)
        XCTAssertGreaterThanOrEqual(AppLockManager.shared.lockoutSecondsRemaining, 1)
    }

    func test_lockoutEscalates_beyondLadderThresholds() async {
        for _ in 0..<8 {
            _ = await AppLockManager.shared.submitPin("999999")
        }
        // After 8 fails, lockout is the 5-minute step (300 s); allow some slack.
        XCTAssertGreaterThanOrEqual(AppLockManager.shared.lockoutSecondsRemaining, 60)
    }

    func test_submitDuringLockout_isRejected() async {
        for _ in 0..<5 {
            _ = await AppLockManager.shared.submitPin("999999")
        }
        let remainingAtStart = AppLockManager.shared.lockoutSecondsRemaining
        XCTAssertGreaterThan(remainingAtStart, 0)
        // Now try again — it should not reset or advance beyond what the ladder did.
        let result = await AppLockManager.shared.submitPin("999999")
        XCTAssertEqual(result, .mismatch)
        XCTAssertGreaterThan(AppLockManager.shared.lockoutSecondsRemaining, 0)
    }
}
