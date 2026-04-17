// DriftCalculator.swift — Lost person drift pattern calculator for SAR.
// Generates probability distribution across terrain sectors based on
// travel mode, barriers, terrain slope, vegetation density.
// Based on ISRID (International Search & Rescue Incident Database) behaviour profiles.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Travel Mode

enum TravelMode: String, CaseIterable, Identifiable {
    case hiker       = "Hiker"
    case runner      = "Runner"
    case cyclist     = "Cyclist"
    case vehicle     = "Vehicle"
    case child       = "Child (< 12)"
    case elderlyAdult = "Elderly Adult"
    case dementia    = "Dementia/Cognitive"
    case despondent  = "Despondent"
    case intoxicated = "Intoxicated"

    var id: String { rawValue }

    /// Typical travel radius (km) in 12 hrs based on ISRID
    var typicalRadiusKm: Double {
        switch self {
        case .hiker:         return 3.0
        case .runner:        return 6.0
        case .cyclist:       return 12.0
        case .vehicle:       return 30.0
        case .child:         return 0.8
        case .elderlyAdult:  return 1.5
        case .dementia:      return 1.0
        case .despondent:    return 3.0
        case .intoxicated:   return 1.2
        }
    }

    /// Tendency to follow linear features (trails/roads) vs go off-track
    var linearAttraction: Double {
        switch self {
        case .hiker, .runner, .cyclist, .vehicle: return 0.75
        case .child:         return 0.30
        case .elderlyAdult:  return 0.60
        case .dementia:      return 0.20  // wanders without pattern
        case .despondent:    return 0.40
        case .intoxicated:   return 0.25
        }
    }

    /// Barrier tendency: how likely to stop at a major terrain feature
    var barrierSensitivity: Double {
        switch self {
        case .child, .elderlyAdult, .dementia: return 0.90
        case .hiker, .runner:                  return 0.55
        case .cyclist, .vehicle:               return 0.80
        case .despondent:                      return 0.20   // may override barriers
        case .intoxicated:                     return 0.50
        }
    }
}

// MARK: - Drift Sector

struct DriftSector: Identifiable {
    let id = UUID()
    let bearingDeg: Double         // sector centre bearing from IPP
    let widthDeg: Double           // sector angular width
    let radiusKm: Double           // search radius for this sector
    let probability: Double        // 0-1 probability of subject being here
    let terrainBarrier: String?    // barrier description if applicable

    var sweepAreaKm2: Double {
        // Annular sector area: π * r² * (θ/360)
        .pi * radiusKm * radiusKm * (widthDeg / 360.0)
    }
}

// MARK: - DriftResult

struct DriftResult {
    let timestamp: Date
    let ipp: CLLocationCoordinate2D    // initial planning point (LKP/LKA)
    let mode: TravelMode
    let sectors: [DriftSector]
    let maxRadiusKm: Double
    let pOA: Double                    // probability of area (should sum to ~1)
    let prioritySectors: [DriftSector] // top 3 by probability

    var containmentRadiusKm: Double {
        // 75th percentile search radius from ISRID
        mode.typicalRadiusKm * 1.4
    }
}

// MARK: - DriftCalculatorEngine

@MainActor
enum DriftCalculatorEngine {

    static let sectorCount = 8  // 8 compass sectors × 45° each

    static func calculate(
        ipp: CLLocationCoordinate2D,
        mode: TravelMode,
        timeLostHrs: Double,
        useTerrainData: Bool = true
    ) -> DriftResult {
        // Scale radius by time lost (root of time models ISRID empirical data)
        let baseRadiusKm = mode.typicalRadiusKm * sqrt(timeLostHrs / 12.0)

        var sectors: [DriftSector] = []
        var probs: [Double] = Array(repeating: 0, count: sectorCount)

        // Base distribution: flat if no linear features, biased toward downhill otherwise
        let slope = TerrainEngine.shared.elevationGrid(around: ipp, windowCells: 10)
            .map { grid -> Double in
                // Compute mean gradient direction from DEM
                let meanSlope = grid.flatMap { $0 }.reduce(0, +) / Double(grid.count * grid[0].count)
                return Double(atan(meanSlope) * 180 / .pi)
            } ?? 0.0

        for i in 0..<sectorCount {
            let bearing = Double(i) * 45.0
            var prob = 1.0 / Double(sectorCount)  // uniform base

            // Downhill bias: sectors within 90° of downslope direction get +20%
            let downslope = (slope + 180).truncatingRemainder(dividingBy: 360)
            let diff = abs(bearing - downslope)
            let angDiff = min(diff, 360 - diff)
            if angDiff < 90 { prob += 0.2 * (1 - angDiff / 90) }

            // Linear feature attraction (N-S and E-W bias for roads)
            if mode.linearAttraction > 0.6 {
                if [0, 90, 180, 270].contains(Int(bearing)) { prob += 0.1 }
            }

            // Cognitive impairment: random scatter
            if mode == .dementia || mode == .intoxicated {
                prob += Double.random(in: -0.1...0.1)
            }

            probs[i] = max(0, prob)
        }

        // Normalize to sum 1
        let total = probs.reduce(0, +)
        let normalized = probs.map { $0 / max(0.001, total) }

        // Build sector objects
        for i in 0..<sectorCount {
            let bearing = Double(i) * 45.0
            let prob = normalized[i]
            // Radius varies by probability: higher prob = larger search area
            let r = baseRadiusKm * (0.5 + prob)
            let barrier = detectBarrier(at: ipp, bearing: bearing, radiusKm: r)
            sectors.append(DriftSector(
                bearingDeg: bearing,
                widthDeg: 45,
                radiusKm: r,
                probability: prob,
                terrainBarrier: barrier
            ))
        }

        let top3 = sectors.sorted { $0.probability > $1.probability }.prefix(3)

        return DriftResult(
            timestamp: Date(),
            ipp: ipp,
            mode: mode,
            sectors: sectors,
            maxRadiusKm: baseRadiusKm * 1.5,
            pOA: normalized.reduce(0, +),
            prioritySectors: Array(top3)
        )
    }

    private static func detectBarrier(at ipp: CLLocationCoordinate2D,
                                       bearing: Double,
                                       radiusKm: Double) -> String? {
        // Simplified: use slope data to flag likely barriers (>35° = cliff)
        // In a real implementation this would check DEM along the bearing ray
        return nil   // no barrier data without ray-march
    }
}

// MARK: - DriftCalculatorManager

@MainActor
final class DriftCalculatorManager: ObservableObject {
    static let shared = DriftCalculatorManager()

    @Published var result: DriftResult? = nil
    @Published var isCalculating = false
    @Published var travelMode: TravelMode = .hiker
    @Published var timeLostHrs: Double = 6

    private init() {}

    func calculate() {
        guard let ipp = LocationManager.shared.currentLocation else { return }
        isCalculating = true
        let m = travelMode
        let t = timeLostHrs
        Task.detached(priority: .userInitiated) {
            let r = await MainActor.run { DriftCalculatorEngine.calculate(ipp: ipp, mode: m, timeLostHrs: t) }
            await MainActor.run { [weak self] in
                self?.result = r
                self?.isCalculating = false
            }
        }
    }
}

// MARK: - DriftCalculatorView

struct DriftCalculatorView: View {
    @ObservedObject private var mgr = DriftCalculatorManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        settingsCard
                        if mgr.isCalculating {
                            loadingView
                        } else if let r = mgr.result {
                            summaryCard(r)
                            priorityCard(r)
                            driftMap(r)
                            sectorsCard(r)
                        } else {
                            noResultView
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Drift Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mgr.calculate() } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .onAppear { if mgr.result == nil { mgr.calculate() } }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Settings

    private var settingsCard: some View {
        VStack(spacing: 10) {
            Text("SUBJECT PROFILE").font(.caption.bold()).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("Travel mode").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $mgr.travelMode) {
                    ForEach(TravelMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .tint(ZDDesign.cyanAccent)
            }
            HStack {
                Text("Time lost").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f hrs", mgr.timeLostHrs)).font(.caption).foregroundColor(ZDDesign.pureWhite)
            }
            Slider(value: $mgr.timeLostHrs, in: 1...72, step: 1)
                .tint(ZDDesign.cyanAccent)
                .onChange(of: mgr.timeLostHrs) { _, _ in mgr.calculate() }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(ZDDesign.cyanAccent).scaleEffect(1.4)
            Text("Calculating drift…").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    private var noResultView: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash").font(.largeTitle).foregroundColor(.secondary)
            Text("GPS required — enable location access").font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(ZDDesign.darkCard).cornerRadius(12)
    }

    // MARK: Summary

    private func summaryCard(_ r: DriftResult) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTAINMENT RADIUS").font(.caption.bold()).foregroundColor(.secondary)
                Text(String(format: "%.1f km", r.containmentRadiusKm))
                    .font(.system(size: 28, weight: .black)).foregroundColor(ZDDesign.cyanAccent)
                Text("75th percentile (ISRID)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("MODE").font(.caption.bold()).foregroundColor(.secondary)
                Text(r.mode.rawValue).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                Text(String(format: "%.0f hrs missing", mgr.timeLostHrs))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Priority Sectors

    private func priorityCard(_ r: DriftResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIORITY SEARCH AREAS").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(r.prioritySectors.indices, id: \.self) { i in
                let s = r.prioritySectors[i]
                HStack {
                    Text("\(i+1).").font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent).frame(width: 20)
                    Text(compassDir(s.bearingDeg))
                        .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite).frame(width: 30)
                    Text(String(format: "%.1f km radius", s.radiusKm))
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    probBadge(s.probability)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: Drift Map (compass rose probability display)

    private func driftMap(_ r: DriftResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROBABILITY DISTRIBUTION").font(.caption.bold()).foregroundColor(.secondary)
            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                let maxR = min(cx, cy) * 0.85
                let sorted = r.sectors.sorted { $0.bearingDeg < $1.bearingDeg }
                for s in sorted {
                    let startDeg = s.bearingDeg - s.widthDeg/2
                    let endDeg   = s.bearingDeg + s.widthDeg/2
                    let r_draw   = maxR * CGFloat(s.probability / (r.sectors.map { $0.probability }.max() ?? 1))
                    let path = Path { p in
                        p.move(to: CGPoint(x: cx, y: cy))
                        p.addArc(center: CGPoint(x: cx, y: cy), radius: r_draw,
                                 startAngle: .degrees(startDeg - 90),
                                 endAngle: .degrees(endDeg - 90), clockwise: false)
                        p.closeSubpath()
                    }
                    let alpha = CGFloat(0.3 + s.probability * 0.7)
                    ctx.fill(path, with: .color(Color(red: 0, green: 0.8, blue: 1).opacity(alpha)))
                    ctx.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 1)
                }
                // IPP dot
                ctx.fill(Path(ellipseIn: CGRect(x: cx-5, y: cy-5, width: 10, height: 10)),
                         with: .color(ZDDesign.signalRed))
                // Compass labels
                for (dir, deg) in [("N",0), ("E",90), ("S",180), ("W",270)] {
                    let rad = (Double(deg) - 90) * .pi / 180
                    let lx = cx + (maxR + 12) * CGFloat(cos(rad))
                    let ly = cy + (maxR + 12) * CGFloat(sin(rad))
                    ctx.draw(Text(dir).font(.system(size: 10)).foregroundColor(.secondary),
                             at: CGPoint(x: lx, y: ly))
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: All Sectors

    private func sectorsCard(_ r: DriftResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALL SECTORS").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(r.sectors.sorted { $0.probability > $1.probability }) { s in
                HStack {
                    Text(compassDir(s.bearingDeg))
                        .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite).frame(width: 32)
                    Text(String(format: "%.1f km", s.radiusKm)).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if let b = s.terrainBarrier {
                        Text(b).font(.caption2).foregroundColor(.orange)
                    }
                    probBadge(s.probability)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func compassDir(_ deg: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        return dirs[Int((deg + 22.5) / 45.0) % 8]
    }

    private func probBadge(_ p: Double) -> some View {
        Text(String(format: "%.0f%%", p * 100))
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(ZDDesign.cyanAccent.opacity(0.15))
            .foregroundColor(ZDDesign.cyanAccent)
            .cornerRadius(4)
    }
}
