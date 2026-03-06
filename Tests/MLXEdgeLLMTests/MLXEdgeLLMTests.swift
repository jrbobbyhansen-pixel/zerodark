import XCTest
@testable import MLXEdgeLLM

final class MLXEdgeLLMTests: XCTestCase {
    func testTextModelEnum() {
        XCTAssertEqual(TextModel.default, .qwen3_1_7b)
        XCTAssertFalse(TextModel.allCases.isEmpty)
    }

    func testVisionModelEnum() {
        XCTAssertEqual(VisionModel.default, .qwen35_0_8b)
        XCTAssertFalse(VisionModel.allCases.isEmpty)
    }

    func testModelSizes() {
        XCTAssertGreaterThan(VisionModel.qwen35_0_8b.approximateSizeMB, 0)
        XCTAssertGreaterThan(TextModel.qwen3_1_7b.approximateSizeMB, 0)
    }
}
