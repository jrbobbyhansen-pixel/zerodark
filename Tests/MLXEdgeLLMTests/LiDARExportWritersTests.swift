// LiDARExportWritersTests.swift — Coverage for the PR-B7 extraction.
//
// savePointsBinary is the only writer exercised in unit tests — USDZ
// needs real ARMeshAnchor objects (ARKit-bound) that aren't available
// in a simulator unit test. The point-cloud binary writer IS testable:
// we round-trip through a temporary file and verify the header count +
// each SIMD3<Float> position matches.

import XCTest
import simd
@testable import ZeroDark

final class LiDARExportWritersTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ply_writer_\(UUID().uuidString).bin")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func test_empty_points_produceNoFile() async throws {
        try await LiDARExportWriters.savePointsBinary([], to: tempURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "empty input should be a no-op")
    }

    /// Read one 12-byte point (three little-endian Float32) at the given
    /// offset into `data`. We can't `load(as: SIMD3<Float>.self)` because
    /// SIMD3 has a 16-byte stride but the writer emits packed 12-byte
    /// triplets.
    private func readPackedPoint(_ data: Data, at offset: Int) -> SIMD3<Float> {
        let x = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: Float.self) }
        let y = data.subdata(in: offset+4..<offset+8).withUnsafeBytes { $0.load(as: Float.self) }
        let z = data.subdata(in: offset+8..<offset+12).withUnsafeBytes { $0.load(as: Float.self) }
        return .init(x, y, z)
    }

    func test_singlePoint_roundTrip() async throws {
        let pts: [SIMD3<Float>] = [.init(1, 2, 3)]
        try await LiDARExportWriters.savePointsBinary(pts, to: tempURL)
        let data = try Data(contentsOf: tempURL)
        XCTAssertEqual(data.count, 4 + 12)
        let header = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(header, 1)
        let pt = readPackedPoint(data, at: 4)
        XCTAssertEqual(pt.x, 1)
        XCTAssertEqual(pt.y, 2)
        XCTAssertEqual(pt.z, 3)
    }

    func test_multiplePoints_roundTrip() async throws {
        let pts: [SIMD3<Float>] = (0..<100).map { i in
            .init(Float(i), Float(-i), Float(i * 2))
        }
        try await LiDARExportWriters.savePointsBinary(pts, to: tempURL)
        let data = try Data(contentsOf: tempURL)
        XCTAssertEqual(data.count, 4 + 100 * 12)
        let header = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(header, 100)

        // Spot-check first and last points.
        let first = readPackedPoint(data, at: 4)
        let last  = readPackedPoint(data, at: 4 + 99 * 12)
        XCTAssertEqual(first, .init(0, 0, 0))
        XCTAssertEqual(last,  .init(99, -99, 198))
    }

    func test_chunkBoundary_roundTrip() async throws {
        // Writer chunks at 85_000 — use 90_000 points to exercise the
        // chunk-boundary path at least once.
        let pts: [SIMD3<Float>] = (0..<90_000).map { i in
            .init(Float(i), 0, 0)
        }
        try await LiDARExportWriters.savePointsBinary(pts, to: tempURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertEqual(size, 4 + 90_000 * 12)
    }
}
