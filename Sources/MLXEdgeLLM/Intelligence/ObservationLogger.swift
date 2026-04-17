// ObservationLogger.swift — Field observation logging with location and bearing
// Records observations with GPS coordinates for pattern analysis

import Foundation
import SwiftUI
import CoreLocation

// MARK: - FieldObservation

struct FieldObservation: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let bearing: Double
    let distance: Double
    let description: String
    let category: ObservationCategory

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(location: CLLocationCoordinate2D, bearing: Double, distance: Double, description: String, category: ObservationCategory = .general) {
        self.id = UUID()
        self.timestamp = Date()
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.bearing = bearing
        self.distance = distance
        self.description = description
        self.category = category
    }

    enum ObservationCategory: String, CaseIterable, Codable {
        case general    = "General"
        case movement   = "Movement"
        case structure  = "Structure"
        case hazard     = "Hazard"
        case resource   = "Resource"
        case personnel  = "Personnel"
    }
}

// MARK: - FieldObservationLogger

@MainActor
final class ObservationLogger: ObservableObject {
    static let shared = ObservationLogger()

    @Published var observations: [FieldObservation] = []
    @Published var exportURL: URL?

    private init() { load() }

    func logObservation(bearing: Double, distance: Double, description: String, category: FieldObservation.ObservationCategory = .general) {
        let location = LocationManager.shared.lastKnownLocation
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let obs = FieldObservation(location: location, bearing: bearing, distance: distance, description: description, category: category)
        observations.append(obs)
        save()
        AuditLogger.shared.log(.observationLogged, detail: category.rawValue)
    }

    func remove(at offsets: IndexSet) {
        observations.remove(atOffsets: offsets)
        save()
    }

    func exportText() -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short

        var text = "OBSERVATION LOG\n═══════════════\n\n"
        for (i, obs) in observations.enumerated() {
            text += "\(i+1). [\(obs.category.rawValue)] \(fmt.string(from: obs.timestamp))\n"
            text += "   \(obs.description)\n"
            text += "   Bearing: \(String(format: "%.0f", obs.bearing))° | Distance: \(String(format: "%.0f", obs.distance))m\n"
            text += "   Location: \(String(format: "%.5f", obs.latitude)), \(String(format: "%.5f", obs.longitude))\n\n"
        }
        return text
    }

    func share() {
        let text = exportText()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("ObservationLog-\(Int(Date().timeIntervalSince1970)).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
    }

    // MARK: - Persistence

    private let persistURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("observations.json")
    }()

    private func save() {
        guard let data = try? JSONEncoder().encode(observations) else { return }
        try? data.write(to: persistURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistURL),
              let loaded = try? JSONDecoder().decode([FieldObservation].self, from: data) else { return }
        observations = loaded
    }
}

// MARK: - FieldObservationLoggerView

struct ObservationLoggerView: View {
    @ObservedObject private var logger = ObservationLogger.shared
    @State private var showAdd = false
    @State private var newDesc = ""
    @State private var newBearing = ""
    @State private var newDistance = ""
    @State private var newCategory: FieldObservation.ObservationCategory = .general

    var body: some View {
        Form {
            Section("Log Observation") {
                TextField("Description", text: $newDesc)
                HStack {
                    TextField("Bearing (°)", text: $newBearing).keyboardType(.decimalPad).frame(maxWidth: 100)
                    TextField("Distance (m)", text: $newDistance).keyboardType(.decimalPad)
                }
                Picker("Category", selection: $newCategory) {
                    ForEach(FieldObservation.ObservationCategory.allCases, id: \.self) { Text($0.rawValue) }
                }
                Button {
                    logger.logObservation(
                        bearing: Double(newBearing) ?? 0,
                        distance: Double(newDistance) ?? 0,
                        description: newDesc,
                        category: newCategory
                    )
                    newDesc = ""; newBearing = ""; newDistance = ""
                } label: {
                    Label("Log", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(ZDDesign.cyanAccent)
                .disabled(newDesc.isEmpty)
            }

            if !logger.observations.isEmpty {
                Section("Observations (\(logger.observations.count))") {
                    ForEach(logger.observations.reversed()) { obs in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("[\(obs.category.rawValue)]").font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
                                Spacer()
                                Text(obs.timestamp, style: .time).font(.caption).foregroundColor(.secondary)
                            }
                            Text(obs.description).font(.subheadline)
                            Text("Bearing \(String(format: "%.0f", obs.bearing))° | \(String(format: "%.0f", obs.distance))m")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { logger.remove(at: $0) }
                }

                Section {
                    Button { logger.share() } label: {
                        Label("Export Log", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Observation Log")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $logger.exportURL) { url in
            ShareSheet(items: [url])
        }
    }
}

#Preview {
    NavigationStack { ObservationLoggerView() }
}
