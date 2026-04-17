// IncidentLog.swift — Tactical incident log with GPS auto-tag, attachments, and export
// Records: contact, injury, equipment failure, comms issue, etc.
// Photos saved to Documents/IncidentPhotos. Audio referenced by URL.
// Export: CSV or JSON for debrief/AAR.

import Foundation
import SwiftUI
import CoreLocation
import PhotosUI

// MARK: - IncidentCategory

enum IncidentCategory: String, CaseIterable, Codable {
    case contact         = "Contact"
    case injury          = "Injury"
    case equipment       = "Equipment Failure"
    case comms           = "Comms Issue"
    case navigation      = "Navigation Issue"
    case hazard          = "Hazard"
    case observation     = "Observation"
    case adminLogistics  = "Admin/Logistics"
    case other           = "Other"

    var icon: String {
        switch self {
        case .contact:        return "figure.stand.line.dotted.figure.stand"
        case .injury:         return "cross.case.fill"
        case .equipment:      return "wrench.fill"
        case .comms:          return "antenna.radiowaves.left.and.right.slash"
        case .navigation:     return "location.slash.fill"
        case .hazard:         return "exclamationmark.triangle.fill"
        case .observation:    return "eye.fill"
        case .adminLogistics: return "doc.text.fill"
        case .other:          return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .contact:        return .red
        case .injury:         return .pink
        case .equipment:      return .orange
        case .comms:          return .yellow
        case .navigation:     return .cyan
        case .hazard:         return .red
        case .observation:    return .blue
        case .adminLogistics: return .green
        case .other:          return .gray
        }
    }
}

// MARK: - IncidentEntry

struct IncidentEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var latitude: Double
    var longitude: Double
    var category: IncidentCategory
    var description: String
    var reportedBy: String
    var photoFilenames: [String] = []   // filenames in Documents/IncidentPhotos/
    var audioFilename: String?          // filename in Documents/IncidentAudio/

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - IncidentLogManager

@MainActor
final class IncidentLogManager: ObservableObject {
    static let shared = IncidentLogManager()

    @Published var entries: [IncidentEntry] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("incident_log.json")
    }()
    private let photoDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IncidentPhotos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private let audioDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IncidentAudio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() { load() }

    // MARK: - CRUD

    func add(_ entry: IncidentEntry) {
        entries.insert(entry, at: 0)  // newest first
        save()
        AuditLogger.shared.log(.observationLogged, detail: "incident:\(entry.category.rawValue) at \(entry.latitude),\(entry.longitude)")
    }

    func remove(_ entry: IncidentEntry) {
        // Delete attached files
        for fname in entry.photoFilenames {
            try? FileManager.default.removeItem(at: photoDir.appendingPathComponent(fname))
        }
        if let audio = entry.audioFilename {
            try? FileManager.default.removeItem(at: audioDir.appendingPathComponent(audio))
        }
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Photo Save

    func savePhoto(_ image: UIImage) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let url = photoDir.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return filename
    }

    func photoURL(for filename: String) -> URL {
        photoDir.appendingPathComponent(filename)
    }

    // MARK: - Export

    func exportCSV() -> URL? {
        var csv = "ID,Timestamp,Lat,Lon,Category,Description,ReportedBy,Photos,Audio\n"
        let fmt = ISO8601DateFormatter()
        for e in entries {
            let row = [
                e.id.uuidString,
                fmt.string(from: e.timestamp),
                String(e.latitude),
                String(e.longitude),
                e.category.rawValue,
                "\"\(e.description.replacingOccurrences(of: "\"", with: "\"\""))\"",
                e.reportedBy,
                e.photoFilenames.joined(separator: ";"),
                e.audioFilename ?? ""
            ].joined(separator: ",")
            csv += row + "\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("incident_log_\(Int(Date().timeIntervalSince1970)).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func exportJSON() -> URL? {
        guard let data = try? JSONEncoder().encode(entries) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("incident_log_\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([IncidentEntry].self, from: data) else { return }
        entries = loaded
    }
}

// MARK: - IncidentLogView

struct IncidentLogView: View {
    @ObservedObject private var manager = IncidentLogManager.shared
    @State private var showAddSheet = false
    @State private var filterCategory: IncidentCategory?
    @State private var exportURL: URL?
    @Environment(\.dismiss) private var dismiss

    private var filteredEntries: [IncidentEntry] {
        guard let cat = filterCategory else { return manager.entries }
        return manager.entries.filter { $0.category == cat }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    categoryFilter
                    if filteredEntries.isEmpty {
                        emptyState
                    } else {
                        entryList
                    }
                }
            }
            .navigationTitle("Incident Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Menu {
                            Button("Export CSV", systemImage: "tablecells") {
                                exportURL = manager.exportCSV()
                            }
                            Button("Export JSON", systemImage: "doc.text") {
                                exportURL = manager.exportJSON()
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NewIncidentSheet { entry in
                    manager.add(entry)
                    showAddSheet = false
                }
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
        .preferredColorScheme(.dark)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All") { filterCategory = nil }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(filterCategory == nil ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                    .foregroundColor(filterCategory == nil ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                ForEach(IncidentCategory.allCases, id: \.self) { cat in
                    Button {
                        filterCategory = filterCategory == cat ? nil : cat
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cat.icon).font(.system(size: 9))
                            Text(cat.rawValue).lineLimit(1)
                        }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(filterCategory == cat ? cat.color : ZDDesign.darkCard)
                    .foregroundColor(filterCategory == cat ? .black : ZDDesign.pureWhite)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 44)).foregroundColor(.secondary)
            Text("No Incidents").font(.headline)
            Text("Tap + to log a new incident.").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                IncidentRowView(entry: entry)
                    .listRowBackground(ZDDesign.darkCard)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            manager.remove(entry)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Incident Row

struct IncidentRowView: View {
    let entry: IncidentEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(entry.category.color.opacity(0.2)).frame(width: 36, height: 36)
                Image(systemName: entry.category.icon)
                    .font(.caption.bold()).foregroundColor(entry.category.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.category.rawValue)
                        .font(.caption.bold()).foregroundColor(entry.category.color)
                    Spacer()
                    Text(entry.timestamp, style: .relative)
                        .font(.caption2).foregroundColor(.secondary)
                }
                Text(entry.description).font(.subheadline).foregroundColor(ZDDesign.pureWhite).lineLimit(2)
                HStack(spacing: 8) {
                    Label(entry.reportedBy, systemImage: "person").font(.caption2).foregroundColor(.secondary)
                    Label(String(format: "%.4f, %.4f", entry.latitude, entry.longitude), systemImage: "location")
                        .font(.caption2).foregroundColor(.secondary)
                    if !entry.photoFilenames.isEmpty {
                        Label("\(entry.photoFilenames.count)", systemImage: "photo").font(.caption2).foregroundColor(.secondary)
                    }
                    if entry.audioFilename != nil {
                        Image(systemName: "waveform").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Incident Sheet

struct NewIncidentSheet: View {
    let onSave: (IncidentEntry) -> Void

    @State private var category: IncidentCategory = .observation
    @State private var description: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    @State private var isPickingPhoto = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Category") {
                        Picker("Category", selection: $category) {
                            ForEach(IncidentCategory.allCases, id: \.self) {
                                Label($0.rawValue, systemImage: $0.icon).tag($0)
                            }
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Description") {
                        TextField("What happened?", text: $description, axis: .vertical)
                            .lineLimit(3...6)
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Photos") {
                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: 5,
                            matching: .images
                        ) {
                            Label("Attach Photos (\(pickedImages.count) selected)", systemImage: "photo.badge.plus")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                        .onChange(of: selectedPhotos) { _, items in
                            Task {
                                pickedImages = []
                                for item in items {
                                    if let data = try? await item.loadTransferable(type: Data.self),
                                       let img = UIImage(data: data) {
                                        pickedImages.append(img)
                                    }
                                }
                            }
                        }
                        if !pickedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(pickedImages.enumerated()), id: \.offset) { _, img in
                                        Image(uiImage: img)
                                            .resizable().scaledToFill()
                                            .frame(width: 60, height: 60).clipped().cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Incident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let loc = LocationManager.shared.currentLocation
                            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        var entry = IncidentEntry(
                            latitude: loc.latitude,
                            longitude: loc.longitude,
                            category: category,
                            description: description,
                            reportedBy: AppConfig.deviceCallsign
                        )
                        // Save photos
                        for img in pickedImages {
                            if let fname = IncidentLogManager.shared.savePhoto(img) {
                                entry.photoFilenames.append(fname)
                            }
                        }
                        onSave(entry)
                    }
                    .fontWeight(.bold)
                    .disabled(description.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
