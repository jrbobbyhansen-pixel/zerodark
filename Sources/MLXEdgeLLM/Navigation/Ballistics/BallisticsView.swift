// BallisticsView.swift — SwiftUI UI wrapping BallisticsEngine.
// Preset cartridge + environment + target range → holdover table in MOA & MIL.

import SwiftUI

public struct BallisticsView: View {
    @StateObject private var vm = BallisticsViewModel()

    public init() {}

    public var body: some View {
        Form {
            cartridgeSection
            firearmSection
            environmentSection
            targetSection
            solutionSection
        }
        .navigationTitle("Ballistics")
    }

    // MARK: - Sections

    private var cartridgeSection: some View {
        Section("Cartridge") {
            Picker("Preset", selection: $vm.cartridgeId) {
                ForEach(BallisticsCartridge.presets) { c in
                    Text(c.name).tag(c.id)
                }
            }
            if let c = vm.selectedCartridge {
                LabeledContent("Muzzle velocity", value: String(format: "%.0f m/s", c.muzzleVelocityMps))
                LabeledContent("BC (G1)",           value: String(format: "%.3f", c.ballisticCoefficientG1))
                LabeledContent("Bullet weight",     value: String(format: "%.0f gr", c.bulletWeightGrains))
            }
        }
    }

    private var firearmSection: some View {
        Section("Firearm") {
            Stepper(value: $vm.zeroRangeMeters, in: 25...300, step: 25) {
                LabeledContent("Zero range", value: "\(Int(vm.zeroRangeMeters)) m")
            }
            Stepper(value: $vm.sightHeightCm, in: 3...12, step: 0.5) {
                LabeledContent("Sight height", value: String(format: "%.1f cm", vm.sightHeightCm))
            }
        }
    }

    private var environmentSection: some View {
        Section("Environment") {
            Stepper(value: $vm.temperatureC, in: -40...50, step: 1) {
                LabeledContent("Temperature", value: "\(Int(vm.temperatureC))°C")
            }
            Stepper(value: $vm.pressureHpa, in: 850...1050, step: 5) {
                LabeledContent("Pressure", value: String(format: "%.0f hPa", vm.pressureHpa))
            }
            Stepper(value: $vm.windSpeedMps, in: 0...25, step: 0.5) {
                LabeledContent("Wind", value: String(format: "%.1f m/s", vm.windSpeedMps))
            }
            Stepper(value: $vm.windDirectionDeg, in: 0...359, step: 15) {
                LabeledContent("Wind direction", value: "\(Int(vm.windDirectionDeg))° (0=head, 90=R→L)")
            }
        }
    }

    private var targetSection: some View {
        Section("Target") {
            Stepper(value: $vm.targetRangeMeters, in: 25...1500, step: 25) {
                LabeledContent("Range", value: "\(Int(vm.targetRangeMeters)) m")
            }
            Button("Compute") { vm.recompute() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }

    private var solutionSection: some View {
        Section("Solution") {
            if let s = vm.solutionAtTarget {
                row("Drop", String(format: "%.2f m",  s.dropMeters))
                row("Drop (MOA)", String(format: "%.1f MOA", s.dropMOA))
                row("Drop (MIL)", String(format: "%.2f mil", s.dropMIL))
                row("Windage", String(format: "%.2f m", s.windageMeters))
                row("Windage (MOA)", String(format: "%.1f MOA", s.windageMOA))
                row("Windage (MIL)", String(format: "%.2f mil", s.windageMIL))
                row("Velocity", String(format: "%.0f m/s", s.velocityMps))
                row("Energy", String(format: "%.0f J", s.energyJoules))
                row("TOF", String(format: "%.2f s", s.timeOfFlightSec))
            } else {
                Text("Tap Compute to solve.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            if !vm.holdoverTable.isEmpty {
                NavigationLink("Holdover Table") {
                    HoldoverTable(rows: vm.holdoverTable)
                }
            }
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).monospacedDigit().foregroundColor(.secondary)
        }
    }
}

// MARK: - Holdover Table

private struct HoldoverTable: View {
    let rows: [BallisticsSolution]

    var body: some View {
        List(Array(rows.enumerated()), id: \.0) { _, s in
            HStack {
                Text("\(Int(s.rangeMeters)) m")
                    .font(.body.monospacedDigit())
                    .frame(width: 70, alignment: .leading)
                Spacer()
                Text(String(format: "%.1f MOA", s.dropMOA))
                    .font(.body.monospacedDigit())
                    .frame(width: 90, alignment: .trailing)
                Text(String(format: "%.2f mil", s.dropMIL))
                    .font(.body.monospacedDigit())
                    .frame(width: 80, alignment: .trailing)
                Text(String(format: "%.0f m/s", s.velocityMps))
                    .font(.caption.monospacedDigit())
                    .frame(width: 70, alignment: .trailing)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Holdover Table")
    }
}

// MARK: - ViewModel

@MainActor
final class BallisticsViewModel: ObservableObject {
    @Published var cartridgeId: String = BallisticsCartridge.presets[0].id
    @Published var zeroRangeMeters: Double = 100
    @Published var sightHeightCm: Double = 7.0

    @Published var temperatureC: Double = 15
    @Published var pressureHpa: Double = 1013.25
    @Published var windSpeedMps: Double = 0
    @Published var windDirectionDeg: Double = 90

    @Published var targetRangeMeters: Double = 300
    @Published var solutionAtTarget: BallisticsSolution?
    @Published var holdoverTable: [BallisticsSolution] = []

    var selectedCartridge: BallisticsCartridge? {
        BallisticsCartridge.presets.first { $0.id == cartridgeId }
    }

    func recompute() {
        guard let cartridge = selectedCartridge else { return }
        let firearm = BallisticsFirearm(
            sightHeightMeters: sightHeightCm / 100,
            zeroRangeMeters: zeroRangeMeters
        )
        let env = BallisticsEnvironment(
            temperatureCelsius: temperatureC,
            pressureHpa: pressureHpa,
            humidityPercent: 50,
            altitudeMeters: 0,
            windSpeedMps: windSpeedMps,
            windDirectionDeg: windDirectionDeg
        )

        // Target and holdover table in one solver run
        let tableRanges = stride(from: 100.0, through: min(targetRangeMeters, 1500), by: 100).map { $0 }
        var allRanges = Array(Set(tableRanges + [targetRangeMeters])).sorted()
        if allRanges.first ?? 0 > 100 { allRanges.insert(100, at: 0) }

        let sols = BallisticsEngine.solve(
            cartridge: cartridge,
            firearm: firearm,
            environment: env,
            ranges: allRanges,
            maxRangeMeters: max(1500, targetRangeMeters + 100)
        )
        holdoverTable = sols
        solutionAtTarget = sols.first { abs($0.rangeMeters - targetRangeMeters) < 0.5 }
            ?? sols.last
    }
}
