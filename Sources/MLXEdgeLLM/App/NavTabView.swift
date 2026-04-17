// NavTabView.swift — Navigation HUD with AR celestial overlay
// Primary navigation view: EKF breadcrumb trail, viewshed, compass, DR confidence ring

import SwiftUI
import MapKit
import CoreLocation

struct NavTabView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var breadcrumb = BreadcrumbEngine.shared
    @ObservedObject private var deadReckoning = DeadReckoningEngine.shared
    @ObservedObject private var celestial = CelestialNavigator.shared
    @ObservedObject private var weather = WeatherForecaster.shared

    @State private var showAROverlay = false
    @State private var showLOS = false
    @State private var showHLZ = false
    @State private var showWaterCrossing = false
    @State private var viewshedResult: ViewshedResult?
    @State private var isComputingViewshed = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            ZStack {
                // Map with breadcrumb trail + viewshed overlay
                Map(position: $mapPosition) {
                    // Breadcrumb trail
                    if breadcrumb.trail.count >= 2 {
                        MapPolyline(coordinates: breadcrumb.trail.map(\.coordinate))
                            .stroke(.cyan, lineWidth: 3)
                    }

                    // Current position marker
                    if let pos = appState.navState.position {
                        Annotation("", coordinate: pos) {
                            ZStack {
                                // DR confidence ring
                                if deadReckoning.isActive {
                                    Circle()
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                                        .frame(width: max(20, deadReckoning.confidenceRadius), height: max(20, deadReckoning.confidenceRadius))
                                }
                                // EKF uncertainty ring
                                Circle()
                                    .fill(Color.cyan.opacity(0.3))
                                    .frame(width: max(12, appState.navState.ekfUncertainty), height: max(12, appState.navState.ekfUncertainty))
                                // Heading indicator
                                Image(systemName: "location.north.fill")
                                    .foregroundColor(.cyan)
                                    .rotationEffect(.degrees(appState.navState.heading))
                            }
                        }
                    }

                    // Viewshed visualization
                    if let vs = viewshedResult {
                        viewshedOverlay(vs)
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))

                // HUD overlay
                VStack {
                    navHUD
                    Spacer()
                    bottomBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLOS = true
                    } label: {
                        Image(systemName: "rays")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAROverlay.toggle()
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await computeViewshed() }
                    } label: {
                        if isComputingViewshed {
                            ProgressView()
                        } else {
                            Image(systemName: "eye.circle")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                    .disabled(isComputingViewshed)
                }
            }
            .navigationTitle("Navigation")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAROverlay) {
                celestialARSheet
            }
            .sheet(isPresented: $showLOS) {
                LineOfSightAnalyzerView()
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showHLZ) {
                HLZFinderView()
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showWaterCrossing) {
                WaterCrossingAnalyzerView()
                    .preferredColorScheme(.dark)
            }
        }
    }

    // MARK: - Navigation HUD

    private var navHUD: some View {
        HStack(spacing: 16) {
            // Speed
            VStack(spacing: 2) {
                Text(String(format: "%.1f", appState.navState.speed))
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(ZDDesign.pureWhite)
                Text("m/s")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Divider().frame(height: 40)

            // Heading
            VStack(spacing: 2) {
                Text(String(format: "%03.0f\u{00B0}", appState.navState.heading))
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(ZDDesign.pureWhite)
                Text("HDG")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Divider().frame(height: 40)

            // Altitude
            VStack(spacing: 2) {
                Text(String(format: "%.0fm", appState.navState.altitude))
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(ZDDesign.pureWhite)
                Text("ALT")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Divider().frame(height: 40)

            // EKF uncertainty
            VStack(spacing: 2) {
                Text(String(format: "%.1fm", appState.navState.ekfUncertainty))
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundColor(appState.navState.ekfUncertainty > 10 ? ZDDesign.signalRed : ZDDesign.pureWhite)
                Text("ERR")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ZDDesign.darkCard.opacity(0.9))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 20) {
            // Canopy indicator
            HStack(spacing: 4) {
                Image(systemName: appState.navState.canopyDetected ? "leaf.fill" : "leaf")
                    .foregroundColor(appState.navState.canopyDetected ? .orange : .green)
                Text(appState.navState.canopyDetected ? "CANOPY" : "OPEN")
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
            }

            // ZUPT count
            HStack(spacing: 4) {
                Image(systemName: "shoeprints.fill")
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("ZUPT: \(appState.navState.zuptCount)")
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
            }

            // Celestial status
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundColor(celestial.detectedStarCount >= 2 ? .yellow : ZDDesign.mediumGray)
                Text("\(celestial.detectedStarCount)")
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
            }

            // HLZ finder
            Button {
                showHLZ = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "helicopter")
                        .foregroundColor(ZDDesign.cyanAccent)
                    Text("HLZ")
                        .font(.caption)
                        .foregroundColor(ZDDesign.pureWhite)
                }
            }

            // Water crossing
            Button {
                showWaterCrossing = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.blue)
                    Text("H2O")
                        .font(.caption)
                        .foregroundColor(ZDDesign.pureWhite)
                }
            }

            // Battery trend
            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .foregroundColor(batteryColor)
                Text(String(format: "%.0fmin", appState.navState.batteryMinutesRemaining))
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
            }

            // Baro trend
            HStack(spacing: 4) {
                Image(systemName: baroIcon)
                    .foregroundColor(ZDDesign.cyanAccent)
                Text(weather.barometricPressureTrend == .stable ? "STABLE" :
                     weather.barometricPressureTrend == .rapidDrop ? "DROP" : "RISE")
                    .font(.caption)
                    .foregroundColor(ZDDesign.pureWhite)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ZDDesign.darkCard.opacity(0.9))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Celestial AR Sheet

    private var celestialARSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Celestial AR Overlay")
                    .font(.headline)
                    .foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Button("Done") { showAROverlay = false }
                    .foregroundColor(ZDDesign.cyanAccent)
            }
            .padding()

            if let overlay = celestial.arOverlayData {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.yellow)
                        Text(String(format: "Sun: Az %.1f\u{00B0} Alt %.1f\u{00B0}", overlay.sunAzimuth, overlay.sunAltitude))
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    if let moonAz = overlay.moonAzimuth, let moonAlt = overlay.moonAltitude {
                        HStack {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.gray)
                            Text(String(format: "Moon: Az %.1f\u{00B0} Alt %.1f\u{00B0}", moonAz, moonAlt))
                                .foregroundColor(ZDDesign.pureWhite)
                        }
                    }
                    Text("Stars detected: \(celestial.detectedStarCount)")
                        .foregroundColor(ZDDesign.mediumGray)
                }
            } else {
                Text("Point camera at sky to detect celestial bodies")
                    .foregroundColor(ZDDesign.mediumGray)
            }

            Spacer()
        }
        .background(Color.black)
        .presentationDetents([.medium])
    }

    // MARK: - Viewshed

    @MapContentBuilder
    private func viewshedOverlay(_ result: ViewshedResult) -> some MapContent {
        // Render visible/blocked radial endpoints as annotations
        let step = 360.0 / Double(result.resolution)
        ForEach(0..<result.resolution, id: \.self) { radialIdx in
            let bearing = Double(radialIdx) * step
            let lastSampleIdx = radialIdx * result.samplesPerRadial + (result.samplesPerRadial - 1)
            let isVisible = result.visibility[lastSampleIdx] > 0.5
            let endpoint = coordinateAtBearing(
                from: result.observer,
                bearing: bearing,
                distance: result.radius
            )
            Annotation("", coordinate: endpoint) {
                Circle()
                    .fill(isVisible ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func computeViewshed() async {
        guard let pos = appState.navState.position else { return }
        isComputingViewshed = true
        defer { isComputingViewshed = false }

        let cpuResult = LOSRaycastEngine.shared.computeViewshed(from: pos, radius: 2000, resolution: 360)
        var visibility = [Float](repeating: 0, count: 360 * 100)
        for (idx, entry) in cpuResult.enumerated() {
            visibility[idx] = entry.isVisible ? 1.0 : 0.0
        }
        let result = ViewshedResult(
            observer: pos,
            radius: 2000,
            resolution: 360,
            samplesPerRadial: 100,
            visibility: visibility,
            computeTimeMs: 0
        )
        viewshedResult = result
        appState.navState.viewshedTimestamp = Date()
        appState.navEventBus.send(.viewshedComputed(result))
    }

    // MARK: - Helpers

    private func coordinateAtBearing(from origin: CLLocationCoordinate2D, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let lat1 = origin.latitude * .pi / 180.0
        let lon1 = origin.longitude * .pi / 180.0
        let brng = bearing * .pi / 180.0
        let d = distance / earthRadius

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180.0 / .pi, longitude: lon2 * 180.0 / .pi)
    }

    private var batteryIcon: String {
        let level = appState.navState.batteryTrend
        if level > 0.75 { return "battery.100" }
        if level > 0.5 { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }

    private var batteryColor: Color {
        let mins = appState.navState.batteryMinutesRemaining
        if mins < 30 { return Color(ZDDesign.signalRed) }
        if mins < 60 { return .orange }
        return .green
    }

    private var baroIcon: String {
        switch weather.barometricPressureTrend {
        case .stable: return "barometer"
        case .rapidDrop: return "arrow.down.circle"
        case .rapidRise: return "arrow.up.circle"
        }
    }
}
