// MARCHTests.swift — Coverage for TCCC MARCH assessment mapping.
//
// The intervention map is safety-critical: a wrong mapping from finding to
// intervention can cost a life in the field. These tests pin each finding's
// indicated interventions to TCCC doctrine.

import XCTest
@testable import ZeroDark

final class MARCHTests: XCTestCase {

    // MARK: - Finding → intervention mapping

    func test_arterialExtremity_mapsToTourniquet() {
        XCTAssertTrue(MARCHFinding.arterialExtremity.indicatedInterventions.contains(.tourniquet))
    }

    func test_junctional_mapsToJunctionalTourniquetAndWoundPacking() {
        let set = Set(MARCHFinding.junctional.indicatedInterventions)
        XCTAssertTrue(set.contains(.junctionalTourniquet))
        XCTAssertTrue(set.contains(.woundPacking))
    }

    func test_tensionPneumo_mapsToNeedleDecompression() {
        XCTAssertEqual(MARCHFinding.tensionPneumo.indicatedInterventions, [.needleDecompression])
    }

    func test_openChest_mapsToVentedChestSeal() {
        XCTAssertTrue(MARCHFinding.openChest.indicatedInterventions.contains(.ventedChestSeal))
    }

    func test_penetratingTorso_includesMonitorTensionPneumo() {
        // A vented chest seal can still tension — monitoring is mandatory.
        let set = Set(MARCHFinding.penetratingTorso.indicatedInterventions)
        XCTAssertTrue(set.contains(.ventedChestSeal))
        XCTAssertTrue(set.contains(.monitorTensionPneumo))
    }

    func test_shock_includesHypothermiaPrevention() {
        // Lethal triad: acidosis, coagulopathy, hypothermia. Warming is required.
        XCTAssertTrue(MARCHFinding.shock.indicatedInterventions.contains(.preventHypothermia))
        XCTAssertTrue(MARCHFinding.shock.indicatedInterventions.contains(.rapidEvac))
    }

    func test_headInjury_headUp30() {
        XCTAssertTrue(MARCHFinding.headInjury.indicatedInterventions.contains(.headUp30))
        XCTAssertTrue(MARCHFinding.headInjury.indicatedInterventions.contains(.monitorGCS))
    }

    func test_everyFinding_hasAtLeastOneIntervention() {
        for finding in MARCHFinding.allCases {
            XCTAssertFalse(finding.indicatedInterventions.isEmpty,
                           "\(finding) has no indicated interventions")
        }
    }

    // MARK: - CasualtyCard round-trip

    func test_casualtyCard_codable_roundtrip() throws {
        var card = CasualtyCard(
            callsign: "TANGO-2",
            unit: "Alpha",
            mechanism: "GSW right thigh",
            findings: [.arterialExtremity, .shock]
        )
        card.interventionsLogged = [
            .init(intervention: .tourniquet, location: "R mid-thigh", performedBy: "MED-1")
        ]
        card.vitals = [
            .init(heartRate: 120, systolicBP: 90, spo2: 94, respirationRate: 22, gcs: 15)
        ]

        let data = try JSONEncoder().encode(card)
        let back = try JSONDecoder().decode(CasualtyCard.self, from: data)

        XCTAssertEqual(back.callsign, "TANGO-2")
        XCTAssertEqual(back.findings, [.arterialExtremity, .shock])
        XCTAssertEqual(back.interventionsLogged.count, 1)
        XCTAssertEqual(back.interventionsLogged.first?.intervention, .tourniquet)
        XCTAssertEqual(back.vitals.first?.heartRate, 120)
    }
}
