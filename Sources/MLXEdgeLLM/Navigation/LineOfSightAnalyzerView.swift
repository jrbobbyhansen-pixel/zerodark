// LineOfSightAnalyzerView.swift — Full LOS analysis: terrain profile, Fresnel zones, radio planning
// Wraps LOSRaycastEngine with configurable observer/target, elevation chart, and segment map

import SwiftUI
import CoreLocation
import Charts

// MARK: - Radio Band

enum RadioBand: String, CaseIterable, Identifiable {
    case vhf  = "VHF"
    case uhf  = "UHF"
    case wifi = "WiFi"
    case lora = "LoRa"

    var id: String { rawValue }

    /// Wavelength in meters
    var wavelengthMeters: Double {
        switch self {
        case .vhf:  return 2.027    // ~148 MHz
        case .uhf:  return 0.682    // ~440 MHz
        case .wifi: return 0.125    // ~2.4 GHz
        case .lora: return 0.138    // ~2.17 GHz 915 MHz = 0.327
        }
    }

    var icon: String {
        switch self {
        case .vhf:  return "antenna.radiowaves.left.and.right"
        case .uhf:  return "dot.radiowaves.right"
        case .wifi: return "wifi"
        case .lora: return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - ViewModel

@MainActor
class LineOfSightAnalyzerViewModel: ObservableObject {
    @Published var observer: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @Published var target: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @Published var observerHeight: Double = 1.8
    @Published var targetHeight: Double = 0.0
    @Published var radioBand: RadioBand = .vhf
    @Published var result: LOSResult? = nil
    @Published var profile: [ElevationProfilePoint] = []
    @Published var isAnalyzing: Bool = false
    @Published var distanceMeters: Double = 0

    func analyze() {
        guard observer.latitude != 0 || target.latitude != 0 else { return }
        isAnalyzing = true

        Task.detached(priority: .userInitiated) { [observer, target, observerHeight, targetHeight] in
            let res = LOSRaycastEngine.shared.computeLOS(
                from: observer,
                to: target,
                observerHeight: observerHeight,
                targetHeight: targetHeight,
                sampleCount: 200
            )
            let prof = LOSRaycastEngine.shared.elevationProfile(
                from: observer,
                to: target,
                observerHeight: observerHeight,
                targetHeight: targetHeight,
                sampleCount: 200
            )
            let dist = CLLocation(latitude: observer.latitude, longitude: observer.longitude)
                .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))

            await MainActor.run { [weak self] in
                self?.result = res
                self?.profile = prof
                self?.distanceMeters = dist
                self?.isAnalyzing = false
            }
        }
    }

    /// Fresnel zone 1 radius at midpoint for the selected radio band.
    /// r = sqrt(λ * d1 * d2 / d_total) where d1=d2=d/2 at midpoint
    var fresnelZoneRadiusM: Double {
        guard distanceMeters > 0 else { return 0 }
        let d = distanceMeters
        return sqrt(radioBand.wavelengthMeters * (d / 2) * (d / 2) / d)
    }

    /// 0.6 * Fresnel zone 1 — minimum clearance needed for acceptable RF propagation
    var fresnelClearanceRequired: Double { fresnelZoneRadiusM * 0.6 }

    /// Minimum terrain clearance above LOS line across the profile
    var minimumClearanceM: Double {
        profile.map { $0.losHeight - $0.terrainElevation }.min() ?? 0
    }

    /// Whether Fresnel zone is adequately clear
    var fresnelClear: Bool { minimumClearanceM >= fresnelClearanceRequired }
}

// MARK: - Main View

struct LineOfSightAnalyzerView: View {
    @StateObject private var vm = LineOfSightAnalyzerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        coordinateInputs
                        radioPlanning
                        analyzeButton

                        if let result = vm.result {
                            resultBanner(result: result)
                            if !vm.profile.isEmpty {
                                elevationProfileChart
                                fresnelCard
                            }
                            segmentSummary(result: result)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Line of Sight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let loc = LocationManager.shared.currentLocation {
                            vm.observer = loc
                        }
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    .help("Set observer to current GPS")
                }
            }
            .onAppear {
                if let loc = LocationManager.shared.currentLocation {
                    vm.observer = loc
                }
            }
        }
    }

    // MARK: - Coordinate Inputs

    private var coordinateInputs: some View {
        VStack(spacing: 10) {
            coordinateRow(label: "Observer", icon: "eye.fill", color: ZDDesign.cyanAccent, coord: $vm.observer)
            coordinateRow(label: "Target", icon: "scope", color: .orange, coord: $vm.target)

            HStack(spacing: 12) {
                heightField(label: "Observer height", value: $vm.observerHeight)
                heightField(label: "Target height", value: $vm.targetHeight)
            }
        }
    }

    private func coordinateRow(label: String, icon: String, color: Color, coord: Binding<CLLocationCoordinate2D>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .leading)
            CoordinateTextField(coordinate: coord)
        }
        .padding(10)
        .background(ZDDesign.darkCard)
        .cornerRadius(8)
    }

    private func heightField(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack {
                Text(String(format: "%.1f m", value.wrappedValue))
                    .font(.caption.monospaced())
                    .foregroundColor(ZDDesign.pureWhite)
                Stepper("", value: value, in: 0...50, step: 0.5)
                    .labelsHidden()
            }
        }
        .padding(10)
        .background(ZDDesign.darkCard)
        .cornerRadius(8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Radio Planning

    private var radioPlanning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Radio Band")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(RadioBand.allCases) { band in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { vm.radioBand = band }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: band.icon)
                                .font(.caption)
                            Text(band.rawValue)
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(vm.radioBand == band ? ZDDesign.cyanAccent.opacity(0.2) : ZDDesign.darkCard)
                        .foregroundColor(vm.radioBand == band ? ZDDesign.cyanAccent : .secondary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(vm.radioBand == band ? ZDDesign.cyanAccent : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        Button {
            vm.analyze()
        } label: {
            HStack {
                if vm.isAnalyzing {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Image(systemName: "rays")
                }
                Text(vm.isAnalyzing ? "Analyzing…" : "Analyze LOS")
                    .font(.headline.bold())
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(vm.isAnalyzing ? Color.gray : ZDDesign.cyanAccent)
            .cornerRadius(12)
        }
        .disabled(vm.isAnalyzing)
    }

    // MARK: - Result Banner

    private func resultBanner(result: LOSResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.isVisible ? "eye.fill" : "eye.slash.fill")
                .font(.title2)
                .foregroundColor(result.isVisible ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.isVisible ? "Line of Sight CLEAR" : "Line of Sight BLOCKED")
                    .font(.headline.bold())
                    .foregroundColor(result.isVisible ? .green : .red)
                Text(String(format: "%.0fm | Observer: %.0fm | Target: %.0fm",
                            vm.distanceMeters, result.observerElevation, result.targetElevation))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(result.isVisible ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Elevation Profile Chart

    private var elevationProfileChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Elevation Profile")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            Chart {
                // Terrain fill
                ForEach(Array(vm.profile.enumerated()), id: \.offset) { _, pt in
                    AreaMark(
                        x: .value("Distance", pt.distance),
                        y: .value("Terrain", pt.terrainElevation)
                    )
                    .foregroundStyle(
                        pt.isBlocked ? Color.red.opacity(0.6) : Color.green.opacity(0.4)
                    )
                }

                // LOS line
                ForEach(Array(vm.profile.enumerated()), id: \.offset) { _, pt in
                    LineMark(
                        x: .value("Distance", pt.distance),
                        y: .value("LOS", pt.losHeight)
                    )
                    .foregroundStyle(ZDDesign.cyanAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .chartXAxisLabel("Distance (m)")
            .chartYAxisLabel("Elevation (m)")
            .frame(height: 180)
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(10)
        }
    }

    // MARK: - Fresnel Card

    private var fresnelCard: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.fresnelClear ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(vm.fresnelClear ? .green : .orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Fresnel Zone Clearance (\(vm.radioBand.rawValue))")
                    .font(.caption.bold())
                    .foregroundColor(ZDDesign.pureWhite)
                HStack(spacing: 8) {
                    Text("Required: \(String(format: "%.1f", vm.fresnelClearanceRequired)) m")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    Text("Min available: \(String(format: "%.1f", vm.minimumClearanceM)) m")
                        .font(.caption.monospaced())
                        .foregroundColor(vm.fresnelClear ? .green : .orange)
                }
                Text(vm.fresnelClear ? "RF path acceptable" : "Terrain intrudes — expect degraded signal")
                    .font(.caption2)
                    .foregroundColor(vm.fresnelClear ? .secondary : .orange)
            }
            Spacer()
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    // MARK: - Segment Summary

    private func segmentSummary(result: LOSResult) -> some View {
        let visible = result.segments.filter(\.isVisible).count
        let blocked = result.segments.filter { !$0.isVisible }.count

        return VStack(alignment: .leading, spacing: 8) {
            Text("Segments")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                segmentChip(label: "\(visible) visible", color: .green, icon: "eye.fill")
                segmentChip(label: "\(blocked) blocked", color: .red, icon: "eye.slash.fill")
                if let obs = result.obstructionPoint {
                    segmentChip(label: String(format: "%.5f, %.5f", obs.latitude, obs.longitude),
                                color: .orange, icon: "location.fill")
                }
            }
        }
    }

    private func segmentChip(label: String, color: Color, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .cornerRadius(8)
    }
}

// MARK: - Coordinate Text Field Helper

private struct CoordinateTextField: View {
    @Binding var coordinate: CLLocationCoordinate2D
    @State private var latText: String = ""
    @State private var lonText: String = ""
    @State private var editingLat = false
    @State private var editingLon = false

    var body: some View {
        HStack(spacing: 4) {
            TextField("Lat", text: $latText)
                .keyboardType(.decimalPad)
                .font(.caption.monospaced())
                .foregroundColor(ZDDesign.cyanAccent)
                .frame(maxWidth: .infinity)
                .onChange(of: latText) { _, v in
                    if let lat = Double(v) { coordinate.latitude = lat }
                }
            Text(",")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Lon", text: $lonText)
                .keyboardType(.decimalPad)
                .font(.caption.monospaced())
                .foregroundColor(ZDDesign.cyanAccent)
                .frame(maxWidth: .infinity)
                .onChange(of: lonText) { _, v in
                    if let lon = Double(v) { coordinate.longitude = lon }
                }
        }
        .onAppear {
            if coordinate.latitude != 0 { latText = String(format: "%.5f", coordinate.latitude) }
            if coordinate.longitude != 0 { lonText = String(format: "%.5f", coordinate.longitude) }
        }
        .onChange(of: coordinate.latitude) { _, v in
            if !editingLat { latText = String(format: "%.5f", v) }
        }
        .onChange(of: coordinate.longitude) { _, v in
            if !editingLon { lonText = String(format: "%.5f", v) }
        }
    }
}
