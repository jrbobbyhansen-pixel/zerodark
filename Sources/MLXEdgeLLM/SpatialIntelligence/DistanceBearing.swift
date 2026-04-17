// DistanceBearing.swift — Distance and bearing between any two or more points
// Supports current location, MGRS input, multiple waypoints, reverse bearing.

import Foundation
import CoreLocation
import SwiftUI

// MARK: - DistanceBearingCalc

enum DistanceBearingCalc {

    /// Haversine distance in meters.
    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let R = 6371000.0   // Earth radius meters
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let s = sin(dLat / 2)
        let c = cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let h = s * s + c
        return R * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Forward bearing in degrees true (0–360).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearing = atan2(y, x) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return bearing
    }

    /// Reverse bearing (back-bearing).
    static func reverseBearing(_ forward: Double) -> Double {
        return forward < 180 ? forward + 180 : forward - 180
    }

    /// Total route distance through ordered waypoints.
    static func routeDistance(waypoints: [CLLocationCoordinate2D]) -> Double {
        guard waypoints.count >= 2 else { return 0 }
        return zip(waypoints, waypoints.dropFirst()).map { distance(from: $0, to: $1) }.reduce(0, +)
    }

    /// Destination point given start, bearing, distance.
    static func destination(from start: CLLocationCoordinate2D, bearing: Double, distanceM: Double) -> CLLocationCoordinate2D {
        let R = 6371000.0
        let d = distanceM / R
        let b = bearing * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
        let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

// MARK: - DBWaypoint

struct DBWaypoint: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var mgrs: String {
        MGRSConverter.toMGRS(coordinate: coordinate, precision: 4)
    }
}

// MARK: - DBLeg (segment between two waypoints)

struct DBLeg: Identifiable {
    let id = UUID()
    let from: DBWaypoint
    let to: DBWaypoint
    let distanceM: Double
    let bearing: Double
    let reverseBearing: Double

    var distanceKm: Double { distanceM / 1000 }
    var distanceNM: Double { distanceM / 1852 }

    var cardinalDirection: String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW","N"]
        return dirs[Int((bearing + 11.25) / 22.5) % 16]
    }
}

// MARK: - DistanceBearingManager

@MainActor
final class DistanceBearingManager: ObservableObject {
    static let shared = DistanceBearingManager()

    @Published var waypoints: [DBWaypoint] = []

    private let saveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("distance_bearing_wpts.json")

    private init() { load() }

    // MARK: - Waypoints

    func addCurrentLocation(name: String = "") {
        guard let loc = LocationManager.shared.currentLocation else { return }
        let n = name.isEmpty ? "WP\(waypoints.count + 1)" : name
        waypoints.append(DBWaypoint(name: n, latitude: loc.latitude, longitude: loc.longitude))
        save()
    }

    func add(coordinate: CLLocationCoordinate2D, name: String = "") {
        let n = name.isEmpty ? "WP\(waypoints.count + 1)" : name
        waypoints.append(DBWaypoint(name: n, latitude: coordinate.latitude, longitude: coordinate.longitude))
        save()
    }

    func remove(at offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to dest: Int) {
        waypoints.move(fromOffsets: source, toOffset: dest)
        save()
    }

    // MARK: - Legs

    var legs: [DBLeg] {
        guard waypoints.count >= 2 else { return [] }
        return zip(waypoints, waypoints.dropFirst()).map { (a, b) in
            let dist = DistanceBearingCalc.distance(from: a.coordinate, to: b.coordinate)
            let brg  = DistanceBearingCalc.bearing(from: a.coordinate, to: b.coordinate)
            return DBLeg(from: a, to: b, distanceM: dist, bearing: brg,
                         reverseBearing: DistanceBearingCalc.reverseBearing(brg))
        }
    }

    var totalRouteDistanceM: Double {
        DistanceBearingCalc.routeDistance(waypoints: waypoints.map(\.coordinate))
    }

    // MARK: - Current Location Quick Calc

    func distanceBearingFromCurrent(to waypoint: DBWaypoint) -> (distanceM: Double, bearing: Double)? {
        guard let loc = LocationManager.shared.currentLocation else { return nil }
        let dist = DistanceBearingCalc.distance(from: loc, to: waypoint.coordinate)
        let brg  = DistanceBearingCalc.bearing(from: loc, to: waypoint.coordinate)
        return (dist, brg)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(waypoints) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([DBWaypoint].self, from: data) else { return }
        waypoints = loaded
    }
}

// MARK: - DistanceBearingView

struct DistanceBearingView: View {
    @ObservedObject private var manager = DistanceBearingManager.shared
    @State private var showAddSheet = false
    @State private var editMode: EditMode = .inactive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        waypointCard
                        if manager.legs.count > 0 { legsCard }
                        if manager.waypoints.count >= 2 { summaryCard }
                        quickCalcCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Distance & Bearing")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        EditButton()
                            .foregroundColor(ZDDesign.cyanAccent)
                        Button { showAddSheet = true } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showAddSheet) { AddWaypointSheet() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Waypoints Card

    private var waypointCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WAYPOINTS").font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Button {
                    manager.addCurrentLocation()
                } label: {
                    Label("Add Here", systemImage: "location.fill")
                        .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                }
            }
            if manager.waypoints.isEmpty {
                Text("Add waypoints to calculate distance and bearing")
                    .font(.caption).foregroundColor(.secondary).padding(.vertical, 8)
            } else {
                ForEach(Array(manager.waypoints.enumerated()), id: \.element.id) { i, wp in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.caption.bold().monospaced())
                            .foregroundColor(ZDDesign.cyanAccent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wp.name).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text(wp.mgrs).font(.caption2.monospaced()).foregroundColor(.secondary)
                        }
                        Spacer()
                        if editMode == .active {
                            Button {
                                if let idx = manager.waypoints.firstIndex(where: { $0.id == wp.id }) {
                                    manager.remove(at: IndexSet([idx]))
                                }
                            } label: {
                                Image(systemName: "trash").foregroundColor(ZDDesign.signalRed).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Legs Card

    private var legsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROUTE LEGS").font(.caption.bold()).foregroundColor(.secondary)
            ForEach(manager.legs) { leg in
                legRow(leg)
                if leg.id != manager.legs.last?.id {
                    Divider().background(ZDDesign.mediumGray.opacity(0.3))
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func legRow(_ leg: DBLeg) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(leg.from.name) → \(leg.to.name)")
                    .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                Spacer()
            }
            HStack(spacing: 20) {
                VStack(spacing: 1) {
                    Text(String(format: "%.0f m", leg.distanceM))
                        .font(.subheadline.bold()).foregroundColor(ZDDesign.cyanAccent)
                    Text(String(format: "%.2f km", leg.distanceKm))
                        .font(.caption2).foregroundColor(.secondary)
                }
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(ZDDesign.safetyYellow).font(.caption)
                        Text(String(format: "%.0f° %@", leg.bearing, leg.cardinalDirection))
                            .font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    }
                    Text("Fwd bearing").font(.caption2).foregroundColor(.secondary)
                }
                VStack(spacing: 1) {
                    Text(String(format: "%.0f°", leg.reverseBearing))
                        .font(.subheadline.bold()).foregroundColor(ZDDesign.mediumGray)
                    Text("Back bearing").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTE SUMMARY").font(.caption.bold()).foregroundColor(.secondary)
            HStack(spacing: 20) {
                statPill(
                    value: String(format: "%.0f m", manager.totalRouteDistanceM),
                    label: "Total Distance",
                    color: ZDDesign.cyanAccent
                )
                statPill(
                    value: String(format: "%.2f km", manager.totalRouteDistanceM / 1000),
                    label: "Kilometers",
                    color: .green
                )
                statPill(
                    value: String(format: "%.1f NM", manager.totalRouteDistanceM / 1852),
                    label: "Nautical Miles",
                    color: .blue
                )
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    // MARK: - Quick Calc Card

    private var quickCalcCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FROM CURRENT LOCATION").font(.caption.bold()).foregroundColor(.secondary)
            if manager.waypoints.isEmpty {
                Text("Add waypoints above").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(manager.waypoints.prefix(5)) { wp in
                    if let result = manager.distanceBearingFromCurrent(to: wp) {
                        HStack {
                            Text(wp.name).font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                            Spacer()
                            Text(String(format: "%.0f m", result.distanceM))
                                .font(.caption.monospaced()).foregroundColor(ZDDesign.cyanAccent)
                            Text(String(format: "%.0f°", result.bearing))
                                .font(.caption.monospaced()).foregroundColor(ZDDesign.safetyYellow)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.caption.bold()).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Add Waypoint Sheet

struct AddWaypointSheet: View {
    @ObservedObject private var manager = DistanceBearingManager.shared
    @State private var name: String = ""
    @State private var latText: String = ""
    @State private var lonText: String = ""
    @State private var mgrsText: String = ""
    @State private var inputMode: InputMode = .latlon
    @Environment(\.dismiss) private var dismiss

    enum InputMode: String, CaseIterable { case latlon = "Lat/Lon"; case mgrs = "MGRS"; case current = "Current" }

    var body: some View {
        NavigationStack {
            Form {
                Section("NAME") {
                    TextField("Waypoint name", text: $name)
                }
                Section("INPUT METHOD") {
                    Picker("", selection: $inputMode) {
                        ForEach(InputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                switch inputMode {
                case .current:
                    Section {
                        HStack {
                            Image(systemName: "location.fill").foregroundColor(ZDDesign.cyanAccent)
                            Text("Will use current GPS location")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                case .latlon:
                    Section("COORDINATES") {
                        TextField("Latitude (e.g. 30.2671)", text: $latText).keyboardType(.numbersAndPunctuation)
                        TextField("Longitude (e.g. -97.7430)", text: $lonText).keyboardType(.numbersAndPunctuation)
                    }
                case .mgrs:
                    Section("MGRS") {
                        TextField("e.g. 14RPU1234567890", text: $mgrsText)
                            .font(.body.monospaced())
                    }
                }
            }
            .navigationTitle("Add Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        switch inputMode {
                        case .current:
                            manager.addCurrentLocation(name: name)
                        case .latlon:
                            guard let lat = Double(latText), let lon = Double(lonText) else { return }
                            manager.add(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), name: name)
                        case .mgrs:
                            guard let coord = NGACoordinates.fromMGRS(mgrsText) else { return }
                            manager.add(coordinate: coord, name: name)
                        }
                        dismiss()
                    }
                    .font(.body.bold()).foregroundColor(ZDDesign.cyanAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
