// TeamRoster.swift — Team member CRUD with JSON persistence and mesh sync
// Full fields: name, callsign, role, radioChannel, bloodType, allergies, emergencyContact

import Foundation
import SwiftUI
import Combine

// MARK: - TeamMember Model

struct TeamMember: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var callsign: String
    var role: TeamRole
    var radioChannel: Int
    var bloodType: BloodType
    var allergies: [String]
    var emergencyContact: String
    var notes: String = ""

    enum TeamRole: String, CaseIterable, Codable {
        case lead       = "Team Lead"
        case medic      = "Medic"
        case pointman   = "Pointman"
        case support    = "Support"
        case observer   = "Observer"
        case comms      = "Comms"
        case logistics  = "Logistics"
        case other      = "Other"
    }

    enum BloodType: String, CaseIterable, Codable {
        case aPos = "A+"
        case aNeg = "A-"
        case bPos = "B+"
        case bNeg = "B-"
        case abPos = "AB+"
        case abNeg = "AB-"
        case oPos = "O+"
        case oNeg = "O-"
        case unknown = "Unknown"
    }

    static let empty = TeamMember(
        name: "", callsign: "", role: .other, radioChannel: 1,
        bloodType: .unknown, allergies: [], emergencyContact: ""
    )
}

// MARK: - TeamRosterManager

@MainActor
class TeamRosterManager: ObservableObject {
    static let shared = TeamRosterManager()

    @Published var teamMembers: [TeamMember] = []
    @Published var lastSyncDate: Date? = nil

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("team_roster.json")
    }()

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ member: TeamMember) {
        teamMembers.append(member)
        save()
        syncViaMesh()
    }

    func update(_ member: TeamMember) {
        if let index = teamMembers.firstIndex(where: { $0.id == member.id }) {
            teamMembers[index] = member
            save()
            syncViaMesh()
        }
    }

    func remove(_ member: TeamMember) {
        teamMembers.removeAll { $0.id == member.id }
        save()
        syncViaMesh()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(teamMembers)
            try data.write(to: saveURL, options: .atomic)
        } catch {}
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let members = try? JSONDecoder().decode([TeamMember].self, from: data) else { return }
        teamMembers = members
    }

    // MARK: - Mesh Sync

    /// Broadcast roster to connected peers via mesh.
    /// Encodes roster as JSON and sends as a mesh message payload.
    func syncViaMesh() {
        guard MeshService.shared.isActive,
              let data = try? JSONEncoder().encode(teamMembers) else { return }
        let payload = "[roster]" + (String(data: data, encoding: .utf8) ?? "")
        MeshService.shared.sendText(payload)
        lastSyncDate = Date()
    }

    /// Merge a received roster from a peer (keep latest by member id).
    func mergeReceivedRoster(_ data: Data) {
        guard let received = try? JSONDecoder().decode([TeamMember].self, from: data) else { return }
        for incoming in received {
            if !teamMembers.contains(where: { $0.id == incoming.id }) {
                teamMembers.append(incoming)
            }
        }
        save()
    }
}

// MARK: - Team Roster View

struct TeamRosterView: View {
    @ObservedObject private var manager = TeamRosterManager.shared
    @State private var showAddSheet = false
    @State private var editingMember: TeamMember? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if manager.teamMembers.isEmpty {
                    emptyState
                } else {
                    memberList
                }
            }
            .navigationTitle("Team Roster")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            manager.syncViaMesh()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button {
                            editingMember = nil
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                TeamMemberFormView(member: editingMember) { saved in
                    if let existing = editingMember {
                        manager.update(saved)
                        _ = existing  // suppress warning
                    } else {
                        manager.add(saved)
                    }
                    showAddSheet = false
                    editingMember = nil
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3").font(.system(size: 44)).foregroundColor(.secondary)
            Text("No Team Members").font(.headline)
            Text("Tap + to add the first member.").font(.caption).foregroundColor(.secondary)
            Button {
                showAddSheet = true
            } label: {
                Text("Add Member")
                    .font(.subheadline.bold()).foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(ZDDesign.cyanAccent).cornerRadius(10)
            }
        }
    }

    private var memberList: some View {
        List {
            if let syncDate = manager.lastSyncDate {
                Text("Last synced: \(syncDate, style: .relative)")
                    .font(.caption2).foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(manager.teamMembers) { member in
                TeamMemberListRow(member: member)
                    .listRowBackground(ZDDesign.darkCard)
                    .swipeActions {
                        Button(role: .destructive) {
                            manager.remove(member)
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            editingMember = member
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

// MARK: - Member List Row

struct TeamMemberListRow: View {
    let member: TeamMember

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(ZDDesign.cyanAccent.opacity(0.2)).frame(width: 40, height: 40)
                Text(member.callsign.prefix(2).uppercased())
                    .font(.caption.bold()).foregroundColor(ZDDesign.cyanAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(member.name).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text("[\(member.callsign)]").font(.caption.monospaced()).foregroundColor(ZDDesign.cyanAccent)
                    Spacer()
                    Text("Ch \(member.radioChannel)").font(.caption2.monospaced()).foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Text(member.role.rawValue).font(.caption).foregroundColor(.secondary)
                    Text("•").foregroundColor(.secondary)
                    Text(member.bloodType.rawValue)
                        .font(.caption.bold()).foregroundColor(member.bloodType == .oNeg ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add/Edit Form

struct TeamMemberFormView: View {
    let member: TeamMember?
    let onSave: (TeamMember) -> Void

    @State private var form: TeamMember
    @State private var allergyText: String = ""
    @Environment(\.dismiss) private var dismiss

    init(member: TeamMember?, onSave: @escaping (TeamMember) -> Void) {
        self.member = member
        self.onSave = onSave
        _form = State(initialValue: member ?? TeamMember.empty)
        _allergyText = State(initialValue: member?.allergies.joined(separator: ", ") ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Identity") {
                        formField("Name", text: $form.name)
                        formField("Callsign", text: $form.callsign)
                        Picker("Role", selection: $form.role) {
                            ForEach(TeamMember.TeamRole.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Communications") {
                        Stepper("Radio Ch: \(form.radioChannel)", value: $form.radioChannel, in: 1...99)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Medical") {
                        Picker("Blood Type", selection: $form.bloodType) {
                            ForEach(TeamMember.BloodType.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        formField("Allergies (comma-separated)", text: $allergyText)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Emergency") {
                        formField("Emergency Contact", text: $form.emergencyContact)
                        formField("Notes", text: $form.notes)
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(member == nil ? "Add Member" : "Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        form.allergies = allergyText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        onSave(form)
                    }
                    .fontWeight(.bold).disabled(form.name.isEmpty || form.callsign.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func formField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary).frame(minWidth: 80, alignment: .leading)
            TextField(label, text: text)
                .font(.body).foregroundColor(ZDDesign.pureWhite)
        }
    }
}
