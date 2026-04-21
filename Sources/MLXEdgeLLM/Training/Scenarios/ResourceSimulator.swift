// ResourceSimulator.swift — Training: operational capability under resource constraints.
//
// Previous impl: print("Adapting to resource constraints...") — no data.
// Now models equipment failures, personnel injuries, and supply shortages each
// with a weighted operational impact, computes a live capability percentage,
// and emits concrete adaptation recommendations (task reassignment, substitute
// equipment, resupply priority, mission stand-down if below threshold).

import Foundation
import SwiftUI

// MARK: - Events

struct EquipmentFailure: Identifiable, Hashable {
    let id = UUID()
    let equipment: String
    let category: Category
    let impact: Double      // 0–1 fraction of capability loss
    let timestamp: Date = .init()

    enum Category: String { case radio, weapon, navigation, medical, optics, power, other }
}

struct PersonnelInjury: Identifiable, Hashable {
    let id = UUID()
    let personnel: String
    let severity: Severity
    let role: String
    let timestamp: Date = .init()

    enum Severity: String { case minor, moderate, major }
    var capabilityLoss: Double {
        switch severity {
        case .minor:    return 0.05
        case .moderate: return 0.25
        case .major:    return 0.60
        }
    }
}

struct SupplyShortage: Identifiable, Hashable {
    let id = UUID()
    let supply: String
    let criticality: Criticality
    let remainingHours: Double
    let timestamp: Date = .init()

    enum Criticality: String { case nonCritical, important, mission }
    var capabilityLoss: Double {
        switch criticality {
        case .nonCritical: return 0.02
        case .important:   return 0.15
        case .mission:     return 0.50
        }
    }
}

// MARK: - Recommendation

struct ResourceAdaptation: Identifiable {
    let id = UUID()
    let action: String
    let priority: Priority
    let reasoning: String
    enum Priority: String, Comparable {
        case p1 = "IMMEDIATE", p2 = "HIGH", p3 = "MEDIUM", p4 = "LOW"
        static func < (a: Priority, b: Priority) -> Bool {
            let order: [Priority] = [.p1, .p2, .p3, .p4]
            return order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }
    }
}

// MARK: - Simulator

@MainActor
final class ResourceSimulator: ObservableObject {
    @Published var equipmentFailures: [EquipmentFailure] = []
    @Published var personnelInjuries: [PersonnelInjury] = []
    @Published var supplyShortages: [SupplyShortage] = []

    /// Threshold below which a mission stand-down is recommended.
    var standDownThreshold: Double = 0.50

    /// Operational capability 0–1. 1.0 = fully mission-capable.
    var capability: Double {
        let equipLoss    = equipmentFailures.reduce(0) { $0 + $1.impact }
        let injuryLoss   = personnelInjuries.reduce(0) { $0 + $1.capabilityLoss }
        let shortageLoss = supplyShortages.reduce(0) { $0 + $1.capabilityLoss }
        let total = equipLoss + injuryLoss + shortageLoss
        return max(0, 1 - min(1, total))
    }

    // MARK: Record events

    func simulateEquipmentFailure(_ equipment: String, category: EquipmentFailure.Category = .other, impact: Double = 0.1) {
        equipmentFailures.append(.init(equipment: equipment, category: category, impact: impact))
    }

    func simulatePersonnelInjury(_ personnel: String, severity: PersonnelInjury.Severity = .moderate, role: String = "Operator") {
        personnelInjuries.append(.init(personnel: personnel, severity: severity, role: role))
    }

    func simulateSupplyShortage(_ supply: String, criticality: SupplyShortage.Criticality = .important, remainingHours: Double = 6) {
        supplyShortages.append(.init(supply: supply, criticality: criticality, remainingHours: remainingHours))
    }

    func reset() {
        equipmentFailures.removeAll()
        personnelInjuries.removeAll()
        supplyShortages.removeAll()
    }

    // MARK: Adaptation logic

    /// Produce ordered adaptation recommendations for the current event set.
    func adaptations() -> [ResourceAdaptation] {
        var out: [ResourceAdaptation] = []

        // Stand-down recommendation if capability is below threshold
        if capability < standDownThreshold {
            out.append(.init(
                action: "RECOMMEND STAND-DOWN: consolidate at primary rally, request relief",
                priority: .p1,
                reasoning: String(format: "Operational capability %.0f%% < %.0f%% threshold",
                                  capability * 100, standDownThreshold * 100)
            ))
        }

        // Major equipment losses → redundancy / substitution
        for f in equipmentFailures where f.impact >= 0.15 {
            switch f.category {
            case .radio:      out.append(.init(action: "Fail-over to backup mesh channel; shift to HF/LoRa",
                                               priority: .p1, reasoning: "Primary radio \(f.equipment) down"))
            case .weapon:     out.append(.init(action: "Reassign affected element to secondary fires role",
                                               priority: .p2, reasoning: "\(f.equipment) offline"))
            case .navigation: out.append(.init(action: "Switch to celestial/breadcrumb nav; verify via mesh peers",
                                               priority: .p2, reasoning: "\(f.equipment) offline"))
            case .medical:    out.append(.init(action: "Consolidate medical supplies to senior medic; re-evacuate plan",
                                               priority: .p1, reasoning: "\(f.equipment) offline"))
            case .optics:     out.append(.init(action: "Reduce standoff distance; increase observation rotation",
                                               priority: .p3, reasoning: "\(f.equipment) offline"))
            case .power:      out.append(.init(action: "Power-save mode, reduce LiDAR/video, ration charging",
                                               priority: .p2, reasoning: "\(f.equipment) offline"))
            case .other:      out.append(.init(action: "Adjust task assignments for \(f.equipment) loss",
                                               priority: .p3, reasoning: "Equipment degraded"))
            }
        }

        // Major injuries → evac / role reassignment
        for inj in personnelInjuries where inj.severity != .minor {
            let action = inj.severity == .major
                ? "Priority CASEVAC for \(inj.personnel); redistribute \(inj.role) duties"
                : "Reduced-duty for \(inj.personnel); monitor deterioration"
            let pri: ResourceAdaptation.Priority = inj.severity == .major ? .p1 : .p2
            out.append(.init(action: action, priority: pri,
                             reasoning: "Personnel injury (\(inj.severity.rawValue))"))
        }

        // Supply shortages — resupply priority
        for s in supplyShortages where s.criticality != .nonCritical {
            let action = s.criticality == .mission
                ? "REQUEST RESUPPLY IMMEDIATELY: \(s.supply) (\(String(format: "%.1f", s.remainingHours)) hr remaining)"
                : "Schedule resupply: \(s.supply) within \(Int(s.remainingHours)) hr"
            let pri: ResourceAdaptation.Priority = s.criticality == .mission ? .p1 : .p3
            out.append(.init(action: action, priority: pri,
                             reasoning: "Supply shortage (\(s.criticality.rawValue))"))
        }

        // If no issues, confirm posture
        if out.isEmpty {
            out.append(.init(action: "No adaptations needed — posture nominal",
                             priority: .p4,
                             reasoning: String(format: "Capability %.0f%%", capability * 100)))
        }

        return out.sorted { $0.priority < $1.priority }
    }
}

// MARK: - View

struct ResourceSimulatorView: View {
    @StateObject private var sim = ResourceSimulator()

    var body: some View {
        List {
            Section("Capability") {
                capabilityBar
            }

            Section("Equipment Failures") {
                if sim.equipmentFailures.isEmpty {
                    Text("—").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(sim.equipmentFailures) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.equipment).font(.subheadline)
                            Text("\(f.category.rawValue) · \(Int(f.impact * 100))% capability loss")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                Button("Simulate — Primary Radio Down") {
                    sim.simulateEquipmentFailure("Primary Radio (PRC-148)", category: .radio, impact: 0.25)
                }
            }

            Section("Personnel Injuries") {
                if sim.personnelInjuries.isEmpty {
                    Text("—").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(sim.personnelInjuries) { inj in
                        Text("\(inj.personnel) · \(inj.role) · \(inj.severity.rawValue)")
                            .font(.caption)
                    }
                }
                Button("Simulate — Team Lead Injury") {
                    sim.simulatePersonnelInjury("Alpha-1", severity: .major, role: "Team Lead")
                }
            }

            Section("Supply Shortages") {
                if sim.supplyShortages.isEmpty {
                    Text("—").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(sim.supplyShortages) { s in
                        Text("\(s.supply) · \(s.criticality.rawValue) · \(Int(s.remainingHours)) hr")
                            .font(.caption)
                    }
                }
                Button("Simulate — Water Critical") {
                    sim.simulateSupplyShortage("Water", criticality: .mission, remainingHours: 2)
                }
            }

            Section("Adaptations (ranked)") {
                ForEach(sim.adaptations()) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(a.priority.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(priorityBG(a.priority))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            Text(a.action).font(.subheadline)
                        }
                        Text(a.reasoning).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive) { sim.reset() } label: { Text("Reset All") }
            }
        }
        .navigationTitle("Resource Sim")
    }

    private var capabilityBar: some View {
        let cap = sim.capability
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(format: "%.0f%% operational", cap * 100))
                .font(.title3.bold())
                .foregroundColor(capabilityColor(cap))
            ProgressView(value: cap)
                .tint(capabilityColor(cap))
        }
    }

    private func capabilityColor(_ c: Double) -> Color {
        if c < 0.5 { return .red }
        if c < 0.75 { return .orange }
        return .green
    }

    private func priorityBG(_ p: ResourceAdaptation.Priority) -> Color {
        switch p {
        case .p1: return .red
        case .p2: return .orange
        case .p3: return .blue
        case .p4: return .gray
        }
    }
}

struct ResourceSimulatorView_Previews: PreviewProvider {
    static var previews: some View { NavigationStack { ResourceSimulatorView() } }
}
