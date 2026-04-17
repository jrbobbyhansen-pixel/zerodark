// ShiftScheduler.swift — Watch schedule management with fatigue tracking and mesh alerts
// Assigns watch/duty shifts, computes rest debt and fatigue risk (FAID-style model),
// fires UNNotifications for shift handovers, broadcasts via mesh.

import Foundation
import SwiftUI
import UserNotifications

// MARK: - ShiftType

enum ShiftType: String, CaseIterable, Codable {
    case watch        = "Watch"
    case patrol       = "Patrol"
    case rest         = "Rest"
    case standby      = "Standby"
    case maintenance  = "Maintenance"

    var icon: String {
        switch self {
        case .watch:       return "eye.fill"
        case .patrol:      return "figure.walk"
        case .rest:        return "moon.fill"
        case .standby:     return "antenna.radiowaves.left.and.right"
        case .maintenance: return "wrench.fill"
        }
    }

    var color: Color {
        switch self {
        case .watch:       return .blue
        case .patrol:      return .green
        case .rest:        return .indigo
        case .standby:     return .yellow
        case .maintenance: return .orange
        }
    }
}

// MARK: - WatchShift

struct WatchShift: Identifiable, Codable {
    var id: UUID = UUID()
    var assignee: String          // callsign
    var type: ShiftType
    var startTime: Date
    var durationHours: Double     // hours
    var notes: String = ""

    var endTime: Date { startTime.addingTimeInterval(durationHours * 3600) }

    var isActive: Bool {
        let now = Date()
        return now >= startTime && now < endTime
    }

    var isUpcoming: Bool {
        startTime > Date() && startTime <= Date().addingTimeInterval(3600) // within 1h
    }
}

// MARK: - FatigueProfile (per person)

struct FatigueProfile: Identifiable {
    let id: String        // callsign
    var totalRestHours24h: Double
    var totalDutyHours24h: Double
    var totalRestHours72h: Double
    var totalDutyHours72h: Double

    /// Rest debt in last 24h (should have ~8h rest / 24h)
    var restDebt24h: Double {
        max(0, 8.0 - totalRestHours24h)
    }

    /// Simple FAID-style fatigue risk score 0–100
    var fatigueScore: Double {
        let debtFactor = min(1, restDebt24h / 8.0)
        let durationFactor = min(1, totalDutyHours24h / 18)
        return min(100, (debtFactor * 0.6 + durationFactor * 0.4) * 100)
    }

    var riskLabel: String {
        switch fatigueScore {
        case 75...: return "High Risk"
        case 50..<75: return "Elevated"
        case 25..<50: return "Moderate"
        default: return "Low"
        }
    }

    var riskColor: Color {
        switch fatigueScore {
        case 75...: return .red
        case 50..<75: return .orange
        case 25..<50: return .yellow
        default: return .green
        }
    }
}

// MARK: - ShiftScheduleManager

@MainActor
final class ShiftScheduleManager: ObservableObject {
    static let shared = ShiftScheduleManager()

    @Published var shifts: [WatchShift] = []
    @Published var fatigueProfiles: [FatigueProfile] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shift_schedule.json")
    }()
    private let meshPrefix = "[shift-alert]"

    private init() {
        load()
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        refreshFatigue()
    }

    // MARK: - CRUD

    func add(_ shift: WatchShift) {
        shifts.append(shift)
        shifts.sort { $0.startTime < $1.startTime }
        save()
        scheduleNotification(for: shift)
        broadcastShiftAssigned(shift)
        refreshFatigue()
    }

    func update(_ shift: WatchShift) {
        if let i = shifts.firstIndex(where: { $0.id == shift.id }) {
            shifts[i] = shift
            save()
            scheduleNotification(for: shift)
            refreshFatigue()
        }
    }

    func remove(_ shift: WatchShift) {
        shifts.removeAll { $0.id == shift.id }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [shift.id.uuidString])
        save()
        refreshFatigue()
    }

    var activeShifts: [WatchShift] { shifts.filter(\.isActive) }
    var upcomingShifts: [WatchShift] { shifts.filter(\.isUpcoming) }

    // MARK: - Fatigue

    func refreshFatigue() {
        let now = Date()
        let window24 = now.addingTimeInterval(-86400)
        let window72 = now.addingTimeInterval(-3 * 86400)

        var callsigns = Set(shifts.map(\.assignee))
        callsigns.insert(AppConfig.deviceCallsign)
        MeshService.shared.peers.forEach { callsigns.insert($0.name) }

        fatigueProfiles = callsigns.map { callsign in
            let s24 = shifts.filter { $0.assignee == callsign && $0.startTime >= window24 }
            let s72 = shifts.filter { $0.assignee == callsign && $0.startTime >= window72 }
            let dutyTypes: Set<ShiftType> = [.watch, .patrol, .standby, .maintenance]
            return FatigueProfile(
                id: callsign,
                totalRestHours24h: s24.filter { $0.type == .rest }.map(\.durationHours).reduce(0, +),
                totalDutyHours24h: s24.filter { dutyTypes.contains($0.type) }.map(\.durationHours).reduce(0, +),
                totalRestHours72h: s72.filter { $0.type == .rest }.map(\.durationHours).reduce(0, +),
                totalDutyHours72h: s72.filter { dutyTypes.contains($0.type) }.map(\.durationHours).reduce(0, +)
            )
        }.sorted { $0.fatigueScore > $1.fatigueScore }
    }

    // MARK: - Mesh

    private func broadcastShiftAssigned(_ shift: WatchShift) {
        guard MeshService.shared.isActive else { return }
        MeshService.shared.sendText("\(meshPrefix)\(shift.assignee):\(shift.type.rawValue) @ \(shift.startTime.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: - Notifications

    private func scheduleNotification(for shift: WatchShift) {
        let alertTime = shift.startTime.addingTimeInterval(-15 * 60)
        guard alertTime > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Shift in 15 min: \(shift.type.rawValue)"
        content.body = "Assigned to \(shift.assignee) — \(String(format: "%.0fh", shift.durationHours))"
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertTime)
        let req = UNNotificationRequest(
            identifier: shift.id.uuidString, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(shifts) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([WatchShift].self, from: data) else { return }
        shifts = loaded
    }
}

// MARK: - Shift Scheduler View

struct ShiftSchedulerView: View {
    @ObservedObject private var manager = ShiftScheduleManager.shared
    @State private var showAddSheet = false
    @State private var editingShift: WatchShift?
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("View", selection: $selectedTab) {
                        Text("Schedule").tag(0)
                        Text("Fatigue").tag(1)
                    }
                    .pickerStyle(.segmented).padding()

                    if selectedTab == 0 { scheduleView } else { fatigueView }
                }
            }
            .navigationTitle("Shift Scheduler")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingShift = nil; showAddSheet = true } label: {
                        Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                ShiftFormView(shift: editingShift) { saved in
                    if editingShift != nil { manager.update(saved) }
                    else { manager.add(saved) }
                    showAddSheet = false
                    editingShift = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var scheduleView: some View {
        Group {
            if manager.shifts.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "calendar.badge.clock").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("No Shifts Scheduled").font(.headline)
                    Text("Tap + to add watch/duty shifts.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    if !manager.activeShifts.isEmpty {
                        Section("Active Now") {
                            ForEach(manager.activeShifts) { shift in
                                ShiftRowView(shift: shift, isActive: true).listRowBackground(ZDDesign.darkCard)
                            }
                        }
                    }
                    Section("All Shifts") {
                        ForEach(manager.shifts) { shift in
                            ShiftRowView(shift: shift, isActive: shift.isActive)
                                .listRowBackground(ZDDesign.darkCard)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { manager.remove(shift) } label: { Label("Delete", systemImage: "trash") }
                                    Button { editingShift = shift; showAddSheet = true } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            }
        }
    }

    private var fatigueView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(manager.fatigueProfiles) { profile in
                    FatigueProfileCard(profile: profile)
                }
            }
            .padding()
        }
    }
}

// MARK: - Shift Row

struct ShiftRowView: View {
    let shift: WatchShift
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(shift.type.color.opacity(isActive ? 0.3 : 0.1)).frame(width: 36, height: 36)
                Image(systemName: shift.type.icon).font(.caption.bold())
                    .foregroundColor(isActive ? shift.type.color : .secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(shift.assignee).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                    Text(shift.type.rawValue).font(.caption).foregroundColor(shift.type.color)
                    if isActive {
                        Text("LIVE").font(.caption2.bold()).foregroundColor(.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.15)).cornerRadius(4)
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    Text(shift.startTime.formatted(date: .abbreviated, time: .shortened))
                    Text("→")
                    Text(shift.endTime.formatted(date: .omitted, time: .shortened))
                    Text("(\(String(format: "%.0fh", shift.durationHours)))")
                }
                .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Fatigue Card

struct FatigueProfileCard: View {
    let profile: FatigueProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.id).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Text(profile.riskLabel).font(.caption.bold())
                    .foregroundColor(profile.riskColor)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(profile.riskColor.opacity(0.15)).cornerRadius(6)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                    Capsule().fill(profile.riskColor)
                        .frame(width: geo.size.width * CGFloat(profile.fatigueScore / 100), height: 6)
                }
            }.frame(height: 6)
            HStack(spacing: 16) {
                infoCell("Duty 24h", String(format: "%.0fh", profile.totalDutyHours24h))
                infoCell("Rest 24h", String(format: "%.0fh", profile.totalRestHours24h))
                infoCell("Rest Debt", String(format: "%.0fh", profile.restDebt24h), color: profile.restDebt24h > 0 ? .orange : .green)
                infoCell("Score", String(format: "%.0f", profile.fatigueScore), color: profile.riskColor)
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private func infoCell(_ label: String, _ value: String, color: Color = ZDDesign.pureWhite) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.monospaced()).foregroundColor(color)
        }
    }
}

// MARK: - Shift Form

struct ShiftFormView: View {
    let shift: WatchShift?
    let onSave: (WatchShift) -> Void

    @State private var assignee: String
    @State private var type: ShiftType
    @State private var startTime: Date
    @State private var durationHours: Double
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    private var teamOptions: [String] {
        var opts = [AppConfig.deviceCallsign]
        opts += MeshService.shared.peers.map(\.name)
        return opts
    }

    init(shift: WatchShift?, onSave: @escaping (WatchShift) -> Void) {
        self.shift = shift
        self.onSave = onSave
        _assignee      = State(initialValue: shift?.assignee ?? AppConfig.deviceCallsign)
        _type          = State(initialValue: shift?.type ?? .watch)
        _startTime     = State(initialValue: shift?.startTime ?? Date())
        _durationHours = State(initialValue: shift?.durationHours ?? 2)
        _notes         = State(initialValue: shift?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Assignment") {
                        Picker("Assignee", selection: $assignee) {
                            ForEach(teamOptions, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Type", selection: $type) {
                            ForEach(ShiftType.allCases, id: \.self) {
                                Label($0.rawValue, systemImage: $0.icon).tag($0)
                            }
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                    Section("Schedule") {
                        DatePicker("Start", selection: $startTime).colorScheme(.dark)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Duration: \(String(format: "%.0fh", durationHours))")
                                .font(.caption).foregroundColor(.secondary)
                            Slider(value: $durationHours, in: 0.5...12, step: 0.5).tint(ZDDesign.cyanAccent)
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                    Section("Notes") {
                        TextField("Optional", text: $notes).foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(shift == nil ? "Add Shift" : "Edit Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(WatchShift(
                            id: shift?.id ?? UUID(), assignee: assignee,
                            type: type, startTime: startTime,
                            durationHours: durationHours, notes: notes
                        ))
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
