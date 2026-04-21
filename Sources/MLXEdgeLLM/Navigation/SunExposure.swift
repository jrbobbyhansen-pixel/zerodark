// SunExposure.swift — Terrain sun exposure and thermal impact calculation
// Uses Jean Meeus ephemeris (CelestialNavigator) + terrain slope/aspect (TerrainEngine)
// to compute per-point insolation, self-shadowing, and thermal load for route planning.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - SunExposure Result

struct SunExposure: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let date: Date
    let sunAzimuth: Double     // degrees true (0=N, 90=E)
    let sunAltitude: Double    // degrees above horizon (negative = below)
    let slopeDeg: Double
    let aspectDeg: Double
    let insolation: Double     // 0–1 (0 = fully shaded, 1 = full perpendicular sun)
    let isShaded: Bool         // true if in shadow OR night
    let estimatedThermalDeltaC: Double  // surface temp above ambient

    var shadingReason: String? {
        if sunAltitude <= 0 { return "Night" }
        if insolation == 0 { return "Self-shadow (terrain facing away from sun)" }
        return nil
    }
}

struct ThermalImpactResult {
    let waypoints: [SunExposure]
    let peakDeltaC: Double       // max surface temp above ambient
    let averageDeltaC: Double    // average thermal load along route
    let shadedFraction: Double   // 0–1 fraction of route in shade
    let hotestSegmentIndex: Int? // index into waypoints
}

// MARK: - SunExposureService

@MainActor
class SunExposureService: ObservableObject {
    static let shared = SunExposureService()

    @Published var lastResult: SunExposure?
    @Published var routeThermal: ThermalImpactResult?
    @Published var shadedRestAreas: [SunExposure] = []
    @Published var isCalculating: Bool = false

    /// Peak solar delta above ambient (°C) for full perpendicular insolation.
    /// Calibrated for mid-latitude summer around solar noon.
    var peakThermalDeltaC: Double = 22.0

    private init() {}

    // MARK: - Single Point

    /// Compute sun exposure at a coordinate for a specific date/time.
    func calculateSunExposure(
        for date: Date = Date(),
        at location: CLLocationCoordinate2D
    ) -> SunExposure {
        let (az, alt) = CelestialNavigator.shared.sunPosition(
            date: date,
            latitude: location.latitude,
            longitude: location.longitude
        )
        let slope = TerrainEngine.shared.slopeAt(coordinate: location) ?? 0
        let aspect = TerrainEngine.shared.aspectAt(coordinate: location) ?? 0

        let insolation = computeInsolation(
            sunAzimuth: az, sunAltitude: alt,
            slopeDeg: slope, aspectDeg: aspect
        )

        let result = SunExposure(
            coordinate: location,
            date: date,
            sunAzimuth: az,
            sunAltitude: alt,
            slopeDeg: slope,
            aspectDeg: aspect,
            insolation: insolation,
            isShaded: insolation == 0,
            estimatedThermalDeltaC: insolation * peakThermalDeltaC
        )
        lastResult = result
        return result
    }

    // MARK: - Route Thermal Impact

    /// Compute thermal impact along a route for a given date/time.
    func calculateThermalImpact(
        for route: [CLLocationCoordinate2D],
        at date: Date = Date()
    ) async -> ThermalImpactResult? {
        guard !route.isEmpty else { return nil }
        isCalculating = true

        let sunPos = CelestialNavigator.shared.sunPosition(
            date: date, latitude: route[0].latitude, longitude: route[0].longitude
        )
        let result: ThermalImpactResult = await Task.detached(priority: .userInitiated) { [peakDeltaC = self.peakThermalDeltaC, sunPos] in
            let (az, alt) = sunPos
            var waypoints: [SunExposure] = []

            for coord in route {
                let slope = TerrainEngine.shared.slopeAt(coordinate: coord) ?? 0
                let aspect = TerrainEngine.shared.aspectAt(coordinate: coord) ?? 0
                let insolation = Self.computeInsolationStatic(
                    sunAzimuth: az, sunAltitude: alt,
                    slopeDeg: slope, aspectDeg: aspect
                )
                waypoints.append(SunExposure(
                    coordinate: coord,
                    date: date,
                    sunAzimuth: az,
                    sunAltitude: alt,
                    slopeDeg: slope,
                    aspectDeg: aspect,
                    insolation: insolation,
                    isShaded: insolation == 0,
                    estimatedThermalDeltaC: insolation * peakDeltaC
                ))
            }

            let deltas = waypoints.map(\.estimatedThermalDeltaC)
            let peak = deltas.max() ?? 0
            let avg  = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
            let shadedFrac = Double(waypoints.filter(\.isShaded).count) / Double(waypoints.count)
            let hotIdx = deltas.indices.max(by: { deltas[$0] < deltas[$1] })

            return ThermalImpactResult(
                waypoints: waypoints,
                peakDeltaC: peak,
                averageDeltaC: avg,
                shadedFraction: shadedFrac,
                hotestSegmentIndex: hotIdx
            )
        }.value

        routeThermal = result
        isCalculating = false
        return result
    }

    // MARK: - Shaded Rest Areas

    /// Identify shaded locations in a region for a given date/time.
    func identifyShadedRestAreas(
        in region: MKCoordinateRegion,
        at date: Date = Date(),
        gridResolution: Int = 10
    ) async {
        isCalculating = true
        let sunPos2 = CelestialNavigator.shared.sunPosition(
            date: date, latitude: region.center.latitude, longitude: region.center.longitude
        )
        let results: [SunExposure] = await Task.detached(priority: .userInitiated) { [peakDeltaC = self.peakThermalDeltaC, sunPos2] in
            let (az, alt) = sunPos2
            var shaded: [SunExposure] = []
            let latStep = region.span.latitudeDelta / Double(gridResolution)
            let lonStep = region.span.longitudeDelta / Double(gridResolution)
            let startLat = region.center.latitude - region.span.latitudeDelta / 2
            let startLon = region.center.longitude - region.span.longitudeDelta / 2

            for row in 0..<gridResolution {
                for col in 0..<gridResolution {
                    let coord = CLLocationCoordinate2D(
                        latitude: startLat + Double(row) * latStep,
                        longitude: startLon + Double(col) * lonStep
                    )
                    let slope  = TerrainEngine.shared.slopeAt(coordinate: coord) ?? 0
                    let aspect = TerrainEngine.shared.aspectAt(coordinate: coord) ?? 0
                    let insolation = Self.computeInsolationStatic(
                        sunAzimuth: az, sunAltitude: alt,
                        slopeDeg: slope, aspectDeg: aspect
                    )
                    if insolation < 0.2 {  // Less than 20% sun = practical shade
                        shaded.append(SunExposure(
                            coordinate: coord,
                            date: date,
                            sunAzimuth: az, sunAltitude: alt,
                            slopeDeg: slope, aspectDeg: aspect,
                            insolation: insolation,
                            isShaded: true,
                            estimatedThermalDeltaC: insolation * peakDeltaC
                        ))
                    }
                }
            }
            return shaded
        }.value
        shadedRestAreas = results
        isCalculating = false
    }

    // MARK: - Insolation Physics

    /// Compute cosine of solar incidence angle on a sloped surface.
    /// Returns 0 if night or terrain faces away from sun.
    private func computeInsolation(
        sunAzimuth az: Double,
        sunAltitude alt: Double,
        slopeDeg: Double,
        aspectDeg: Double
    ) -> Double {
        Self.computeInsolationStatic(sunAzimuth: az, sunAltitude: alt, slopeDeg: slopeDeg, aspectDeg: aspectDeg)
    }

    nonisolated static func computeInsolationStatic(
        sunAzimuth az: Double,
        sunAltitude alt: Double,
        slopeDeg: Double,
        aspectDeg: Double
    ) -> Double {
        guard alt > 0 else { return 0 }  // Below horizon

        let altRad    = alt      * .pi / 180
        let slopeRad  = slopeDeg * .pi / 180
        let azRad     = az       * .pi / 180
        let aspRad    = aspectDeg * .pi / 180

        // cos(incidence) = sin(alt)*cos(slope) + cos(alt)*sin(slope)*cos(az - aspect)
        let cosI = sin(altRad) * cos(slopeRad)
                 + cos(altRad) * sin(slopeRad) * cos(azRad - aspRad)

        return max(0, cosI)
    }
}

// MARK: - Sun Exposure View

struct SunExposureView: View {
    @ObservedObject private var service = SunExposureService.shared
    @State private var selectedDate: Date = Date()
    @State private var analysisCoord: CLLocationCoordinate2D = CLLocationCoordinate2D()
    @State private var exposure: SunExposure? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        datePicker
                        analyzeButton
                        if let exp = exposure {
                            exposureCard(exp)
                        }
                        if let thermal = service.routeThermal {
                            thermalRouteCard(thermal)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Sun Exposure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if let loc = LocationManager.shared.currentLocation {
                    analysisCoord = loc
                }
            }
        }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analysis Time")
                .font(.caption.bold()).foregroundColor(.secondary).padding(.horizontal, 4)
            DatePicker("", selection: $selectedDate)
                .datePickerStyle(.compact)
                .colorScheme(.dark)
                .padding()
                .background(ZDDesign.darkCard)
                .cornerRadius(10)
        }
    }

    private var analyzeButton: some View {
        Button {
            if let loc = LocationManager.shared.currentLocation {
                analysisCoord = loc
            }
            exposure = service.calculateSunExposure(for: selectedDate, at: analysisCoord)
        } label: {
            HStack {
                Image(systemName: "sun.max.fill")
                Text("Analyze Current Location")
                    .font(.headline.bold())
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ZDDesign.cyanAccent)
            .cornerRadius(12)
        }
    }

    private func exposureCard(_ exp: SunExposure) -> some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: exp.isShaded ? "cloud.fill" : "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(exp.isShaded ? .blue : .yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exp.isShaded ? "SHADED" : "SUN EXPOSED")
                        .font(.headline.bold())
                        .foregroundColor(exp.isShaded ? .blue : .yellow)
                    if let reason = exp.shadingReason {
                        Text(reason).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "+%.0f°C", exp.estimatedThermalDeltaC))
                        .font(.title2.bold().monospaced())
                        .foregroundColor(thermalColor(exp.estimatedThermalDeltaC))
                    Text("thermal delta").font(.caption2).foregroundColor(.secondary)
                }
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                infoCell("Sun Azimuth", value: String(format: "%.0f° T", exp.sunAzimuth))
                infoCell("Sun Altitude", value: String(format: "%.1f°", exp.sunAltitude))
                infoCell("Slope", value: String(format: "%.1f°", exp.slopeDeg))
                infoCell("Aspect", value: String(format: "%.0f° T", exp.aspectDeg))
                infoCell("Insolation", value: String(format: "%.0f%%", exp.insolation * 100))
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func thermalRouteCard(_ result: ThermalImpactResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route Thermal Profile").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 16) {
                VStack {
                    Text(String(format: "+%.0f°C", result.peakDeltaC))
                        .font(.title2.bold().monospaced()).foregroundColor(.red)
                    Text("peak").font(.caption2).foregroundColor(.secondary)
                }
                VStack {
                    Text(String(format: "+%.0f°C", result.averageDeltaC))
                        .font(.title2.bold().monospaced()).foregroundColor(.orange)
                    Text("average").font(.caption2).foregroundColor(.secondary)
                }
                VStack {
                    Text(String(format: "%.0f%%", result.shadedFraction * 100))
                        .font(.title2.bold().monospaced()).foregroundColor(.green)
                    Text("shaded").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func infoCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.monospaced().bold()).foregroundColor(ZDDesign.pureWhite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(6)
    }

    private func thermalColor(_ delta: Double) -> Color {
        switch delta {
        case 15...: return .red
        case 8..<15: return .orange
        case 3..<8: return .yellow
        default: return .green
        }
    }
}
