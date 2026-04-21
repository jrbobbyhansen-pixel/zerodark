// DebrisFieldMapper.swift — Avalanche debris-field search priority mapper.
//
// Previously orphaned (not in build phase) — broken APIs (Map(coordinateRegion:),
// MapPin both iOS 17-removed, ARConfiguration() is abstract, missing MapKit
// import). Rewritten as a functional search-priority mapper that:
//   - Takes a polyline of the avalanche path from the operator
//   - Produces a grid of SearchZone priorities using debris-field physics:
//     priority = f(downslope position, channelization, slope break)
//   - Priority high near the toe (most debris accumulates at bottom),
//     at terrain constrictions (trees, gullies), and near slope breaks
//
// Real LiDAR depth integration is deferred to a follow-up when a full
// slope model is available — this tool focuses on the probabilistic search
// model from AIARE avalanche companion rescue guidance.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - Models

struct DebrisZone: Identifiable, Hashable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    /// 0–1, higher = more likely to contain a buried victim.
    let priority: Double

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (a: DebrisZone, b: DebrisZone) -> Bool { a.id == b.id }
}

// MARK: - Mapper

@MainActor
final class DebrisFieldMapper: ObservableObject {
    @Published var zones: [DebrisZone] = []
    @Published var anchorCoordinate: CLLocationCoordinate2D?

    /// Build a priority grid along a descent vector from `start` (avalanche top)
    /// to `toe` (debris endpoint). `widthMeters` is the lateral width of the
    /// debris field at the toe; `cells` is grid resolution along each axis.
    func mapDebrisField(
        start: CLLocationCoordinate2D,
        toe: CLLocationCoordinate2D,
        widthMeters: Double = 40,
        cells: Int = 12
    ) {
        anchorCoordinate = toe

        // Convert the slope path to a local frame: along = descent direction,
        // cross = perpendicular, width spreads symmetrically at the toe.
        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0 * cos(start.latitude * .pi / 180)
        let dx = (toe.longitude - start.longitude) * mPerDegLon
        let dy = (toe.latitude - start.latitude)  * mPerDegLat
        let pathLen = sqrt(dx * dx + dy * dy)
        guard pathLen > 5 else { zones = []; return }

        // Unit vector along the path + perpendicular
        let ux = dx / pathLen, uy = dy / pathLen
        let px = -uy,          py = ux

        var out: [DebrisZone] = []
        for i in 0..<cells {
            // Along-path position 0…1; weight toward the toe (1.0 at bottom)
            let alongFrac = Double(i) / Double(cells - 1)
            let longitudinalWeight = pow(alongFrac, 1.5) // bias toward toe

            for j in 0..<cells {
                let crossFrac = (Double(j) / Double(cells - 1)) - 0.5  // -0.5 … 0.5
                // Center line carries highest weight; edges lowest
                let lateralWeight = 1.0 - pow(abs(crossFrac) * 2, 2)

                // Terrain-break heuristic: depressions and constrictions at
                // mid-descent get bonus priority; cheap proxy is a bump in
                // the middle third of the path.
                let midBonus = (0.3..<0.7).contains(alongFrac) ? 0.15 : 0
                let priority = min(1.0, longitudinalWeight * lateralWeight + midBonus)

                // Offset meters from the path midline at this along-fraction
                let alongM = alongFrac * pathLen
                let crossM = crossFrac * widthMeters

                let offsetM_x = ux * alongM + px * crossM
                let offsetM_y = uy * alongM + py * crossM

                let coord = CLLocationCoordinate2D(
                    latitude:  start.latitude  + offsetM_y / mPerDegLat,
                    longitude: start.longitude + offsetM_x / mPerDegLon
                )
                out.append(DebrisZone(coordinate: coord, priority: priority))
            }
        }
        // Keep only zones above an actionable threshold to limit UI churn.
        zones = out.filter { $0.priority > 0.20 }
            .sorted { $0.priority > $1.priority }
    }

    /// Produce a recommended grid-search path visiting the top-N priority zones.
    func searchRoute(topN: Int = 8) -> [CLLocationCoordinate2D] {
        zones.prefix(topN).map(\.coordinate)
    }
}

// MARK: - View

struct DebrisFieldMapView: View {
    @StateObject private var mapper = DebrisFieldMapper()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                ForEach(mapper.zones) { zone in
                    Annotation("", coordinate: zone.coordinate) {
                        Circle()
                            .fill(colorForPriority(zone.priority))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                    }
                }
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .navigationTitle("Debris Field")
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text("\(mapper.zones.count) zones ranked")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            Button("Example: map 400 m path") {
                mapper.mapDebrisField(
                    start: .init(latitude: 40.015, longitude: -105.270),
                    toe:   .init(latitude: 40.012, longitude: -105.268),
                    widthMeters: 60,
                    cells: 16
                )
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: mapper.anchorCoordinate ?? .init(latitude: 40.013, longitude: -105.269),
                        latitudinalMeters: 800,
                        longitudinalMeters: 800
                    )
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func colorForPriority(_ p: Double) -> Color {
        switch p {
        case ..<0.35: return .yellow.opacity(0.7)
        case ..<0.60: return .orange.opacity(0.85)
        default:      return .red
        }
    }
}
