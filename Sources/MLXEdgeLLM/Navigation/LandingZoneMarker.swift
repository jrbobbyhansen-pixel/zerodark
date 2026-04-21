// LandingZoneMarker.swift — Supply drop zone marker with parachute drift compensation.
// Calculates airdrop offset from wind speed/direction and cargo descent rate.
// Marks DZ on map, broadcasts coordinates via MeshService.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - DropZoneType

enum DropZoneType: String, CaseIterable, Identifiable, Codable {
    case supply      = "Supply Drop"
    case medevac     = "MEDEVAC LZ"
    case personnel   = "Personnel"
    case equipment   = "Equipment"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .supply:    return "shippingbox.fill"
        case .medevac:   return "cross.fill"
        case .personnel: return "person.fill"
        case .equipment: return "gearshape.fill"
        }
    }
    var color: Color {
        switch self {
        case .supply:    return ZDDesign.safetyYellow
        case .medevac:   return ZDDesign.signalRed
        case .personnel: return ZDDesign.cyanAccent
        case .equipment: return .orange
        }
    }
}

// MARK: - ParachuteDriftCalc

struct ParachuteDriftCalc {
    let releaseAltitudeM: Double
    let descentRateMps: Double
    let windSpeedMps: Double
    let windBearingDeg: Double

    var descentTimeSec: Double { releaseAltitudeM / max(0.1, descentRateMps) }
    var driftM: Double { windSpeedMps * descentTimeSec }

    func releasePoint(from lz: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let releaseBearing = (windBearingDeg + 180).truncatingRemainder(dividingBy: 360)
        return offsetCoord(from: lz, bearing: releaseBearing, distanceM: driftM)
    }

    private func offsetCoord(from o: CLLocationCoordinate2D, bearing deg: Double, distanceM: Double) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let d = distanceM / R
        let b = deg * .pi / 180
        let lat1 = o.latitude * .pi / 180, lon1 = o.longitude * .pi / 180
        let lat2 = asin(sin(lat1)*cos(d) + cos(lat1)*sin(d)*cos(b))
        let lon2 = lon1 + atan2(sin(b)*sin(d)*cos(lat1), cos(d)-sin(lat1)*sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / Double.pi, longitude: lon2 * 180 / Double.pi)
    }
}

// MARK: - CLLocation2D (Codable wrapper)

struct CLLocation2D: Codable {
    var latitude: Double
    var longitude: Double

    init(coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude; longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - DropZone

struct DropZone: Identifiable, Codable {
    let id: UUID
    let type: DropZoneType
    var name: String
    var intendedLZ: CLLocation2D
    var releasePoint: CLLocation2D?
    var driftM: Double
    var descentTimeSec: Double
    var notes: String
    var timestamp: Date
    var transmittedViaMesh: Bool

    init(type: DropZoneType, name: String, lz: CLLocationCoordinate2D, notes: String = "") {
        id = UUID(); self.type = type; self.name = name
        intendedLZ = CLLocation2D(coordinate: lz)
        releasePoint = nil; driftM = 0; descentTimeSec = 0
        self.notes = notes; timestamp = Date(); transmittedViaMesh = false
    }
}

// MARK: - LandingZoneManager

@MainActor
final class LandingZoneManager: ObservableObject {
    static let shared = LandingZoneManager()

    @Published var zones: [DropZone] = []
    @Published var selectedCalc: ParachuteDriftCalc? = nil

    @Published var releaseAltitudeM: Double = 300
    @Published var descentRateMps: Double   = 5.0
    @Published var windSpeedMps: Double     = 3.0
    @Published var windBearingDeg: Double   = 270

    private let saveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("drop_zones.json")

    private init() {
        load()
        // Pre-fill wind from WindEstimator if available
        if let last = WindEstimator.shared.history.last {
            windSpeedMps = last.estimatedKph / 3.6
            windBearingDeg = last.directionDeg ?? 270
        }
    }

    func addZone(type: DropZoneType, name: String, coordinate: CLLocationCoordinate2D, notes: String = "") {
        let calc = makeCalc()
        var zone = DropZone(type: type, name: name, lz: coordinate, notes: notes)
        zone.releasePoint = CLLocation2D(coordinate: calc.releasePoint(from: coordinate))
        zone.driftM = calc.driftM
        zone.descentTimeSec = calc.descentTimeSec
        selectedCalc = calc
        zones.insert(zone, at: 0)
        save()
    }

    func recalculate(_ zone: DropZone) {
        guard let idx = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        let calc = makeCalc()
        let lz = zones[idx].intendedLZ.coordinate
        zones[idx].releasePoint = CLLocation2D(coordinate: calc.releasePoint(from: lz))
        zones[idx].driftM = calc.driftM
        zones[idx].descentTimeSec = calc.descentTimeSec
        selectedCalc = calc
        save()
    }

    func transmit(_ zone: DropZone) {
        guard let idx = zones.firstIndex(where: { $0.id == zone.id }) else { return }
        MeshService.shared.shareLocation(zones[idx].intendedLZ.coordinate)
        zones[idx].transmittedViaMesh = true
        save()
    }

    func remove(_ zone: DropZone) {
        zones.removeAll { $0.id == zone.id }
        save()
    }

    private func makeCalc() -> ParachuteDriftCalc {
        ParachuteDriftCalc(releaseAltitudeM: releaseAltitudeM,
                           descentRateMps: descentRateMps,
                           windSpeedMps: windSpeedMps,
                           windBearingDeg: windBearingDeg)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(zones) { try? data.write(to: saveURL, options: .atomic) }
    }
    private func load() {
        if let data = try? Data(contentsOf: saveURL),
           let decoded = try? JSONDecoder().decode([DropZone].self, from: data) { zones = decoded }
    }
}

// MARK: - LandingZoneMarkerView

struct LandingZoneMarkerView: View {
    @ObservedObject private var mgr = LandingZoneManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newType: DropZoneType = .supply

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        windCard
                        if mgr.zones.isEmpty { noZonesView }
                        else { ForEach(mgr.zones) { zoneCard($0) } }
                    }
                    .padding()
                }
            }
            .navigationTitle("Drop Zone Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) { addSheet }
        }
        .preferredColorScheme(.dark)
    }

    private var windCard: some View {
        VStack(spacing: 10) {
            Text("WIND CONDITIONS").font(.caption.bold()).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 20) {
                metricCell(String(format: "%.1f m/s", mgr.windSpeedMps), "speed")
                metricCell(String(format: "%.0f°", mgr.windBearingDeg), "from")
                metricCell(String(format: "%.0fm", mgr.releaseAltitudeM), "release alt")
                metricCell(String(format: "%.1f m/s", mgr.descentRateMps), "descent")
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var noZonesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox").font(.system(size: 48)).foregroundColor(.secondary)
            Text("No drop zones marked").font(.subheadline).foregroundColor(.secondary)
            Button("Add Drop Zone") { showAddSheet = true }
                .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
        }
        .frame(maxWidth: .infinity).padding(40)
    }

    @ViewBuilder
    private func zoneCard(_ zone: DropZone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: zone.type.icon).foregroundColor(zone.type.color)
                Text(zone.name).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                Spacer()
                if zone.transmittedViaMesh {
                    Label("Sent", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption2).foregroundColor(ZDDesign.successGreen)
                }
            }
            Text(String(format: "LZ: %.5f°, %.5f°", zone.intendedLZ.latitude, zone.intendedLZ.longitude))
                .font(.caption).foregroundColor(.secondary)
            if let rp = zone.releasePoint {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "RELEASE: %.5f°, %.5f°", rp.latitude, rp.longitude))
                        .font(.caption.bold()).foregroundColor(ZDDesign.safetyYellow)
                    Text(String(format: "Drift %.0fm in %.0fs", zone.driftM, zone.descentTimeSec))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button { mgr.recalculate(zone) } label: {
                    Label("Recalc", systemImage: "arrow.clockwise")
                        .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                }
                Button { mgr.transmit(zone) } label: {
                    Label("Mesh TX", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption.bold()).foregroundColor(ZDDesign.successGreen)
                }
                Spacer()
                Button { mgr.remove(zone) } label: {
                    Image(systemName: "trash").font(.caption).foregroundColor(ZDDesign.signalRed)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    TextField("Zone name", text: $newName).textFieldStyle(.roundedBorder)
                    Picker("Type", selection: $newType) {
                        ForEach(DropZoneType.allCases) { t in Text(t.rawValue).tag(t) }
                    }.pickerStyle(.segmented)
                    VStack(spacing: 8) {
                        Text("WIND & DROP PARAMETERS").font(.caption.bold()).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        sliderRow("Wind speed", $mgr.windSpeedMps, 0...30, "m/s")
                        sliderRow("Wind bearing", $mgr.windBearingDeg, 0...359, "°")
                        sliderRow("Release alt", $mgr.releaseAltitudeM, 50...3000, "m")
                        sliderRow("Descent rate", $mgr.descentRateMps, 3...15, "m/s")
                    }
                    .padding()
                    .background(ZDDesign.darkCard).cornerRadius(12)
                    Spacer()
                    Button("Mark Drop Zone") {
                        let coord = LocationManager.shared.currentLocation
                            ?? CLLocationCoordinate2D(latitude: 30, longitude: -97)
                        mgr.addZone(type: newType,
                                    name: newName.isEmpty ? "DZ \(mgr.zones.count+1)" : newName,
                                    coordinate: coord)
                        showAddSheet = false
                        newName = ""
                    }
                    .font(.subheadline.bold()).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(ZDDesign.cyanAccent).cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("New Drop Zone").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showAddSheet = false } } }
        }
        .preferredColorScheme(.dark)
    }

    private func sliderRow(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ unit: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range).tint(ZDDesign.cyanAccent)
            Text(String(format: "%.0f%@", value.wrappedValue, unit)).font(.caption).foregroundColor(ZDDesign.pureWhite).frame(width: 48)
        }
    }

    private func metricCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
