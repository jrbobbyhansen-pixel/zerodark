// ThreatClassifierTests.swift — Coverage for PR-A4 threshold + suppress list.
//
// classify() requires the Phi-3.5 inference engine (downloaded at runtime)
// which isn't available in unit-test environment. These tests exercise the
// pure logic around thresholds and the suppress-list lifecycle — the parts
// that make a wrong LLM answer either visible or filtered to the operator.

import XCTest
@testable import ZeroDark

@MainActor
final class ThreatClassifierTests: XCTestCase {

    func test_setThreshold_updatesValue() {
        ThreatClassifier.shared.setThreshold(0.8, for: "explosive")
        XCTAssertEqual(ThreatClassifier.shared.thresholds["explosive"], 0.8)
    }

    func test_setThreshold_clampsBelowZero() {
        ThreatClassifier.shared.setThreshold(-0.5, for: "personnel")
        XCTAssertEqual(ThreatClassifier.shared.thresholds["personnel"], 0.0)
    }

    func test_setThreshold_clampsAboveOne() {
        ThreatClassifier.shared.setThreshold(2.5, for: "personnel")
        XCTAssertEqual(ThreatClassifier.shared.thresholds["personnel"], 1.0)
    }

    func test_defaultThresholds_sanity() {
        // CBRN categories should be more sensitive (lower threshold) than
        // ordinary personnel sightings.
        let explosive = ThreatClassifier.shared.thresholds["explosive"] ?? 1.0
        let chem      = ThreatClassifier.shared.thresholds["chemical"]  ?? 1.0
        let none      = ThreatClassifier.shared.thresholds["none"]      ?? 0.0

        XCTAssertLessThanOrEqual(chem, 0.6, "chem threshold should be sensitive")
        XCTAssertGreaterThanOrEqual(none, 0.9, "'none' threshold should be strict (never surface)")
        XCTAssertLessThanOrEqual(explosive, 0.8)
    }

    func test_markFalsePositive_addsSuppression() {
        let report = ThreatReport(source: "test", text: "branch hanging over road",
                                  category: "personnel", confidence: 0.75, location: nil)
        // Ensure report is in the store so markFalsePositive can find it.
        ThreatClassifier.shared.reports.append(report)
        let before = ThreatClassifier.shared.suppressedSignatures.count
        ThreatClassifier.shared.markFalsePositive(report)
        XCTAssertEqual(ThreatClassifier.shared.suppressedSignatures.count, before + 1)
        let last = ThreatClassifier.shared.suppressedSignatures.last
        XCTAssertEqual(last?.category, "personnel")
    }

    func test_markFalsePositive_marksReportResolved() {
        let report = ThreatReport(source: "test", text: "dog barking",
                                  category: "personnel", confidence: 0.55, location: nil)
        ThreatClassifier.shared.reports.append(report)
        ThreatClassifier.shared.markFalsePositive(report)
        let stored = ThreatClassifier.shared.reports.first(where: { $0.id == report.id })
        XCTAssertEqual(stored?.resolved, true)
        XCTAssertNotNil(stored?.resolution)
    }

    func test_unsuppress_removesEntry() {
        let report = ThreatReport(source: "test", text: "branch scraping window",
                                  category: "personnel", confidence: 0.7, location: nil)
        ThreatClassifier.shared.reports.append(report)
        ThreatClassifier.shared.markFalsePositive(report)
        guard let entry = ThreatClassifier.shared.suppressedSignatures.last else {
            return XCTFail("expected suppression entry")
        }
        let before = ThreatClassifier.shared.suppressedSignatures.count
        ThreatClassifier.shared.unsuppress(entry)
        XCTAssertEqual(ThreatClassifier.shared.suppressedSignatures.count, before - 1)
    }

    func test_unresolvedCount_ignoresResolved() {
        let r1 = ThreatReport(source: "a", text: "x", category: "explosive", confidence: 0.9)
        var r2 = ThreatReport(source: "b", text: "y", category: "personnel", confidence: 0.9)
        r2.resolved = true
        ThreatClassifier.shared.reports = [r1, r2]
        XCTAssertEqual(ThreatClassifier.shared.unresolvedCount, 1)
    }
}
