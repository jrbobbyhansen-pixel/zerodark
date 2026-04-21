// TrenchRescue.swift — OSHA-based trench rescue planner (Type A/B/C soil).
//
// Previously orphaned. Implements real OSHA 1926 Subpart P Appendix A soil
// classification + shoring / sloping requirements (29 CFR 1926.652). The
// operator enters observed soil indicators; the tool classifies the trench
// Type A / B / C / unclassified, emits required slope angle + shoring spec,
// and computes a safety exclusion zone whose radius scales with trench depth.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - OSHA soil classification

enum OSHASoilType: String, CaseIterable {
    case typeA = "Type A"           // Cohesive — clay, silty clay, etc. Best.
    case typeB = "Type B"           // Cohesive less stable — silt, loam
    case typeC = "Type C"           // Granular — gravel, sand, submerged, unstable
    case unclassified = "Unclassified" // Default to Type C requirements

    /// Allowable slope ratio H:V for benching per 29 CFR 1926.652 App B.
    var maxSlopeHtoV: Double {
        switch self {
        case .typeA:         return 0.75   // ¾:1 (53°)
        case .typeB:         return 1.0    // 1:1 (45°)
        case .typeC:         return 1.5    // 1½:1 (34°)
        case .unclassified:  return 1.5
        }
    }

    /// Shoring system required for trenches >5 ft deep.
    var shoringSpec: String {
        switch self {
        case .typeA:
            return "Timber uprights 3×8 min, 4 ft on-center, horizontal crossbraces 4×6"
        case .typeB:
            return "Timber uprights 3×12 min, 4 ft on-center, crossbraces 6×6, or aluminum trench box"
        case .typeC:
            return "Hydraulic shoring, trench shield, or sloping only. Timber not permitted alone."
        case .unclassified:
            return "Treat as Type C: hydraulic shoring or trench shield required"
        }
    }

    /// Typical field indicators that suggest this type.
    var indicators: [String] {
        switch self {
        case .typeA:
            return ["Unfissured cohesive soil", "Clay-rich, holds vertical walls",
                    "Dry, no seepage", "Not previously disturbed"]
        case .typeB:
            return ["Fissured cohesive soil", "Silty loam", "Previously disturbed",
                    "Slight moisture but not saturated"]
        case .typeC:
            return ["Granular — sand / gravel", "Saturated / submerged / seeping",
                    "Previously excavated", "Adjacent to water table"]
        case .unclassified:
            return ["Not yet identified — default to Type C for safety"]
        }
    }
}

// MARK: - Shoring requirements

struct ShoringRequirements {
    let soilType: OSHASoilType
    let trenchDepthM: Double
    let trenchWidthM: Double
    let shoringRequired: Bool
    let shoringSpec: String
    let alternativeSlopeAngleDeg: Double  // sloping alternative to shoring
    let totalWidthWithSlopingM: Double    // surface footprint if sloped instead

    init(soil: OSHASoilType, depthM: Double, widthM: Double) {
        self.soilType = soil
        self.trenchDepthM = depthM
        self.trenchWidthM = widthM
        self.shoringRequired = depthM >= 1.52  // OSHA 5 ft threshold
        self.shoringSpec = soil.shoringSpec
        let htov = soil.maxSlopeHtoV
        self.alternativeSlopeAngleDeg = atan(1.0 / htov) * 180 / .pi
        self.totalWidthWithSlopingM = widthM + 2 * depthM * htov
    }
}

// MARK: - Rescue plan

enum RescueApproach: String, CaseIterable {
    case vertical    // victim accessed from above (standard)
    case horizontal  // side-entry through trench box
    case diagonal    // sloped-wall descent
}

struct TrenchRescuePlan {
    let approach: RescueApproach
    let exclusionRadiusM: Double
    let safetyZone: MKPolygon
}

// MARK: - Safety zone

final class SafetyZoneManager: ObservableObject {
    @Published var safetyZone: MKPolygon?

    /// Circular (octagon-approx) exclusion zone centered on `center` with
    /// a radius scaled to trench depth (OSHA: spoil pile + equipment min 2 ft
    /// from edge; full exclusion ~2× depth for rescue operations).
    func createSafetyZone(center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance) {
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(center.latitude * .pi / 180)

        var coords: [CLLocationCoordinate2D] = []
        let steps = 16
        for i in 0..<steps {
            let angle = Double(i) / Double(steps) * 2 * .pi
            let dxM = cos(angle) * radiusMeters
            let dyM = sin(angle) * radiusMeters
            coords.append(.init(
                latitude:  center.latitude  + dyM / metersPerDegLat,
                longitude: center.longitude + dxM / metersPerDegLon
            ))
        }
        safetyZone = MKPolygon(coordinates: coords, count: coords.count)
    }
}

// MARK: - ViewModel

@MainActor
final class TrenchRescueViewModel: ObservableObject {
    @Published var trenchCenter: CLLocationCoordinate2D = .init(latitude: 37.7749, longitude: -122.4194)
    @Published var trenchDepthM: Double = 2.4        // typical utility trench
    @Published var trenchWidthM: Double = 1.2
    @Published var soilIndicators: Set<String> = []
    @Published var selectedSoilType: OSHASoilType = .unclassified
    @Published var shoringRequirements: ShoringRequirements?
    @Published var rescuePlan: TrenchRescuePlan?
    @Published var safetyZoneManager = SafetyZoneManager()

    /// Bucketed classification from indicator checklist. Conservative:
    /// any Type C indicator downgrades the classification.
    func classifySoil() {
        let cIndicators = Set(OSHASoilType.typeC.indicators)
        let bIndicators = Set(OSHASoilType.typeB.indicators)
        if !soilIndicators.intersection(cIndicators).isEmpty {
            selectedSoilType = .typeC
        } else if !soilIndicators.intersection(bIndicators).isEmpty {
            selectedSoilType = .typeB
        } else if !soilIndicators.isEmpty {
            selectedSoilType = .typeA
        } else {
            selectedSoilType = .unclassified
        }
    }

    func buildPlan() {
        classifySoil()
        shoringRequirements = ShoringRequirements(
            soil: selectedSoilType,
            depthM: trenchDepthM,
            widthM: trenchWidthM
        )

        // Exclusion radius: 2 m minimum, scales to ~2× depth for rescue
        let radius = max(2.0, 2.0 * trenchDepthM)
        safetyZoneManager.createSafetyZone(center: trenchCenter, radiusMeters: radius)

        let approach: RescueApproach
        if selectedSoilType == .typeC { approach = .horizontal }  // trench box mandatory
        else if trenchDepthM >= 3.0 { approach = .diagonal }      // deep = slope preferred
        else { approach = .vertical }

        rescuePlan = TrenchRescuePlan(
            approach: approach,
            exclusionRadiusM: radius,
            safetyZone: safetyZoneManager.safetyZone
                ?? MKPolygon(coordinates: [trenchCenter], count: 1)
        )
    }
}

// MARK: - View

struct TrenchRescueView: View {
    @StateObject private var vm = TrenchRescueViewModel()

    var body: some View {
        Form {
            Section("Trench") {
                Stepper(value: $vm.trenchDepthM, in: 0.5...6.0, step: 0.3) {
                    HStack {
                        Text("Depth")
                        Spacer()
                        Text(String(format: "%.1f m (%.1f ft)", vm.trenchDepthM, vm.trenchDepthM * 3.281))
                            .foregroundColor(.secondary)
                    }
                }
                Stepper(value: $vm.trenchWidthM, in: 0.3...3.0, step: 0.1) {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text(String(format: "%.1f m", vm.trenchWidthM))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Soil Indicators (select all that apply)") {
                ForEach(OSHASoilType.allCases.filter { $0 != .unclassified }, id: \.self) { t in
                    DisclosureGroup(t.rawValue) {
                        ForEach(t.indicators, id: \.self) { ind in
                            Toggle(ind, isOn: Binding(
                                get: { vm.soilIndicators.contains(ind) },
                                set: { on in
                                    if on { vm.soilIndicators.insert(ind) }
                                    else  { vm.soilIndicators.remove(ind) }
                                }
                            ))
                            .font(.caption)
                        }
                    }
                }
            }

            Section {
                Button("Generate Rescue Plan") { vm.buildPlan() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }

            if let req = vm.shoringRequirements {
                Section("Classification") {
                    LabeledContent("Soil Type", value: req.soilType.rawValue)
                    LabeledContent("Shoring required", value: req.shoringRequired ? "YES (depth ≥ 5 ft)" : "No")
                    Text(req.shoringSpec).font(.caption).foregroundColor(.secondary)
                }
                Section("Sloping alternative") {
                    LabeledContent("Slope angle", value: String(format: "%.0f° from horizontal", req.alternativeSlopeAngleDeg))
                    LabeledContent("Surface footprint", value: String(format: "%.1f m wide", req.totalWidthWithSlopingM))
                }
            }

            if let plan = vm.rescuePlan {
                Section("Rescue Plan") {
                    LabeledContent("Approach", value: plan.approach.rawValue.capitalized)
                    LabeledContent("Exclusion radius", value: String(format: "%.1f m", plan.exclusionRadiusM))
                    Text("Clear all non-essential personnel + equipment from within the exclusion zone. No spoil-pile material within 2 ft of edge.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Trench Rescue")
    }
}
