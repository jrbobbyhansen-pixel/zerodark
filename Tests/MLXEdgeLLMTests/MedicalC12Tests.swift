// MedicalC12Tests.swift — Coverage for PR-C12 medical upgrades.

import XCTest
@testable import ZeroDark

@MainActor
final class BurnCalculatorInhalationTests: XCTestCase {

    func test_inhalationInjury_increasesFluidByFortyPercent() {
        let calc = BurnCalculator()
        calc.calculateRuleOfNines(burnArea: 20, weight: 70)
        let baseTotal = calc.fluidTotal
        XCTAssertEqual(baseTotal, 4.0 * 70 * 20, accuracy: 1)

        // Same input with inhalation-injury toggle on.
        calc.inhalationInjury = true
        calc.calculateRuleOfNines(burnArea: 20, weight: 70)
        XCTAssertEqual(calc.fluidTotal, baseTotal * 1.4, accuracy: 1)
    }

    func test_inhalationInjury_affectsParklandRates() {
        let calc = BurnCalculator()
        calc.inhalationInjury = true
        calc.calculateRuleOfNines(burnArea: 30, weight: 80)
        XCTAssertEqual(calc.fluidTotal, 4.0 * 80 * 30 * 1.4, accuracy: 1)
        // First-8-hour rate = total / 2 / 8
        XCTAssertEqual(calc.fluidRateFirst8, calc.fluidTotal / 16, accuracy: 1)
        // Next-16-hour rate = total / 2 / 16
        XCTAssertEqual(calc.fluidRateNext16, calc.fluidTotal / 32, accuracy: 1)
    }

    func test_offByDefault() {
        let calc = BurnCalculator()
        XCTAssertFalse(calc.inhalationInjury)
    }
}

// NOTE: HypothermiaCalc.swift is currently not registered in the
// ZeroDark app target's Compile Sources build phase — it's an orphan
// file on disk. The PR-C12 rewarming upgrades in that file are
// therefore not visible to @testable imports. Tests are deferred until
// the file is registered (same follow-up issue as NavLogStore).
