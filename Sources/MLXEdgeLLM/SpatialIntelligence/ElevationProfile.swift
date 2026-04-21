// ElevationProfile.swift — Elevation profile along a route or between two GPS points
// Uses GPS altitude from BreadcrumbEngine or manual waypoints. Canvas profile chart.
// Shows cumulative gain/loss, high points, saddles. No internet required.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - ProfilePoint

struct ProfilePoint: Identifiable, Codable {
    var id: UUID = UUID()
    var distanceFromStartM: Double
    var altitudeM: Double
    var coordinate: CoordStore?

    struct CoordStore: Codable {
        var lat: Double; var lon: Double
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
    }
}

// MARK: - ProfileStats

struct ProfileStats {
    let totalDistanceM: Double
    let cumulativeGainM: Double
    let cumulativeLossM: Double
    let maxAltitudeM: Double
    let minAltitudeM: Double
    let startAltitudeM: Double
    let endAltitudeM: Double
    var netChangeM: Double { endAltitudeM - startAltitudeM }
}

// MARK: - ElevationProfileEngine

enum ElevationProfileEngine {

    static func buildProfile(from waypoints: [(coord: CLLocationCoordinate2D, altM: Double)]) -> [ProfilePoint] {
        guard !waypoints.isEmpty else { return [] }
        var cumDist = 0.0
        var points: [ProfilePoint] = []
        for (i, wp) in waypoints.enumerated() {
            if i > 0 {
                let prev = waypoints[i - 1]
                cumDist += DistanceBearingCalc.distance(from: prev.coord, to: wp.coord)
            }
            points.append(ProfilePoint(
                distanceFromStartM: cumDist,
                altitudeM: wp.altM,
                coordinate: ProfilePoint.CoordStore(wp.coord)
            ))
        }
        return points
    }

    static func stats(for points: [ProfilePoint]) -> ProfileStats? {
        guard let first = points.first, let last = points.last else { return nil }
        var gain = 0.0, loss = 0.0
        for i in 1..<points.count {
            let delta = points[i].altitudeM - points[i-1].altitudeM
            if delta > 0 { gain += delta } else { loss += abs(delta) }
        }
        let alts = points.map(\.altitudeM)
        return ProfileStats(
            totalDistanceM: last.distanceFromStartM,
            cumulativeGainM: gain,
            cumulativeLossM: loss,
            maxAltitudeM: alts.max() ?? 0,
            minAltitudeM: alts.min() ?? 0,
            startAltitudeM: first.altitudeM,
            endAltitudeM: last.altitudeM
        )
    }

    /// Find high points (local maxima) in profile.
    static func highPoints(in points: [ProfilePoint], threshold: Double = 10) -> [ProfilePoint] {
        guard points.count >= 3 else { return [] }
        var highs: [ProfilePoint] = []
        for i in 1..<(points.count - 1) {
            let p = points[i]
            if p.altitudeM > points[i-1].altitudeM + threshold && p.altitudeM > points[i+1].altitudeM + threshold {
                highs.append(p)
            }
        }
        return highs
    }

    /// Find saddles (local minima) between high points.
    static func saddles(in points: [ProfilePoint], threshold: Double = 10) -> [ProfilePoint] {
        guard points.count >= 3 else { return [] }
        var sads: [ProfilePoint] = []
        for i in 1..<(points.count - 1) {
            let p = points[i]
            if p.altitudeM < points[i-1].altitudeM - threshold && p.altitudeM < points[i+1].altitudeM - threshold {
                sads.append(p)
            }
        }
        return sads
    }
}

// MARK: - ElevationProfileManager

@MainActor
final class ElevationProfileManager: ObservableObject {
    static let shared = ElevationProfileManager()

    @Published var currentProfile: [ProfilePoint] = []
    @Published var profileStats: ProfileStats? = nil

    private init() { buildFromBreadcrumbs() }

    func buildFromBreadcrumbs() {
        let crumbs = BreadcrumbEngine.shared.trail
        guard !crumbs.isEmpty else { return }
        let waypoints = crumbs.map { ($0.coordinate, $0.altitude) }
        currentProfile = ElevationProfileEngine.buildProfile(from: waypoints)
        profileStats = ElevationProfileEngine.stats(for: currentProfile)
    }

    func buildFromWaypoints(_ waypoints: [(coord: CLLocationCoordinate2D, altM: Double)]) {
        currentProfile = ElevationProfileEngine.buildProfile(from: waypoints)
        profileStats = ElevationProfileEngine.stats(for: currentProfile)
    }

    var highPoints: [ProfilePoint] { ElevationProfileEngine.highPoints(in: currentProfile) }
    var saddles: [ProfilePoint] { ElevationProfileEngine.saddles(in: currentProfile) }
}

// MARK: - ElevationProfileView

struct ElevationProfileView: View {
    @ObservedObject private var manager = ElevationProfileManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if manager.currentProfile.isEmpty {
                            noDataCard
                        } else {
                            profileChartCard
                            if let s = manager.profileStats { statsCard(s) }
                            featuresCard
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Elevation Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manager.buildFromBreadcrumbs()
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var noDataCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "mountain.2").font(.title).foregroundColor(.secondary)
            Text("No route data available").font(.subheadline).foregroundColor(.secondary)
            Text("Enable breadcrumb tracking to record an elevation profile")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(ZDDesign.darkCard).cornerRadius(12)
    }

    private var profileChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ELEVATION PROFILE").font(.caption.bold()).foregroundColor(.secondary)
            GeometryReader { _ in
                let pts = manager.currentProfile
                Canvas { ctx, size in
                    guard pts.count > 1 else { return }
                    let alts = pts.map(\.altitudeM)
                    let minA = (alts.min() ?? 0) - 10
                    let maxA = (alts.max() ?? 0) + 10
                    let range = max(1, maxA - minA)
                    let maxD = pts.last?.distanceFromStartM ?? 1
                    var path = Path()
                    var fill = Path()
                    for (i, p) in pts.enumerated() {
                        let x = CGFloat(p.distanceFromStartM / maxD) * size.width
                        let y = size.height - CGFloat((p.altitudeM - minA) / range) * size.height
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                            fill.move(to: CGPoint(x: x, y: size.height))
                            fill.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                            fill.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(ZDDesign.cyanAccent.opacity(0.15)))
                    ctx.stroke(path, with: .color(ZDDesign.cyanAccent), lineWidth: 2)
                    // High points
                    for hp in ElevationProfileEngine.highPoints(in: pts) {
                        let x = CGFloat(hp.distanceFromStartM / maxD) * size.width
                        let y = size.height - CGFloat((hp.altitudeM - minA) / range) * size.height
                        ctx.fill(Path(ellipseIn: CGRect(x: x-4, y: y-4, width: 8, height: 8)),
                                 with: .color(.orange))
                    }
                }
            }
            .frame(height: 120)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
            if let s = manager.profileStats {
                HStack {
                    Text("Start").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f km", s.totalDistanceM / 1000)).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func statsCard(_ s: ProfileStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROFILE STATISTICS").font(.caption.bold()).foregroundColor(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statPill(v: String(format: "+%.0fm", s.cumulativeGainM), l: "Gain", c: ZDDesign.successGreen)
                statPill(v: String(format: "-%.0fm", s.cumulativeLossM), l: "Loss", c: ZDDesign.signalRed)
                statPill(v: String(format: "%.0fm", s.netChangeM), l: "Net", c: ZDDesign.cyanAccent)
                statPill(v: String(format: "%.0fm", s.maxAltitudeM), l: "Max Alt", c: .orange)
                statPill(v: String(format: "%.0fm", s.minAltitudeM), l: "Min Alt", c: .blue)
                statPill(v: String(format: "%.1f km", s.totalDistanceM / 1000), l: "Distance", c: ZDDesign.mediumGray)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TERRAIN FEATURES").font(.caption.bold()).foregroundColor(.secondary)
            let highs = manager.highPoints
            let sads  = manager.saddles
            if highs.isEmpty && sads.isEmpty {
                Text("No significant features detected").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(highs) { hp in
                    HStack {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("High Point").font(.caption.bold()).foregroundColor(.orange)
                        Spacer()
                        Text(String(format: "%.0fm  at  %.1fkm", hp.altitudeM, hp.distanceFromStartM / 1000))
                            .font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                }
                ForEach(sads) { s in
                    HStack {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        Text("Saddle").font(.caption.bold()).foregroundColor(.blue)
                        Spacer()
                        Text(String(format: "%.0fm  at  %.1fkm", s.altitudeM, s.distanceFromStartM / 1000))
                            .font(.caption.monospaced()).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func statPill(v: String, l: String, c: Color) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.caption.bold()).foregroundColor(c)
            Text(l).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(c.opacity(0.08)).cornerRadius(8)
    }
}
