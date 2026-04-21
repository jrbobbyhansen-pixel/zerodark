// RallyPoint.swift — Primary + alternate rally points with mesh broadcast and ETA
// Supports multiple named sets. Broadcasts via mesh. Computes walking ETA from
// each connected peer's last known location.

import Foundation
import SwiftUI
import CoreLocation

// MARK: - RallyPoint

struct RallyPoint: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var notes: String = ""

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let empty = RallyPoint(name: "", latitude: 0, longitude: 0)
}

// MARK: - RallyPointSet

struct RallyPointSet: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var primary: RallyPoint
    var alternate: RallyPoint?
    var isActive: Bool = false
}

// MARK: - PeerETA

struct PeerETA: Identifiable {
    let id: String   // peer.id
    let peerName: String
    let distanceM: Double
    let etaMinutes: Double   // walking at 1.4 m/s (5 km/h)
}

// MARK: - RallyPointManager

@MainActor
class RallyPointManager: ObservableObject {
    static let shared = RallyPointManager()

    @Published var sets: [RallyPointSet] = []
    @Published var activeSet: RallyPointSet?

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rally_points.json")
    }()

    private let meshPrefix = "[rally]"

    private init() { load() }

    // MARK: - CRUD

    func addSet(_ set: RallyPointSet) {
        sets.append(set)
        save()
    }

    func updateSet(_ set: RallyPointSet) {
        if let i = sets.firstIndex(where: { $0.id == set.id }) {
            sets[i] = set
            save()
        }
    }

    func removeSet(_ set: RallyPointSet) {
        sets.removeAll { $0.id == set.id }
        if activeSet?.id == set.id { activeSet = nil }
        save()
    }

    func activate(_ set: RallyPointSet) {
        for i in sets.indices { sets[i].isActive = false }
        if let i = sets.firstIndex(where: { $0.id == set.id }) {
            sets[i].isActive = true
            activeSet = sets[i]
        }
        save()
        broadcast(set)
    }

    // MARK: - Mesh Broadcast

    func broadcast(_ set: RallyPointSet) {
        guard MeshService.shared.isActive,
              let data = try? JSONEncoder().encode(set),
              let json = String(data: data, encoding: .utf8) else { return }
        MeshService.shared.sendText(meshPrefix + json)
        AuditLogger.shared.log(.rallyPointSet, detail: "broadcast set:\(set.name)")
    }

    /// Handle incoming rally point set from mesh peer
    func handleMeshMessage(_ text: String) {
        guard text.hasPrefix(meshPrefix),
              let data = String(text.dropFirst(meshPrefix.count)).data(using: .utf8),
              let received = try? JSONDecoder().decode(RallyPointSet.self, from: data) else { return }

        if let i = sets.firstIndex(where: { $0.id == received.id }) {
            sets[i] = received
        } else {
            sets.append(received)
        }
        if received.isActive { activeSet = received }
        save()
    }

    // MARK: - ETA Calculation

    /// Walking speed: 1.4 m/s = 5 km/h (NATO standard dismounted pace)
    private let walkingSpeedMps: Double = 1.4

    func peerETAs(to rally: RallyPoint) -> [PeerETA] {
        let dest = CLLocation(latitude: rally.latitude, longitude: rally.longitude)
        return MeshService.shared.peers.compactMap { peer in
            guard let loc = peer.location else { return nil }
            let peerLoc = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            let dist = peerLoc.distance(from: dest)
            let etaMin = dist / walkingSpeedMps / 60.0
            return PeerETA(id: peer.id, peerName: peer.name, distanceM: dist, etaMinutes: etaMin)
        }.sorted { $0.etaMinutes < $1.etaMinutes }
    }

    func selfETA(to rally: RallyPoint) -> Double? {
        guard let loc = LocationManager.shared.currentLocation else { return nil }
        let dest = CLLocation(latitude: rally.latitude, longitude: rally.longitude)
        let selfLoc = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        return selfLoc.distance(from: dest) / walkingSpeedMps / 60.0
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(sets) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([RallyPointSet].self, from: data) else { return }
        sets = loaded
        activeSet = loaded.first { $0.isActive }
    }
}

// MARK: - Rally Point View

struct RallyPointView: View {
    @ObservedObject private var manager = RallyPointManager.shared
    @State private var showAddSheet = false
    @State private var editingSet: RallyPointSet?
    @State private var showETASheet: RallyPointSet?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if manager.sets.isEmpty {
                    emptyState
                } else {
                    setList
                }
            }
            .navigationTitle("Rally Points")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingSet = nil
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                RallyPointSetFormView(set: editingSet) { saved in
                    if editingSet != nil {
                        manager.updateSet(saved)
                    } else {
                        manager.addSet(saved)
                    }
                    showAddSheet = false
                    editingSet = nil
                }
            }
            .sheet(item: $showETASheet) { set in
                RallyETAView(set: set)
                    .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 44)).foregroundColor(.secondary)
            Text("No Rally Points").font(.headline)
            Text("Tap + to add a rally point set.").font(.caption).foregroundColor(.secondary)
            Button {
                showAddSheet = true
            } label: {
                Text("Add Rally Point Set")
                    .font(.subheadline.bold()).foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(ZDDesign.cyanAccent).cornerRadius(10)
            }
        }
    }

    private var setList: some View {
        List {
            ForEach(manager.sets) { set in
                RallySetRow(set: set)
                    .listRowBackground(ZDDesign.darkCard)
                    .onTapGesture { showETASheet = set }
                    .swipeActions(edge: .leading) {
                        Button {
                            manager.activate(set)
                        } label: {
                            Label("Activate", systemImage: "star.fill")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            manager.removeSet(set)
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            editingSet = set
                            showAddSheet = true
                        } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.blue)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Rally Set Row

struct RallySetRow: View {
    let set: RallyPointSet

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((set.isActive ? Color.green : ZDDesign.cyanAccent).opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: set.isActive ? "star.fill" : "mappin")
                    .font(.caption.bold())
                    .foregroundColor(set.isActive ? .green : ZDDesign.cyanAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(set.name).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    if set.isActive {
                        Text("ACTIVE").font(.caption2.bold()).foregroundColor(.green)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15)).cornerRadius(4)
                    }
                }
                HStack(spacing: 8) {
                    Label(set.primary.name, systemImage: "mappin.circle.fill")
                        .font(.caption).foregroundColor(ZDDesign.cyanAccent)
                    if let alt = set.alternate {
                        Text("•").foregroundColor(.secondary)
                        Label(alt.name, systemImage: "mappin.circle")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Rally ETA View

struct RallyETAView: View {
    let set: RallyPointSet
    @ObservedObject private var manager = RallyPointManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        rallyCard(set.primary, label: "PRIMARY")
                        if let alt = set.alternate {
                            rallyCard(alt, label: "ALTERNATE")
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(set.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manager.broadcast(set)
                    } label: {
                        Label("Broadcast", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
        }
    }

    private func rallyCard(_ rally: RallyPoint, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label).font(.caption.bold()).foregroundColor(.secondary)
                Spacer()
                Text(rally.name).font(.headline.bold()).foregroundColor(ZDDesign.pureWhite)
            }

            Text(String(format: "%.6f, %.6f", rally.latitude, rally.longitude))
                .font(.caption.monospaced()).foregroundColor(ZDDesign.cyanAccent).textSelection(.enabled)

            if !rally.notes.isEmpty {
                Text(rally.notes).font(.caption).foregroundColor(.secondary)
            }

            // Self ETA
            if let selfETA = manager.selfETA(to: rally) {
                Divider()
                HStack {
                    Image(systemName: "person.fill").foregroundColor(ZDDesign.cyanAccent)
                    Text("You").font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    Spacer()
                    Text(etaString(selfETA)).font(.subheadline.monospaced()).foregroundColor(ZDDesign.cyanAccent)
                }
            }

            // Peer ETAs
            let etas = manager.peerETAs(to: rally)
            if !etas.isEmpty {
                Divider()
                ForEach(etas) { eta in
                    HStack {
                        Image(systemName: "person").foregroundColor(.secondary)
                        Text(eta.peerName).font(.subheadline).foregroundColor(ZDDesign.pureWhite)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(etaString(eta.etaMinutes)).font(.caption.monospaced()).foregroundColor(.orange)
                            Text(String(format: "%.0fm", eta.distanceM)).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func etaString(_ minutes: Double) -> String {
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return String(format: "%.0f min", minutes) }
        let h = Int(minutes / 60); let m = Int(minutes.truncatingRemainder(dividingBy: 60))
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Rally Point Set Form

struct RallyPointSetFormView: View {
    let set: RallyPointSet?
    let onSave: (RallyPointSet) -> Void

    @State private var name: String
    @State private var primary: RallyPoint
    @State private var alternate: RallyPoint
    @State private var hasAlternate: Bool
    @Environment(\.dismiss) private var dismiss

    init(set: RallyPointSet?, onSave: @escaping (RallyPointSet) -> Void) {
        self.set = set
        self.onSave = onSave
        _name = State(initialValue: set?.name ?? "")
        _primary = State(initialValue: set?.primary ?? RallyPoint(name: "RP Primary", latitude: 0, longitude: 0))
        _alternate = State(initialValue: set?.alternate ?? RallyPoint(name: "RP Alternate", latitude: 0, longitude: 0))
        _hasAlternate = State(initialValue: set?.alternate != nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Set Name") {
                        TextField("e.g. Phase 1 RPs", text: $name)
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Primary Rally Point") {
                        rallyFields(for: $primary)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section {
                        Toggle("Include Alternate RP", isOn: $hasAlternate)
                            .tint(ZDDesign.cyanAccent)
                        if hasAlternate {
                            rallyFields(for: $alternate)
                        }
                    } header: {
                        Text("Alternate Rally Point")
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(set == nil ? "Add Rally Point Set" : "Edit Rally Point Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let newSet = RallyPointSet(
                            id: set?.id ?? UUID(),
                            name: name,
                            primary: primary,
                            alternate: hasAlternate ? alternate : nil,
                            isActive: set?.isActive ?? false
                        )
                        onSave(newSet)
                    }
                    .fontWeight(.bold)
                    .disabled(name.isEmpty || primary.name.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func rallyFields(for rp: Binding<RallyPoint>) -> some View {
        HStack {
            Text("Name").font(.caption).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
            TextField("RP Name", text: rp.name).foregroundColor(ZDDesign.pureWhite)
        }
        HStack {
            Text("Lat").font(.caption).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
            TextField("0.000000", value: rp.latitude, format: .number).keyboardType(.decimalPad).foregroundColor(ZDDesign.pureWhite)
        }
        HStack {
            Text("Lon").font(.caption).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
            TextField("0.000000", value: rp.longitude, format: .number).keyboardType(.decimalPad).foregroundColor(ZDDesign.pureWhite)
        }
        HStack {
            Text("Notes").font(.caption).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
            TextField("Optional notes", text: rp.notes).foregroundColor(ZDDesign.pureWhite)
        }
        Button("Use Current Location") {
            if let loc = LocationManager.shared.currentLocation {
                rp.wrappedValue.latitude = loc.latitude
                rp.wrappedValue.longitude = loc.longitude
            }
        }
        .foregroundColor(ZDDesign.cyanAccent)
    }
}
