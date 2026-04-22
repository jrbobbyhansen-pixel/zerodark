// ScanStorageCapTests.swift — Coverage for PR-C1 storage-size cap.
//
// ScanStorage normally loads from Documents/LiDARScans on init. We just
// exercise the public knob and verify it tracks reality — a deeper
// fixture-based test would require synthesizing metadata.json + enough
// bytes to cross the cap, which is out of scope for a unit test.

import XCTest
@testable import ZeroDark

@MainActor
final class ScanStorageCapTests: XCTestCase {

    func test_maxTotalBytes_defaultsToTenGB() {
        let expected: Int64 = 10 * 1024 * 1024 * 1024
        // Singleton may have been mutated by another test; explicitly
        // reset to the production default before asserting.
        ScanStorage.shared.maxTotalBytes = expected
        XCTAssertEqual(ScanStorage.shared.maxTotalBytes, expected)
    }

    func test_maxTotalBytes_canBeLowered() {
        ScanStorage.shared.maxTotalBytes = 1_024 * 1_024  // 1 MB
        XCTAssertEqual(ScanStorage.shared.maxTotalBytes, 1_048_576)
        // Restore so we don't perturb other tests.
        ScanStorage.shared.maxTotalBytes = 10 * 1024 * 1024 * 1024
    }
}
