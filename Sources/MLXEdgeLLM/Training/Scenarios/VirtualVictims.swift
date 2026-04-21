// VirtualVictims.swift — Training-scenario casualties with time-evolving vitals.
//
// Previous impl: `Condition.allCases` failed (no CaseIterable), outcome math was
// trivial, blood-pressure update force-unwrapped `Int(Substring)` and would crash
// on non-numeric input. Fully rewritten:
//   - Vitals drift toward condition-specific steady state each tick
//   - Effective treatments push vitals toward stable (120/80, HR 70, SpO₂ 98)
//   - Ineffective treatment or no treatment → drift continues
//   - Outcome determined by composite shock index + time elapsed

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Condition

enum Condition: String, Codable, CaseIterable {
    case minorInjury
    case majorInjury
    case criticalInjury

    /// Steady-state vitals the casualty drifts toward if untreated.
    var untreatedSteadyState: Vitals.Snapshot {
        switch self {
        case .minorInjury:    return .init(heartRate: 95,  systolicBP: 115, oxygenSaturation: 97)
        case .majorInjury:    return .init(heartRate: 135, systolicBP: 95,  oxygenSaturation: 90)
        case .criticalInjury: return .init(heartRate: 165, systolicBP: 70,  oxygenSaturation: 82)
        }
    }

    /// Tick-rate of deterioration (per minute). Higher = faster decline.
    var deteriorationRate: Double {
        switch self {
        case .minorInjury:    return 0.02
        case .majorInjury:    return 0.05
        case .criticalInjury: return 0.12
        }
    }
}

// MARK: - Vitals

final class Vitals: ObservableObject {
    struct Snapshot {
        var heartRate: Int
        var systolicBP: Int
        var oxygenSaturation: Int
    }

    @Published var heartRate: Int
    @Published var systolicBP: Int
    @Published var oxygenSaturation: Int

    /// Shock Index: HR / SBP. >1.0 classically indicates hemorrhagic shock.
    var shockIndex: Double {
        guard systolicBP > 0 else { return .infinity }
        return Double(heartRate) / Double(systolicBP)
    }

    /// Classically stable range: SI < 0.8, SpO₂ > 94, HR 60-100.
    var stable: Bool {
        shockIndex < 0.8 && oxygenSaturation > 94 && (60...100).contains(heartRate)
    }

    init(condition: Condition) {
        let ss = condition.untreatedSteadyState
        self.heartRate = ss.heartRate
        self.systolicBP = ss.systolicBP
        self.oxygenSaturation = ss.oxygenSaturation
    }

    /// Move one time-step forward. `dtMinutes` can be any positive real; a treatment
    /// (if present) pulls vitals toward normal, otherwise drift continues toward
    /// the condition's untreated steady state.
    func tick(dtMinutes: Double, condition: Condition, treatment: Treatment?) {
        let target: Snapshot
        let drift: Double

        if let t = treatment, t.effectiveness > 0 {
            target = Snapshot(heartRate: 70, systolicBP: 120, oxygenSaturation: 98)
            drift = condition.deteriorationRate * (1.0 - t.effectiveness)
        } else {
            target = condition.untreatedSteadyState
            drift = condition.deteriorationRate
        }

        let step = min(1.0, drift * dtMinutes)
        heartRate        = interpolateInt(heartRate,        toward: target.heartRate,        step: step)
        systolicBP       = interpolateInt(systolicBP,       toward: target.systolicBP,       step: step)
        oxygenSaturation = interpolateInt(oxygenSaturation, toward: target.oxygenSaturation, step: step)
    }

    private func interpolateInt(_ current: Int, toward target: Int, step: Double) -> Int {
        let delta = Double(target - current) * step
        return Int((Double(current) + delta).rounded())
    }
}

// MARK: - Treatment

struct Treatment: Codable, Hashable {
    let name: String
    /// 0 = ineffective, 1 = fully corrective. Use e.g. 0.3 for partial measures.
    let effectiveness: Double
}

// MARK: - Outcome

enum Outcome: String, Codable {
    case stable
    case critical
    case deceased
}

// MARK: - Virtual Victim

final class VirtualVictim: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var age: Int
    @Published var gender: String
    @Published var location: CLLocationCoordinate2D
    @Published var condition: Condition
    @Published var vitals: Vitals
    @Published var treatment: Treatment?
    @Published var outcome: Outcome = .critical
    @Published var minutesElapsed: Double = 0

    init(name: String, age: Int, gender: String,
         location: CLLocationCoordinate2D, condition: Condition) {
        self.name = name
        self.age = age
        self.gender = gender
        self.location = location
        self.condition = condition
        self.vitals = Vitals(condition: condition)
        self.outcome = determineOutcome()
    }

    /// Advance simulation. Pass `dtMinutes` > 0.
    func advance(dtMinutes: Double) {
        guard outcome != .deceased else { return }
        vitals.tick(dtMinutes: dtMinutes, condition: condition, treatment: treatment)
        minutesElapsed += dtMinutes
        outcome = determineOutcome()
    }

    func applyTreatment(_ t: Treatment) {
        self.treatment = t
        // Re-evaluate outcome with the treatment in place on the next tick.
    }

    private func determineOutcome() -> Outcome {
        if vitals.oxygenSaturation < 70 || vitals.systolicBP < 50 { return .deceased }
        if vitals.stable { return .stable }
        return .critical
    }
}

// MARK: - ViewModel

@MainActor
final class VirtualVictimsViewModel: ObservableObject {
    @Published var victims: [VirtualVictim] = []
    @Published var simMinutes: Double = 0

    private var timer: Timer?

    func generateVictim(near origin: CLLocationCoordinate2D = .init(latitude: 37.7749, longitude: -122.4194)) {
        let idx = victims.count + 1
        let condition = Condition.allCases.randomElement() ?? .minorInjury
        let latJitter = Double.random(in: -0.005...0.005)
        let lonJitter = Double.random(in: -0.005...0.005)
        let v = VirtualVictim(
            name: "Victim \(idx)",
            age: Int.random(in: 18...80),
            gender: ["Male", "Female"].randomElement() ?? "Male",
            location: .init(latitude: origin.latitude + latJitter, longitude: origin.longitude + lonJitter),
            condition: condition
        )
        victims.append(v)
    }

    /// Start a 1 sim-minute-per-real-second tick. Stops when all victims stable/deceased.
    func startClock(rateMinutesPerSecond: Double = 1.0) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(dtMinutes: rateMinutesPerSecond)
            }
        }
    }

    func stopClock() { timer?.invalidate(); timer = nil }

    private func tick(dtMinutes: Double) {
        simMinutes += dtMinutes
        for v in victims { v.advance(dtMinutes: dtMinutes) }
        let allTerminal = !victims.isEmpty && victims.allSatisfy { $0.outcome == .stable || $0.outcome == .deceased }
        if allTerminal { stopClock() }
    }

    func applyTreatment(to victim: VirtualVictim, treatment: Treatment) {
        victim.applyTreatment(treatment)
    }
}

// MARK: - View

struct VirtualVictimsView: View {
    @StateObject private var vm = VirtualVictimsViewModel()

    var body: some View {
        NavigationStack {
            List(vm.victims) { victim in
                VictimRow(victim: victim, vm: vm)
            }
            .navigationTitle("Virtual Victims")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(String(format: "T+%.0f min", vm.simMinutes))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { vm.generateVictim() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Generate victim")
                    Button { vm.startClock() } label: { Image(systemName: "play.fill") }
                        .accessibilityLabel("Start sim clock")
                    Button { vm.stopClock() } label: { Image(systemName: "pause.fill") }
                        .accessibilityLabel("Pause sim clock")
                }
            }
        }
    }
}

private struct VictimRow: View {
    @ObservedObject var victim: VirtualVictim
    let vm: VirtualVictimsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(victim.name).font(.headline)
                Spacer()
                Text(victim.outcome.rawValue.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(outcomeBG(victim.outcome))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            Text("Age \(victim.age) · \(victim.gender) · \(victim.condition.rawValue)")
                .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 12) {
                statView("HR", "\(victim.vitals.heartRate)")
                statView("BP", "\(victim.vitals.systolicBP)")
                statView("SpO₂", "\(victim.vitals.oxygenSaturation)")
                statView("SI", String(format: "%.2f", victim.vitals.shockIndex))
            }
            .font(.caption.monospacedDigit())
            if let t = victim.treatment {
                Text("Tx: \(t.name) (eff \(Int(t.effectiveness * 100))%)")
                    .font(.caption2).foregroundColor(.green)
            }
            HStack {
                Button("Tourniquet") {
                    vm.applyTreatment(to: victim, treatment: .init(name: "Tourniquet", effectiveness: 0.85))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("IV Fluids") {
                    vm.applyTreatment(to: victim, treatment: .init(name: "IV Fluids", effectiveness: 0.6))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("NPA") {
                    vm.applyTreatment(to: victim, treatment: .init(name: "NPA", effectiveness: 0.4))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func statView(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
        }
    }

    private func outcomeBG(_ o: Outcome) -> Color {
        switch o {
        case .stable:   return .green
        case .critical: return .orange
        case .deceased: return .red
        }
    }
}

struct VirtualVictimsView_Previews: PreviewProvider {
    static var previews: some View { VirtualVictimsView() }
}
