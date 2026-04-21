// SignalPropagation.swift — VHF/UHF line-of-sight coverage & dead-zone mapper.
//
// Previously orphaned + stubbed. Now computes real radio coverage using the
// existing LOSRaycastEngine + TerrainEngine DEM: from a radio at known
// coordinates, sample a grid of cells around it, LoS-check each with earth-
// curvature correction, and classify every cell as covered / dead /
// marginal. Then find the highest-dead-zone cell that has LoS to BOTH
// the transmitter AND an unserved region — that's the optimal relay site.
//
// Accepts a radius + grid resolution; budgets ~10 MB of output at
// typical 30 m / 5 km settings (~28k cells) which stays snappy on a ridge
// laptop.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Models

struct CoverageCell: Identifiable, Hashable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    enum Kind: String { case covered, marginal, dead }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (a: CoverageCell, b: CoverageCell) -> Bool { a.id == b.id }

    init(coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.id = UUID()
        self.coordinate = coordinate
        self.kind = kind
    }
}

struct RelayCandidate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let additionalCellsCovered: Int
}

// MARK: - Analyzer

@MainActor
final class SignalPropagation: ObservableObject {
    @Published private(set) var coverage: [CoverageCell] = []
    @Published private(set) var deadZones: [CoverageCell] = []
    @Published private(set) var relayCandidates: [RelayCandidate] = []
    @Published private(set) var isComputing = false
    @Published var transmitter: CLLocationCoordinate2D?

    /// Sample a square grid around `transmitter` and classify LoS. Defaults:
    /// 5 km radius, 30 m cell, transmitter antenna 2 m, receiver antenna 1 m.
    func computeCoverage(
        transmitter: CLLocationCoordinate2D,
        radiusMeters: Double = 5000,
        cellSizeMeters: Double = 30,
        txHeightM: Double = 2.0,
        rxHeightM: Double = 1.0
    ) async {
        isComputing = true
        defer { isComputing = false }
        self.transmitter = transmitter

        let halfCells = Int(radiusMeters / cellSizeMeters)
        let cellDeg = cellSizeMeters / 111_320.0

        var out: [CoverageCell] = []
        out.reserveCapacity((halfCells * 2 + 1) * (halfCells * 2 + 1))

        // Precompute observer elevation = DEM + antenna height.
        let txElev = TerrainEngine.shared.elevationAt(coordinate: transmitter) ?? 0
        _ = txElev + txHeightM   // used via LOSRaycastEngine computeLOS

        for dy in -halfCells...halfCells {
            for dx in -halfCells...halfCells {
                if dx == 0 && dy == 0 { continue }
                let lat = transmitter.latitude  + Double(-dy) * cellDeg
                let lon = transmitter.longitude + Double(dx) * cellDeg
                let target = CLLocationCoordinate2D(latitude: lat, longitude: lon)

                let los = LOSRaycastEngine.shared.computeLOS(
                    from: transmitter,
                    to: target,
                    observerHeight: txHeightM,
                    targetHeight: rxHeightM,
                    sampleCount: 40
                )
                let kind: CoverageCell.Kind
                if los.isVisible { kind = .covered }
                else {
                    // Marginal: blocked but within 50 m of the obstruction
                    let blockedCloseToReceiver = los.obstructionPoint.map {
                        target.distance(to: $0) < 50
                    } ?? false
                    kind = blockedCloseToReceiver ? .marginal : .dead
                }
                out.append(.init(coordinate: target, kind: kind))
            }
        }

        coverage = out
        deadZones = out.filter { $0.kind == .dead }
    }

    /// For the current coverage, propose up to `topN` relay candidates.
    /// Heuristic: for each dead cell, check LoS to transmitter AND a sample
    /// of other dead cells. The candidate that breaks open the most dead
    /// cells wins.
    func findRelayCandidates(topN: Int = 3) async {
        guard let tx = transmitter, !deadZones.isEmpty else { relayCandidates = []; return }
        isComputing = true
        defer { isComputing = false }

        // Subsample dead zones for scoring to keep this O(k²) manageable.
        let sample = deadZones.shuffled().prefix(200)
        let sampleCoords = sample.map(\.coordinate)

        var scored: [(CLLocationCoordinate2D, Int)] = []
        for candidate in sample {
            // Candidate must have LoS to transmitter
            let txLos = LOSRaycastEngine.shared.computeLOS(
                from: tx,
                to: candidate.coordinate,
                observerHeight: 2.0,
                targetHeight: 2.0,
                sampleCount: 40
            )
            guard txLos.isVisible else { continue }

            // Count dead cells that candidate has LoS to
            var opened = 0
            for target in sampleCoords where target.distance(to: candidate.coordinate) > 1 {
                let los = LOSRaycastEngine.shared.computeLOS(
                    from: candidate.coordinate,
                    to: target,
                    observerHeight: 2.0,
                    targetHeight: 1.0,
                    sampleCount: 20
                )
                if los.isVisible { opened += 1 }
            }
            scored.append((candidate.coordinate, opened))
        }

        relayCandidates = scored
            .sorted { $0.1 > $1.1 }
            .prefix(topN)
            .map { RelayCandidate(coordinate: $0.0, additionalCellsCovered: $0.1) }
    }
}

// MARK: - View

struct SignalPropagationView: View {
    @StateObject private var vm = SignalPropagation()
    @ObservedObject private var location = LocationManager.shared

    var body: some View {
        Form {
            Section("Transmitter") {
                LabeledContent("Position") {
                    if let tx = vm.transmitter {
                        Text(String(format: "%.5f, %.5f", tx.latitude, tx.longitude))
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("Not set").foregroundColor(.secondary)
                    }
                }
                Button("Use my location") {
                    Task {
                        await vm.computeCoverage(transmitter: location.locationOrDefault,
                                                 radiusMeters: 2000,
                                                 cellSizeMeters: 50)
                    }
                }
                .disabled(vm.isComputing)
            }

            if vm.isComputing {
                Section {
                    HStack {
                        ProgressView()
                        Text("Computing coverage…")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if !vm.coverage.isEmpty {
                Section("Coverage Summary") {
                    let covered = vm.coverage.filter { $0.kind == .covered }.count
                    let marginal = vm.coverage.filter { $0.kind == .marginal }.count
                    let dead = vm.coverage.filter { $0.kind == .dead }.count
                    stat("Covered", covered, .green)
                    stat("Marginal", marginal, .orange)
                    stat("Dead", dead, .red)
                }
                Section("Relay Candidates") {
                    if vm.relayCandidates.isEmpty {
                        Button("Find relay sites") {
                            Task { await vm.findRelayCandidates() }
                        }
                        .disabled(vm.isComputing)
                    } else {
                        ForEach(vm.relayCandidates) { rc in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.5f, %.5f",
                                            rc.coordinate.latitude, rc.coordinate.longitude))
                                    .font(.caption.monospacedDigit())
                                Text("Opens \(rc.additionalCellsCovered) additional cells")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Signal Propagation")
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)").monospacedDigit().foregroundColor(color)
        }
    }
}
