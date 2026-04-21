// PureLogicTests.swift — Unit tests for pure-logic modules.
//
// NOTE: As of this commit there is no XCTest target registered in
// ZeroDark.xcodeproj — the existing Tests/MLXEdgeLLMTests/ files are orphaned.
// These tests will run the moment a test target is created with this directory
// as its source root. Adding the target is a follow-up (requires host app
// reference + scheme wiring that touches project settings deeply).
//
// Coverage in this file:
//   - Haversine distance + bearing      (TerrainEngine extension,
//                                        ARWaypointNavigatorView.bearingDeg)
//   - Manning's equation                (CurrentEstimator — conceptual port)
//   - Pareto dominance                  (RouteOptimizer concept)
//   - BM25 / token-overlap grounding    (VerifyPipeline concept)
//   - ISRID probability normalization   (DriftCalculator concept)
//   - MinHeap invariants                (Dijkstra heap — shipped this phase)

import XCTest
import CoreLocation
import simd
@testable import ZeroDark   // Adjust if the module name differs.

final class PureLogicTests: XCTestCase {

    // MARK: - Haversine

    func test_haversineDistance_knownPairs() {
        // Known-good check: SF City Hall → LAX ≈ 559 km great-circle.
        // (Note: SFO airport → LAX is ~543 km; City Hall is ~16 km further
        // north which bumps the arc to ~559 km.)
        let sfCityHall = CLLocationCoordinate2D(latitude: 37.7793, longitude: -122.4192)
        let lax        = CLLocationCoordinate2D(latitude: 33.9416, longitude: -118.4085)
        let d = sfCityHall.distance(to: lax)
        XCTAssertEqual(d, 559_000, accuracy: 5_000,  // ±5 km tolerance
                       "SF City Hall → LAX haversine should be ~559 km")
    }

    func test_haversineDistance_sameCoordinateIsZero() {
        let p = CLLocationCoordinate2D(latitude: 29.7604, longitude: -95.3698)
        XCTAssertEqual(p.distance(to: p), 0, accuracy: 1e-6)
    }

    func test_bearing_dueNorth() {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 1, longitude: 0)
        let brg = ARWaypointNavigatorView.bearingDeg(from: a, to: b)
        XCTAssertEqual(brg, 0, accuracy: 0.5)   // ~0° = due north
    }

    func test_bearing_dueEast() {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 1)
        let brg = ARWaypointNavigatorView.bearingDeg(from: a, to: b)
        XCTAssertEqual(brg, 90, accuracy: 0.5)  // ~90° = due east
    }

    func test_bearing_wrapsIntoPositiveRange() {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: -1)
        let brg = ARWaypointNavigatorView.bearingDeg(from: a, to: b)
        XCTAssertGreaterThanOrEqual(brg, 0)
        XCTAssertLessThan(brg, 360)
        XCTAssertEqual(brg, 270, accuracy: 0.5) // due west
    }

    // MARK: - Manning's equation (conceptual — free function port)

    /// V = (1/n) · R^(2/3) · S^(1/2)   (SI units: R in m, S unitless, V in m/s)
    private func mannings(hydraulicRadius R: Double, slope S: Double, roughness n: Double) -> Double {
        return (1.0 / n) * pow(R, 2.0/3.0) * sqrt(S)
    }

    func test_manning_naturalChannel() {
        // Textbook example: R=1.5 m, S=0.001 (0.1%), n=0.035 (natural streambed)
        // V = 28.57 · 1.31 · 0.0316 = ~1.18 m/s
        let v = mannings(hydraulicRadius: 1.5, slope: 0.001, roughness: 0.035)
        XCTAssertEqual(v, 1.18, accuracy: 0.05)
    }

    func test_manning_concreteLinedChannel() {
        // R=1.0, S=0.002, n=0.013 — smooth concrete. V ≈ 3.44 m/s
        let v = mannings(hydraulicRadius: 1.0, slope: 0.002, roughness: 0.013)
        XCTAssertEqual(v, 3.44, accuracy: 0.1)
    }

    func test_manning_slopeMonotonic() {
        // Higher slope → higher velocity, everything else equal.
        let v1 = mannings(hydraulicRadius: 1.0, slope: 0.001, roughness: 0.03)
        let v2 = mannings(hydraulicRadius: 1.0, slope: 0.010, roughness: 0.03)
        XCTAssertGreaterThan(v2, v1)
    }

    // MARK: - Pareto dominance

    /// Point a dominates b when a ≤ b on every objective AND a < b on at least one.
    private func dominates(_ a: [Double], _ b: [Double]) -> Bool {
        guard a.count == b.count else { return false }
        var strictlyBetter = false
        for i in 0..<a.count {
            if a[i] > b[i] { return false }
            if a[i] < b[i] { strictlyBetter = true }
        }
        return strictlyBetter
    }

    func test_pareto_strictlyBetter() {
        XCTAssertTrue(dominates([1, 2, 3], [2, 3, 4]))
    }

    func test_pareto_tiedOnOneObjective() {
        // a = [1,2,3], b = [1,3,4] — equal on first, strictly better on rest
        XCTAssertTrue(dominates([1, 2, 3], [1, 3, 4]))
    }

    func test_pareto_allEqual_doesNotDominate() {
        XCTAssertFalse(dominates([1, 2, 3], [1, 2, 3]))
    }

    func test_pareto_oneWorse_doesNotDominate() {
        XCTAssertFalse(dominates([1, 2, 5], [1, 3, 4])) // a is worse on last objective
    }

    // MARK: - BM25-style token-overlap grounding

    /// Fraction of sentence tokens (len > 2, not stopwords) that appear in at
    /// least one source string. Ports VerifyPipeline.computeOverlap.
    private func tokenOverlap(sentence: String, sources: [String]) -> Double {
        let stop: Set<String> = ["the", "and", "for", "are", "was", "you"]
        let words = sentence.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stop.contains($0) }
        guard !words.isEmpty else { return 0 }
        var matches = 0
        for w in words where sources.contains(where: { $0.contains(w) }) { matches += 1 }
        return Double(matches) / Double(words.count)
    }

    func test_grounding_fullyCovered() {
        let overlap = tokenOverlap(
            sentence: "Apply tourniquet above the bleeding wound",
            sources:  ["TCCC: apply tourniquet two inches above any arterial bleeding wound"]
        )
        XCTAssertGreaterThan(overlap, 0.7, "Nearly every content word appears in source")
    }

    func test_grounding_noOverlap() {
        let overlap = tokenOverlap(
            sentence: "Brew espresso at 93 degrees Celsius",
            sources:  ["TCCC first aid tourniquet application protocols"]
        )
        XCTAssertLessThan(overlap, 0.2)
    }

    func test_grounding_threshold() {
        // A sentence with exactly half of its words grounded should
        // sit on the 0.4 grounding threshold from VerifyPipeline.
        let overlap = tokenOverlap(
            sentence: "tourniquet wound dispatch sierra",
            sources:  ["apply tourniquet above bleeding wound"]
        )
        XCTAssertGreaterThanOrEqual(overlap, 0.4, "Half-grounded should hit the threshold")
    }

    // MARK: - ISRID probability normalization

    /// After any modification to a probability distribution, re-normalize so the
    /// array sums to 1.0 exactly (within float tolerance). Ports DriftCalculator.
    private func renormalize(_ probs: [Double]) -> [Double] {
        let total = probs.reduce(0, +)
        guard total > 0 else { return probs }
        return probs.map { $0 / total }
    }

    func test_isrid_jitterThenNormalize_sumsToOne() {
        // Start with a uniform 8-sector distribution, perturb it, renormalize.
        var probs = Array(repeating: 1.0 / 8.0, count: 8)
        for i in 0..<probs.count {
            probs[i] = max(0, probs[i] + Double.random(in: -0.05...0.05))
        }
        let normalized = renormalize(probs)
        let sum = normalized.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 1e-10)
    }

    func test_isrid_allZero_isSafeToDivide() {
        let normalized = renormalize([0, 0, 0, 0])
        XCTAssertEqual(normalized, [0, 0, 0, 0])   // no NaNs / infs
    }

    // MARK: - MinHeap invariants

    func test_minHeap_popReturnsAscending() {
        var h = MinHeap<Int>()
        [5, 2, 9, 1, 7, 3, 8].forEach { h.push($0) }
        var popped: [Int] = []
        while let v = h.pop() { popped.append(v) }
        XCTAssertEqual(popped, [1, 2, 3, 5, 7, 8, 9])
    }

    func test_minHeap_emptyPop() {
        var h = MinHeap<Int>()
        XCTAssertNil(h.pop())
        XCTAssertTrue(h.isEmpty)
    }

    func test_minHeap_pushPopInterleaved() {
        var h = MinHeap<Int>()
        h.push(10)
        h.push(5)
        XCTAssertEqual(h.pop(), 5)
        h.push(1)
        h.push(7)
        XCTAssertEqual(h.pop(), 1)
        XCTAssertEqual(h.pop(), 7)
        XCTAssertEqual(h.pop(), 10)
    }

    func test_minHeap_peekDoesNotConsume() {
        var h = MinHeap<Int>()
        h.push(3)
        h.push(1)
        h.push(2)
        XCTAssertEqual(h.peek, 1)
        XCTAssertEqual(h.count, 3)
    }
}
