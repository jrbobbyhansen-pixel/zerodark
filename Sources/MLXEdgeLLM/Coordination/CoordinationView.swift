// CoordinationView.swift — Incident, Unit, and Search Pattern Coordination UI
// Main interface for managing emergency response operations

import SwiftUI
import CoreLocation

struct CoordinationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navViewModel: NavigationViewModel
    @ObservedObject var store = IncidentStore.shared
    @StateObject private var sarModel = LandSARSearchModel()
    @State private var showNewIncidentSheet = false
    @State private var showPatternGenerator = false
    @State private var selectedIncident: Incident?
    @State private var sarSubjectType: SAR_SubjectType = .lostHiker
    @State private var sarRadius: Double = 2000

    var body: some View {
        NavigationStack {
            List {
                // Active Incidents Section
                Section(header: Label("Active Incidents", systemImage: "exclamationmark.triangle.fill")) {
                    if store.incidents.filter({ $0.status == .active }).isEmpty {
                        Text("No active incidents")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(store.incidents.filter({ $0.status == .active })) { incident in
                            NavigationLink(destination: IncidentDetailView(incident: incident)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(incident.title)
                                            .font(.headline)
                                        Spacer()
                                        PriorityBadge(priority: incident.priority)
                                    }
                                    Text(incident.summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 12) {
                                        Image(systemName: "person.2.fill")
                                            .font(.caption)
                                        Text("\(incident.assignments.count) assigned")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(incident.timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // Personnel Section
                Section(header: Label("Personnel (\(store.units.count))", systemImage: "person.3.fill")) {
                    if store.units.isEmpty {
                        Text("No units assigned")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(store.units) { unit in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(unit.callsign)
                                            .font(.headline)
                                        Spacer()
                                        UnitStatusBadge(status: unit.status)
                                    }
                                    HStack(spacing: 12) {
                                        if let location = unit.location {
                                            Image(systemName: "location.fill")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                            Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image(systemName: batteryIcon(unit.battery))
                                                .font(.caption)
                                                .foregroundColor(batteryColor(unit.battery))
                                            Text("\(unit.battery)%")
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Search Patterns Section
                Section(header: Label("Search Patterns", systemImage: "map.fill")) {
                    NavigationLink(destination: PatternGeneratorView()) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                                .foregroundColor(.cyan)
                            Text("Generate Search Pattern")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Search & Rescue (LandSAR) Section
                Section(header: Label("Search & Rescue", systemImage: "figure.wave")) {
                    Picker("Subject Type", selection: $sarSubjectType) {
                        ForEach(SAR_SubjectType.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    VStack(alignment: .leading) {
                        Text("Search Radius: \(Int(sarRadius))m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $sarRadius, in: 500...10000, step: 500)
                    }

                    Button("Initialize Probability Grid") {
                        // Initialize SAR grid at current location (default to 0,0 for testing)
                        let center = CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        sarModel.initializeGrid(
                            center: center,
                            radiusMeters: sarRadius,
                            subjectType: sarSubjectType
                        )
                    }
                    .font(.caption)
                    .foregroundColor(ZDDesign.cyanAccent)

                    if !sarModel.cells.isEmpty {
                        let pocPercent = sarModel.totalPOC * 100
                        let pocColor: Color = pocPercent > 50 ? ZDDesign.signalRed : pocPercent > 20 ? ZDDesign.safetyYellow : ZDDesign.successGreen

                        HStack {
                            Text("POC Remaining: \(String(format: "%.1f", pocPercent))%")
                                .font(.caption)
                                .bold()
                            Spacer()
                        }
                        .foregroundColor(pocColor)

                        if let rec = sarModel.recommendedCell {
                            Text("Next sector: \(String(format: "%.4f", rec.coordinate.latitude)), \(String(format: "%.4f", rec.coordinate.longitude))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Button("Mark Recommended Sector Searched (POD 70%)") {
                            if let rec = sarModel.recommendedCell {
                                sarModel.markCellSearched(cellId: rec.id, pod: 0.7)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(ZDDesign.forestGreen)
                    }
                }

                // Recent Incidents Section
                if store.incidents.filter({ $0.status != .active }).count > 0 {
                    Section(header: Label("Resolved Incidents", systemImage: "checkmark.circle.fill")) {
                        ForEach(store.incidents.filter({ $0.status != .active })) { incident in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(incident.title)
                                    .font(.headline)
                                Text(incident.status.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Operations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showNewIncidentSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showNewIncidentSheet) {
                NewIncidentSheet()
            }
        }
    }

    private func batteryIcon(_ percent: Int) -> String {
        switch percent {
        case 75...100: return "battery.100"
        case 50...74: return "battery.75"
        case 25...49: return "battery.50"
        case 1...24: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryColor(_ percent: Int) -> Color {
        if percent > 50 {
            return .green
        } else if percent > 20 {
            return .orange
        } else {
            return .red
        }
    }
}

struct PriorityBadge: View {
    let priority: IncidentPriority

    var body: some View {
        Text(priority.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priorityColor(priority))
            .cornerRadius(4)
    }

    private func priorityColor(_ priority: IncidentPriority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .red.opacity(0.8)
        }
    }
}

struct UnitStatusBadge: View {
    let status: UnitStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
            Text(status.rawValue)
                .font(.caption2)
        }
        .foregroundColor(statusColor(status))
    }

    private func statusColor(_ status: UnitStatus) -> Color {
        switch status {
        case .available: return .green
        case .assigned: return .blue
        case .enroute: return .yellow
        case .onScene: return .orange
        case .offline: return .gray
        }
    }
}

struct NewIncidentSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store = IncidentStore.shared
    @State private var title = ""
    @State private var summary = ""
    @State private var priority: IncidentPriority = .medium
    @State private var reporter = AppConfig.deviceCallsign
    @State private var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    var body: some View {
        NavigationStack {
            Form {
                Section("Incident Details") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...5)
                    Picker("Priority", selection: $priority) {
                        ForEach(IncidentPriority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                }

                Section("Reporter") {
                    TextField("Callsign", text: $reporter)
                }

                Section("Location") {
                    Text(String(format: "%.4f°, %.4f°", coordinate.latitude, coordinate.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Use Current Location") {
                        coordinate = CLLocationCoordinate2D(
                            latitude: 37.7749,  // Example: SF
                            longitude: -122.4194
                        )
                    }
                }
            }
            .navigationTitle("New Incident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        store.createIncident(
                            title: title,
                            summary: summary,
                            coordinate: coordinate,
                            priority: priority,
                            reporter: reporter
                        )
                        dismiss()
                    }
                    .disabled(title.isEmpty || summary.isEmpty)
                }
            }
        }
    }
}

struct IncidentDetailView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store = IncidentStore.shared
    let incident: Incident
    @State private var showAssignSheet = false

    var currentIncident: Incident? {
        store.incidents.first(where: { $0.id == incident.id })
    }

    var body: some View {
        NavigationStack {
            if let current = currentIncident {
                List {
                    Section("Incident") {
                        LabeledContent("Title", value: current.title)
                        LabeledContent("Priority", value: current.priority.rawValue)
                        LabeledContent("Status", value: current.status.rawValue)
                        LabeledContent("Reporter", value: current.reporter)
                    }

                    Section("Location") {
                        LabeledContent("Latitude", value: String(format: "%.8f", current.coordinate.latitude))
                        LabeledContent("Longitude", value: String(format: "%.8f", current.coordinate.longitude))
                    }

                    Section("Summary") {
                        Text(current.summary)
                    }

                    Section("Assigned Units (\(current.assignments.count))") {
                        if current.assignments.isEmpty {
                            Text("No units assigned")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(current.assignments) { assignment in
                                if let unit = store.units.first(where: { $0.id == assignment.unitId }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(unit.callsign)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            UnitStatusBadge(status: unit.status)
                                        }
                                        if let eta = assignment.eta {
                                            Text("ETA: \(eta.formatted(date: .omitted, time: .shortened))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if !assignment.note.isEmpty {
                                            Text(assignment.note)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        Button(action: { showAssignSheet = true }) {
                            Label("Assign Unit", systemImage: "plus")
                        }
                    }

                    Section("Actions") {
                        Button(role: .destructive) {
                            store.resolveIncident(current.id)
                            dismiss()
                        } label: {
                            Label("Resolve Incident", systemImage: "checkmark.circle.fill")
                        }
                    }
                }
                .navigationTitle(current.title)
                .sheet(isPresented: $showAssignSheet) {
                    AssignUnitSheet(incidentId: current.id)
                }
            }
        }
    }
}

struct AssignUnitSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store = IncidentStore.shared
    let incidentId: UUID
    @State private var selectedUnitId: UUID?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Unit") {
                    Picker("Unit", selection: $selectedUnitId) {
                        Text("Choose a unit...").tag(UUID?(nil))
                        ForEach(store.units) { unit in
                            Text(unit.callsign).tag(UUID?(unit.id))
                        }
                    }
                }

                Section("Assignment Note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Assign Unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Assign") {
                        if let unitId = selectedUnitId {
                            store.assignUnit(unitId, to: incidentId, note: note)
                        }
                        dismiss()
                    }
                    .disabled(selectedUnitId == nil)
                }
            }
        }
    }
}

struct PatternGeneratorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var navViewModel: NavigationViewModel
    @State private var patternType: SearchPattern.PatternType = .expandingSquare
    @State private var trackSpacing: Double = 100
    @State private var searchRadius: Double = 500
    @State private var legLength: Double = 1000
    @State private var searchWidth: Double = 500
    @State private var numSectors: Int = 8
    @State private var generatedPattern: SearchPattern?

    var body: some View {
        NavigationStack {
            Form {
                Section("Pattern Type") {
                    Picker("Type", selection: $patternType) {
                        Text("Expanding Square").tag(SearchPattern.PatternType.expandingSquare)
                        Text("Creeping Line").tag(SearchPattern.PatternType.creepingLine)
                        Text("Sector Sweep").tag(SearchPattern.PatternType.sectorSweep)
                    }
                }

                switch patternType {
                case .expandingSquare:
                    Section("Parameters") {
                        HStack {
                            Text("Track Spacing")
                            Spacer()
                            Stepper(value: $trackSpacing, in: 50...500, step: 50) {
                                Text("\(Int(trackSpacing))m")
                            }
                        }
                    }

                case .creepingLine:
                    Section("Parameters") {
                        HStack {
                            Text("Search Width")
                            Spacer()
                            Stepper(value: $searchWidth, in: 100...2000, step: 100) {
                                Text("\(Int(searchWidth))m")
                            }
                        }
                        HStack {
                            Text("Leg Length")
                            Spacer()
                            Stepper(value: $legLength, in: 500...5000, step: 500) {
                                Text("\(Int(legLength))m")
                            }
                        }
                    }

                case .sectorSweep:
                    Section("Parameters") {
                        HStack {
                            Text("Search Radius")
                            Spacer()
                            Stepper(value: $searchRadius, in: 100...5000, step: 100) {
                                Text("\(Int(searchRadius))m")
                            }
                        }
                        HStack {
                            Text("Number of Sectors")
                            Spacer()
                            Stepper(value: $numSectors, in: 4...16, step: 1) {
                                Text("\(numSectors)")
                            }
                        }
                    }
                }

                if let pattern = generatedPattern {
                    Section("Generated Pattern") {
                        LabeledContent("Waypoints", value: "\(pattern.waypoints.count)")
                        LabeledContent("Coverage", value: String(format: "%.0f m²", pattern.coverageArea))
                        LabeledContent("Est. Duration", value: formatDuration(pattern.estimatedDuration))
                        Button(action: loadIntoNavigation) {
                            Label("Load into Navigation", systemImage: "map.fill")
                                .foregroundColor(.cyan)
                        }
                    }
                }

                Section {
                    Button(action: generatePattern) {
                        Label("Generate Pattern", systemImage: "waveform.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Search Pattern Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func generatePattern() {
        let origin = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        generatedPattern = switch patternType {
        case .expandingSquare:
            SearchPattern.expandingSquare(origin: origin, trackSpacing: trackSpacing)
        case .creepingLine:
            SearchPattern.creepingLine(origin: origin, width: searchWidth, legs: 5, legLength: legLength)
        case .sectorSweep:
            SearchPattern.sectorSweep(origin: origin, radius: searchRadius, sectors: numSectors)
        }
    }

    private func loadIntoNavigation() {
        guard let pattern = generatedPattern else { return }

        // Wire to NavigationViewModel - convert coordinates to Waypoints
        let newWaypoints = pattern.waypoints.enumerated().map { index, coord in
            Waypoint(
                name: "SP-\(index + 1)",
                coordinate: coord,
                altitude: 0,
                timestamp: Date(),
                lidarFingerprint: nil
            )
        }
        navViewModel.waypoints.append(contentsOf: newWaypoints)

        dismiss()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}

#Preview {
    CoordinationView()
}
