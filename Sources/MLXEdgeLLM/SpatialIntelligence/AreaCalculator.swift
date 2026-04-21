// AreaCalculator.swift — Draw polygons on map, calculate enclosed area
// Shoelace formula with spherical correction. Search sectors, LZs, perimeters.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - PolygonPurpose

enum PolygonPurpose: String, CaseIterable, Codable {
    case searchSector = "Search Sector"
    case landingZone  = "Landing Zone"
    case perimeter    = "Perimeter"
    case exclusion    = "Exclusion Zone"
    case objectives   = "Objective Area"
    case general      = "General"

    var color: Color {
        switch self {
        case .searchSector: return ZDDesign.cyanAccent
        case .landingZone:  return ZDDesign.successGreen
        case .perimeter:    return .orange
        case .exclusion:    return ZDDesign.signalRed
        case .objectives:   return ZDDesign.safetyYellow
        case .general:      return ZDDesign.mediumGray
        }
    }
    var icon: String {
        switch self {
        case .searchSector: return "magnifyingglass.circle.fill"
        case .landingZone:  return "airplane.circle.fill"
        case .perimeter:    return "shield.fill"
        case .exclusion:    return "xmark.octagon.fill"
        case .objectives:   return "star.fill"
        case .general:      return "pentagon.fill"
        }
    }
}

// MARK: - TacticalPolygon

struct TacticalPolygon: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var purpose: PolygonPurpose
    var vertices: [VertexCoord]    // ordered CCW
    var notes: String = ""

    struct VertexCoord: Codable {
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        init(_ coord: CLLocationCoordinate2D) { latitude = coord.latitude; longitude = coord.longitude }
    }

    var coordinates: [CLLocationCoordinate2D] { vertices.map(\.coordinate) }

    /// Area in square meters using spherical excess (Girard's theorem approximation).
    var areaSqMeters: Double { AreaCalculatorEngine.area(coordinates: coordinates) }
    var areaHectares: Double { areaSqMeters / 10_000 }
    var areaAcres:    Double { areaSqMeters / 4046.86 }
    var areaSqKm:     Double { areaSqMeters / 1_000_000 }
    var perimeterM:   Double { AreaCalculatorEngine.perimeter(coordinates: coordinates) }

    var centroid: CLLocationCoordinate2D? { AreaCalculatorEngine.centroid(coordinates: coordinates) }
}

// MARK: - AreaCalculatorEngine

enum AreaCalculatorEngine {
    static let R: Double = 6_371_000  // Earth radius m

    /// Shoelace formula on projected (lat/lon in radians) with spherical correction.
    static func area(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 3 else { return 0 }
        var sum = 0.0
        let n = coordinates.count
        for i in 0..<n {
            let a = coordinates[i]
            let b = coordinates[(i + 1) % n]
            let laR = a.latitude * .pi / 180
            let lbR = b.latitude * .pi / 180
            let dLon = (b.longitude - a.longitude) * .pi / 180
            sum += (cos(laR) + cos(lbR)) * dLon
        }
        return abs(sum) * R * R / 2
    }

    static func perimeter(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        var total = 0.0
        let n = coordinates.count
        for i in 0..<n {
            total += DistanceBearingCalc.distance(from: coordinates[i], to: coordinates[(i + 1) % n])
        }
        return total
    }

    static func centroid(coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }
        let lat = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let lon = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - AreaCalculator

@MainActor
final class AreaCalculator: ObservableObject {
    static let shared = AreaCalculator()

    @Published var polygons: [TacticalPolygon] = []
    @Published var draft: [CLLocationCoordinate2D] = []   // in-progress polygon vertices

    private let saveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("area_polygons.json")

    private init() { load() }

    var totalArea: Double { polygons.map(\.areaSqMeters).reduce(0, +) }

    func addVertex(_ coord: CLLocationCoordinate2D) { draft.append(coord) }
    func undoVertex() { if !draft.isEmpty { draft.removeLast() } }
    func clearDraft() { draft = [] }

    func commitPolygon(name: String, purpose: PolygonPurpose, notes: String = "") {
        guard draft.count >= 3 else { return }
        let p = TacticalPolygon(
            name: name,
            purpose: purpose,
            vertices: draft.map { TacticalPolygon.VertexCoord($0) },
            notes: notes
        )
        polygons.append(p)
        draft = []
        save()
    }

    func delete(_ polygon: TacticalPolygon) {
        polygons.removeAll { $0.id == polygon.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(polygons) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([TacticalPolygon].self, from: data) else { return }
        polygons = loaded
    }
}

// MARK: - AreaCalculatorView

struct AreaCalculatorView: View {
    @ObservedObject private var calc = AreaCalculator.shared
    @State private var showCommitSheet = false
    @State private var showList = false
    @State private var mapRegion = MKCoordinateRegion(
        center: LocationManager.shared.currentLocation ?? CLLocationCoordinate2D(latitude: 30.27, longitude: -97.74),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                mapLayer
                VStack {
                    Spacer()
                    bottomPanel
                }
                if !calc.draft.isEmpty {
                    draftInfoBadge
                }
            }
            .navigationTitle("Area Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button { showList = true } label: {
                            Image(systemName: "list.bullet").foregroundColor(ZDDesign.cyanAccent)
                        }
                        if !calc.draft.isEmpty {
                            Button { calc.undoVertex() } label: {
                                Image(systemName: "arrow.uturn.backward").foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCommitSheet) { CommitPolygonSheet() }
            .sheet(isPresented: $showList) { PolygonListView() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Map

    private var mapLayer: some View {
        AreaMapView(
            polygons: calc.polygons,
            draft: calc.draft,
            region: $mapRegion
        ) { coord in
            calc.addVertex(coord)
        }
        .ignoresSafeArea()
    }

    // MARK: - Draft Badge

    private var draftInfoBadge: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(calc.draft.count) vertices")
                        .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                    if calc.draft.count >= 3 {
                        let area = AreaCalculatorEngine.area(coordinates: calc.draft)
                        Text(String(format: "~%.0f m²", area))
                            .font(.caption.bold()).foregroundColor(ZDDesign.pureWhite)
                    }
                }
                .padding(8)
                .background(ZDDesign.darkCard.opacity(0.9))
                .cornerRadius(8)
                .padding(.trailing)
            }
            .padding(.top, 12)
            Spacer()
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if let loc = LocationManager.shared.currentLocation {
                        calc.addVertex(loc)
                    }
                } label: {
                    Label("Add Here", systemImage: "location.fill")
                        .font(.caption.bold()).foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(ZDDesign.cyanAccent).cornerRadius(8)
                }
                if calc.draft.count >= 3 {
                    Button {
                        showCommitSheet = true
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold()).foregroundColor(.black)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(ZDDesign.successGreen).cornerRadius(8)
                    }
                }
                if !calc.draft.isEmpty {
                    Button {
                        calc.clearDraft()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .font(.caption.bold()).foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(ZDDesign.signalRed).cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            Text("Tap map to add vertices, or use Add Here for current GPS")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.bottom, 24)
        .padding(.top, 8)
        .background(ZDDesign.darkCard.opacity(0.9))
    }
}

// MARK: - Area Map View

struct AreaMapView: UIViewRepresentable {
    let polygons: [TacticalPolygon]
    let draft: [CLLocationCoordinate2D]
    @Binding var region: MKCoordinateRegion
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.preferredConfiguration = MKStandardMapConfiguration()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mv.addGestureRecognizer(tap)
        mv.setRegion(region, animated: false)
        return mv
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        uiView.removeOverlays(uiView.overlays)
        // Committed polygons
        for poly in polygons {
            var coords = poly.coordinates
            let overlay = MKPolygon(coordinates: &coords, count: coords.count)
            overlay.title = poly.id.uuidString
            uiView.addOverlay(overlay)
        }
        // Draft polygon/line
        if draft.count >= 2 {
            var d = draft
            let line = MKPolyline(coordinates: &d, count: d.count)
            line.title = "draft"
            uiView.addOverlay(line)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AreaMapView
        init(_ p: AreaMapView) { parent = p }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let mv = gr.view as? MKMapView else { return }
            let pt = gr.location(in: mv)
            let coord = mv.convert(pt, toCoordinateFrom: mv)
            parent.onTap(coord)
        }

        func mapView(_ mv: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: poly)
                // Find purpose color
                let purposeColor = parent.polygons.first { $0.id.uuidString == poly.title }?.purpose.color
                let uiColor = UIColor(purposeColor ?? ZDDesign.cyanAccent)
                r.fillColor = uiColor.withAlphaComponent(0.2)
                r.strokeColor = uiColor.withAlphaComponent(0.8)
                r.lineWidth = 2
                return r
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor(ZDDesign.safetyYellow).withAlphaComponent(0.8)
                r.lineWidth = 2
                r.lineDashPattern = [4, 4]
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Commit Sheet

struct CommitPolygonSheet: View {
    @ObservedObject private var calc = AreaCalculator.shared
    @State private var name = ""
    @State private var purpose: PolygonPurpose = .searchSector
    @State private var notes = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("NAME") { TextField("Sector A, LZ Hawk…", text: $name) }
                Section("PURPOSE") {
                    Picker("", selection: $purpose) {
                        ForEach(PolygonPurpose.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }.pickerStyle(.wheel)
                }
                Section("NOTES") { TextField("Optional…", text: $notes) }
                if calc.draft.count >= 3 {
                    Section("AREA") {
                        let a = AreaCalculatorEngine.area(coordinates: calc.draft)
                        LabeledContent("Area", value: String(format: "%.0f m²  /  %.2f ha", a, a / 10_000))
                        LabeledContent("Perimeter", value: String(format: "%.0f m", AreaCalculatorEngine.perimeter(coordinates: calc.draft)))
                        LabeledContent("Vertices", value: "\(calc.draft.count)")
                    }
                }
            }
            .navigationTitle("Save Polygon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        calc.commitPolygon(name: name.isEmpty ? purpose.rawValue : name, purpose: purpose, notes: notes)
                        dismiss()
                    }
                    .font(.body.bold()).foregroundColor(ZDDesign.cyanAccent)
                    .disabled(calc.draft.count < 3)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Polygon List View

struct PolygonListView: View {
    @ObservedObject private var calc = AreaCalculator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List {
                    if calc.polygons.isEmpty {
                        Text("No polygons saved").font(.subheadline).foregroundColor(.secondary)
                            .listRowBackground(ZDDesign.darkCard)
                    } else {
                        ForEach(calc.polygons) { p in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: p.purpose.icon).foregroundColor(p.purpose.color)
                                    Text(p.name).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                                    Spacer()
                                    Text(p.purpose.rawValue).font(.caption2).foregroundColor(p.purpose.color)
                                }
                                HStack(spacing: 16) {
                                    Text(String(format: "%.0f m²", p.areaSqMeters)).font(.caption.monospaced()).foregroundColor(ZDDesign.cyanAccent)
                                    Text(String(format: "%.2f ha", p.areaHectares)).font(.caption.monospaced()).foregroundColor(.secondary)
                                    Text("\(p.vertices.count) vertices").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .listRowBackground(ZDDesign.darkCard)
                        }
                        .onDelete { calc.polygons.remove(atOffsets: $0) }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Saved Polygons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton().foregroundColor(ZDDesign.cyanAccent) }
            }
        }
        .preferredColorScheme(.dark)
    }
}
