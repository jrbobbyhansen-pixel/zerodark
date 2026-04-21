// PointCloudAnnotator.swift — Label, mark, and annotate LiDAR scans
// Mark hazards, features, objectives. Persist with scan data. Mesh-share.

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - AnnotationType

enum AnnotationType: String, CaseIterable, Codable {
    case hazard     = "Hazard"
    case objective  = "Objective"
    case feature    = "Feature"
    case waypoint   = "Waypoint"
    case note       = "Note"
    case breach     = "Breach Point"
    case cover      = "Cover/Concealment"
    case obstacle   = "Obstacle"

    var icon: String {
        switch self {
        case .hazard:    return "exclamationmark.triangle.fill"
        case .objective: return "star.fill"
        case .feature:   return "mappin.circle.fill"
        case .waypoint:  return "location.fill"
        case .note:      return "note.text"
        case .breach:    return "door.left.hand.open"
        case .cover:     return "shield.fill"
        case .obstacle:  return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .hazard:    return ZDDesign.signalRed
        case .objective: return ZDDesign.safetyYellow
        case .feature:   return ZDDesign.cyanAccent
        case .waypoint:  return .blue
        case .note:      return ZDDesign.mediumGray
        case .breach:    return .orange
        case .cover:     return ZDDesign.successGreen
        case .obstacle:  return .purple
        }
    }
}

// MARK: - ScanAnnotation

struct ScanAnnotation: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var latitude: Double
    var longitude: Double
    var altitudeM: Double
    var type: AnnotationType
    var label: String
    var notes: String
    var scanID: UUID?           // nil = not attached to a specific scan
    var createdBy: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var mgrs: String {
        MGRSConverter.toMGRS(coordinate: coordinate, precision: 4)
    }
}

// MARK: - PointCloudAnnotationManager

@MainActor
final class PointCloudAnnotationManager: ObservableObject {
    static let shared = PointCloudAnnotationManager()

    @Published var annotations: [ScanAnnotation] = []
    @Published var selectedAnnotation: ScanAnnotation?

    private let saveURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("scan_annotations.json")

    private init() { load() }

    // MARK: - CRUD

    func add(type: AnnotationType, label: String, notes: String = "", scanID: UUID? = nil) {
        let loc = LocationManager.shared.currentLocation
        let annotation = ScanAnnotation(
            latitude: loc?.latitude ?? 0,
            longitude: loc?.longitude ?? 0,
            altitudeM: 0,
            type: type,
            label: label,
            notes: notes,
            scanID: scanID,
            createdBy: AppConfig.deviceCallsign
        )
        annotations.insert(annotation, at: 0)
        save()
        MeshService.shared.sendText("[scan-annotation]\(annotation.label) [\(annotation.type.rawValue)] \(annotation.mgrs)")
    }

    func add(coordinate: CLLocationCoordinate2D, altM: Double = 0,
             type: AnnotationType, label: String, notes: String = "", scanID: UUID? = nil) {
        let annotation = ScanAnnotation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitudeM: altM,
            type: type,
            label: label,
            notes: notes,
            scanID: scanID,
            createdBy: AppConfig.deviceCallsign
        )
        annotations.insert(annotation, at: 0)
        save()
    }

    func delete(_ annotation: ScanAnnotation) {
        annotations.removeAll { $0.id == annotation.id }
        save()
    }

    func annotations(forScan scanID: UUID) -> [ScanAnnotation] {
        annotations.filter { $0.scanID == scanID }
    }

    func annotations(ofType type: AnnotationType) -> [ScanAnnotation] {
        annotations.filter { $0.type == type }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(annotations) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([ScanAnnotation].self, from: data) else { return }
        annotations = loaded
    }
}

// MARK: - PointCloudAnnotatorView

struct PointCloudAnnotatorView: View {
    @ObservedObject private var manager = PointCloudAnnotationManager.shared
    @State private var showAddSheet = false
    @State private var filterType: AnnotationType? = nil
    @State private var selectedAnnotation: ScanAnnotation? = nil
    @State private var showMap = true
    @Environment(\.dismiss) private var dismiss

    private var filtered: [ScanAnnotation] {
        guard let ft = filterType else { return manager.annotations }
        return manager.annotations.filter { $0.type == ft }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    typeFilter
                    if showMap {
                        mapView
                    }
                    annotationList
                }
            }
            .navigationTitle("Scan Annotations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            showMap.toggle()
                        } label: {
                            Image(systemName: showMap ? "list.bullet" : "map.fill")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button { showAddSheet = true } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) { AddAnnotationSheet() }
            .sheet(item: $selectedAnnotation) { AnnotationDetailView(annotation: $0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Type Filter

    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All") { filterType = nil }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(filterType == nil ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                    .foregroundColor(filterType == nil ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                ForEach(AnnotationType.allCases, id: \.self) { t in
                    Button {
                        filterType = filterType == t ? nil : t
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: t.icon).font(.system(size: 9))
                            Text(t.rawValue)
                        }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(filterType == t ? t.color : ZDDesign.darkCard)
                    .foregroundColor(filterType == t ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    // MARK: - Map View

    private var mapView: some View {
        AnnotationMapView(annotations: filtered, selected: $selectedAnnotation)
            .frame(height: 220)
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 8)
    }

    // MARK: - List

    private var annotationList: some View {
        List {
            if filtered.isEmpty {
                Text("No annotations yet").font(.subheadline).foregroundColor(.secondary)
                    .listRowBackground(ZDDesign.darkCard)
            } else {
                ForEach(filtered) { ann in
                    Button { selectedAnnotation = ann } label: {
                        annotationRow(ann)
                    }
                    .listRowBackground(ZDDesign.darkCard)
                    .swipeActions {
                        Button(role: .destructive) {
                            manager.delete(ann)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func annotationRow(_ ann: ScanAnnotation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ann.type.icon)
                .foregroundColor(ann.type.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(ann.label).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text(ann.type.rawValue).font(.caption2).foregroundColor(ann.type.color)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(ann.type.color.opacity(0.15))
                        .cornerRadius(4)
                }
                Text(ann.mgrs).font(.caption2.monospaced()).foregroundColor(.secondary)
                if !ann.notes.isEmpty {
                    Text(ann.notes).font(.caption).foregroundColor(ZDDesign.mediumGray).lineLimit(1)
                }
            }
            Spacer()
            Text(ann.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospaced()).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Annotation Map View

struct AnnotationMapView: UIViewRepresentable {
    let annotations: [ScanAnnotation]
    @Binding var selected: ScanAnnotation?

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.preferredConfiguration = MKStandardMapConfiguration()
        return mv
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeAnnotations(uiView.annotations)
        let mkAnns = annotations.map { ScanMKAnnotation(scan: $0) }
        uiView.addAnnotations(mkAnns)
        if let first = annotations.first {
            let region = MKCoordinateRegion(center: first.coordinate,
                                            latitudinalMeters: 500, longitudinalMeters: 500)
            uiView.setRegion(region, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AnnotationMapView
        init(_ p: AnnotationMapView) { parent = p }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? ScanMKAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "scan") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "scan")
            view.glyphText = String(a.scan.label.prefix(1))
            view.markerTintColor = UIColor(a.scan.type.color)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let a = view.annotation as? ScanMKAnnotation {
                Task { @MainActor in self.parent.selected = a.scan }
            }
        }
    }
}

private class ScanMKAnnotation: NSObject, MKAnnotation {
    let scan: ScanAnnotation
    var coordinate: CLLocationCoordinate2D { scan.coordinate }
    var title: String? { scan.label }
    var subtitle: String? { scan.type.rawValue }
    init(scan: ScanAnnotation) { self.scan = scan }
}

// MARK: - Add Annotation Sheet

struct AddAnnotationSheet: View {
    @ObservedObject private var manager = PointCloudAnnotationManager.shared
    @State private var type: AnnotationType = .note
    @State private var label: String = ""
    @State private var notes: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("TYPE") {
                    Picker("", selection: $type) {
                        ForEach(AnnotationType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Section("LABEL") {
                    TextField("Breach point, IED hazard, LZ…", text: $label)
                }
                Section("NOTES") {
                    TextField("Additional details…", text: $notes)
                }
                Section {
                    HStack {
                        Image(systemName: "location.fill").foregroundColor(ZDDesign.cyanAccent)
                        Text("Will tag current GPS location")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("New Annotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard !label.isEmpty else { return }
                        manager.add(type: type, label: label, notes: notes)
                        dismiss()
                    }
                    .font(.body.bold()).foregroundColor(ZDDesign.cyanAccent)
                    .disabled(label.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Annotation Detail View

struct AnnotationDetailView: View {
    let annotation: ScanAnnotation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Image(systemName: annotation.type.icon)
                            .font(.system(size: 44)).foregroundColor(annotation.type.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(annotation.label).font(.title3.bold()).foregroundColor(ZDDesign.pureWhite)
                            Text(annotation.type.rawValue).font(.caption).foregroundColor(annotation.type.color)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(ZDDesign.darkCard).cornerRadius(12)

                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Location", annotation.mgrs)
                        detailRow("Created by", annotation.createdBy)
                        detailRow("Time", annotation.timestamp.formatted(date: .abbreviated, time: .shortened))
                        if !annotation.notes.isEmpty {
                            detailRow("Notes", annotation.notes)
                        }
                    }
                    .padding()
                    .background(ZDDesign.darkCard).cornerRadius(12)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Annotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.bold()).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text(value).font(.caption).foregroundColor(ZDDesign.pureWhite)
            Spacer()
        }
    }
}
