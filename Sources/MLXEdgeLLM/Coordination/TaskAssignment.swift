// TaskAssignment.swift — Team task creation, assignment, and mesh sync
// Create tasks with priority/due time/location, assign to mesh peers or self.
// Broadcasts via mesh. Push notifications for overdue tasks.

import Foundation
import SwiftUI
import CoreLocation
import UserNotifications
import Combine

// MARK: - TaskPriority

enum TaskPriority: String, Codable, CaseIterable {
    case low      = "Low"
    case medium   = "Medium"
    case high     = "High"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .low:      return .green
        case .medium:   return .yellow
        case .high:     return .orange
        case .critical: return .red
        }
    }

    var icon: String {
        switch self {
        case .low:      return "arrow.down.circle"
        case .medium:   return "minus.circle"
        case .high:     return "arrow.up.circle.fill"
        case .critical: return "exclamationmark.2"
        }
    }
}

// MARK: - TaskStatus

enum TaskStatus: String, Codable, CaseIterable {
    case pending    = "Pending"
    case inProgress = "In Progress"
    case complete   = "Complete"
    case overdue    = "Overdue"
}

// MARK: - AssignedTask

struct AssignedTask: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var description: String
    var priority: TaskPriority
    var assignee: String          // callsign or "Unassigned"
    var createdBy: String
    var dueDate: Date
    var latitude: Double?
    var longitude: Double?
    var status: TaskStatus = .pending
    var completedAt: Date?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var isOverdue: Bool {
        status != .complete && Date() > dueDate
    }

    var effectiveStatus: TaskStatus {
        if status == .complete { return .complete }
        if isOverdue { return .overdue }
        return status
    }
}

// MARK: - TaskAssignmentManager

@MainActor
class TaskAssignmentManager: ObservableObject {
    static let shared = TaskAssignmentManager()

    @Published var tasks: [AssignedTask] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("task_assignments.json")
    }()
    private let meshPrefix       = "[task-assign]"
    private let meshCompletePrefix = "[task-complete]"
    private var meshCancellable: AnyCancellable?

    private init() {
        load()
        subscribeMesh()
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - CRUD

    func add(_ task: AssignedTask) {
        tasks.append(task)
        save()
        broadcast(task)
        scheduleNotification(for: task)
    }

    func update(_ task: AssignedTask) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i] = task
            save()
            broadcast(task)
        }
    }

    func remove(_ task: AssignedTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func markComplete(_ task: AssignedTask) {
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i].status = .complete
            tasks[i].completedAt = Date()
            save()
            broadcastComplete(tasks[i])
            AuditLogger.shared.log(.observationLogged, detail: "task complete: \(task.title)")
        }
    }

    // MARK: - Mesh

    private func broadcast(_ task: AssignedTask) {
        guard MeshService.shared.isActive,
              let data = try? JSONEncoder().encode(task),
              let json = String(data: data, encoding: .utf8) else { return }
        MeshService.shared.sendText(meshPrefix + json)
    }

    private func broadcastComplete(_ task: AssignedTask) {
        guard MeshService.shared.isActive,
              let data = try? JSONEncoder().encode(task),
              let json = String(data: data, encoding: .utf8) else { return }
        MeshService.shared.sendText(meshCompletePrefix + json)
    }

    private func subscribeMesh() {
        meshCancellable = NotificationCenter.default
            .publisher(for: Notification.Name("ZD.meshMessage"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let text = notification.userInfo?["text"] as? String else { return }
                self?.handleMeshMessage(text)
            }
    }

    private func handleMeshMessage(_ text: String) {
        let prefix = text.hasPrefix(meshPrefix) ? meshPrefix :
                     (text.hasPrefix(meshCompletePrefix) ? meshCompletePrefix : nil)
        guard let p = prefix,
              let data = String(text.dropFirst(p.count)).data(using: .utf8),
              let received = try? JSONDecoder().decode(AssignedTask.self, from: data) else { return }

        if let i = tasks.firstIndex(where: { $0.id == received.id }) {
            // Only update if received version is newer (completedAt is a proxy)
            if received.status == .complete || tasks[i].status != .complete {
                tasks[i] = received
            }
        } else {
            tasks.append(received)
            // Notify if assigned to self
            if received.assignee == AppConfig.deviceCallsign {
                scheduleNotification(for: received)
            }
        }
        save()
    }

    // MARK: - Notifications

    private func scheduleNotification(for task: AssignedTask) {
        guard task.assignee == AppConfig.deviceCallsign || task.assignee == "Unassigned" else { return }
        let content = UNMutableNotificationContent()
        content.title = "Task Assigned: \(task.title)"
        content.body = "[\(task.priority.rawValue)] Due: \(task.dueDate.formatted(date: .abbreviated, time: .shortened))"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "task.\(task.id.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in }

        // Schedule overdue notification at due time
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueDate)
        let overdueContent = UNMutableNotificationContent()
        overdueContent.title = "Task Overdue: \(task.title)"
        overdueContent.body = "Assigned to \(task.assignee)"
        overdueContent.sound = .defaultCritical
        overdueContent.interruptionLevel = .critical
        let overdueReq = UNNotificationRequest(
            identifier: "task.overdue.\(task.id.uuidString)",
            content: overdueContent,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        UNUserNotificationCenter.current().add(overdueReq) { _ in }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([AssignedTask].self, from: data) else { return }
        tasks = loaded
    }

    // MARK: - Filters

    var myTasks: [AssignedTask] {
        tasks.filter { $0.assignee == AppConfig.deviceCallsign }
    }

    var overdueTasks: [AssignedTask] {
        tasks.filter { $0.isOverdue }
    }
}

// MARK: - Task Assignment View

struct TaskAssignmentView: View {
    @ObservedObject private var manager = TaskAssignmentManager.shared
    @State private var showAddSheet = false
    @State private var editingTask: AssignedTask?
    @State private var filterAssignee: String = "All"
    @Environment(\.dismiss) private var dismiss

    private var teamOptions: [String] {
        var opts = ["All", "Unassigned", AppConfig.deviceCallsign]
        opts += MeshService.shared.peers.map(\.name)
        return opts
    }

    private var filteredTasks: [AssignedTask] {
        let sorted = manager.tasks.sorted {
            let aP = prioritySort($0); let bP = prioritySort($1)
            if aP != bP { return aP < bP }
            return $0.dueDate < $1.dueDate
        }
        if filterAssignee == "All" { return sorted }
        return sorted.filter { $0.assignee == filterAssignee }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    assigneeFilter
                    if filteredTasks.isEmpty {
                        emptyState
                    } else {
                        taskList
                    }
                }
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTask = nil
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus").foregroundColor(ZDDesign.cyanAccent)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                TaskFormView(task: editingTask) { saved in
                    if editingTask != nil { manager.update(saved) }
                    else { manager.add(saved) }
                    showAddSheet = false
                    editingTask = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var assigneeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(teamOptions, id: \.self) { opt in
                    Button(opt) { filterAssignee = opt }
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(filterAssignee == opt ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                        .foregroundColor(filterAssignee == opt ? .black : ZDDesign.pureWhite)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checklist").font(.system(size: 44)).foregroundColor(.secondary)
            Text("No Tasks").font(.headline)
            Text("Tap + to create and assign a task.").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }

    private var taskList: some View {
        List {
            // Overdue banner
            if !manager.overdueTasks.isEmpty && filterAssignee == "All" {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                        Text("\(manager.overdueTasks.count) overdue task\(manager.overdueTasks.count == 1 ? "" : "s")")
                            .font(.subheadline.bold()).foregroundColor(.red)
                    }
                }
                .listRowBackground(Color.red.opacity(0.1))
            }

            ForEach(filteredTasks) { task in
                TaskRowView(task: task)
                    .listRowBackground(ZDDesign.darkCard)
                    .swipeActions(edge: .leading) {
                        if task.status != .complete {
                            Button {
                                manager.markComplete(task)
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                            .tint(.green)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            manager.remove(task)
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            editingTask = task
                            showAddSheet = true
                        } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.blue)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func prioritySort(_ task: AssignedTask) -> Int {
        if task.effectiveStatus == .overdue { return 0 }
        switch task.priority {
        case .critical: return 1
        case .high:     return 2
        case .medium:   return 3
        case .low:      return 4
        }
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let task: AssignedTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.effectiveStatus == .complete ? "checkmark.circle.fill" : task.priority.icon)
                .foregroundColor(task.effectiveStatus == .complete ? .green : task.priority.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(task.title).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite)
                        .strikethrough(task.status == .complete)
                    Spacer()
                    Text(task.priority.rawValue).font(.caption2.bold())
                        .foregroundColor(task.priority.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(task.priority.color.opacity(0.15)).cornerRadius(4)
                }
                HStack(spacing: 10) {
                    Label(task.assignee, systemImage: "person.fill").font(.caption).foregroundColor(.secondary)
                    Divider().frame(height: 12)
                    Label(task.dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "clock").font(.caption).foregroundColor(task.isOverdue ? .red : .secondary)
                }
                if task.status == .complete, let done = task.completedAt {
                    Text("Completed \(done, style: .relative) ago").font(.caption2).foregroundColor(.green)
                } else if task.isOverdue {
                    Text("OVERDUE by \(task.dueDate, style: .relative)").font(.caption2).foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Task Form

struct TaskFormView: View {
    let task: AssignedTask?
    let onSave: (AssignedTask) -> Void

    @State private var title: String
    @State private var description: String
    @State private var priority: TaskPriority
    @State private var assignee: String
    @State private var dueDate: Date
    @State private var useLocation: Bool
    @State private var lat: Double
    @State private var lon: Double
    @Environment(\.dismiss) private var dismiss

    private var teamOptions: [String] {
        var opts = ["Unassigned", AppConfig.deviceCallsign]
        opts += MeshService.shared.peers.map(\.name)
        return opts
    }

    init(task: AssignedTask?, onSave: @escaping (AssignedTask) -> Void) {
        self.task = task
        self.onSave = onSave
        _title       = State(initialValue: task?.title ?? "")
        _description = State(initialValue: task?.description ?? "")
        _priority    = State(initialValue: task?.priority ?? .medium)
        _assignee    = State(initialValue: task?.assignee ?? "Unassigned")
        _dueDate     = State(initialValue: task?.dueDate ?? Date().addingTimeInterval(3600))
        _useLocation = State(initialValue: task?.latitude != nil)
        _lat         = State(initialValue: task?.latitude ?? 0)
        _lon         = State(initialValue: task?.longitude ?? 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section("Task") {
                        TextField("Title", text: $title).foregroundColor(ZDDesign.pureWhite)
                        TextField("Description (optional)", text: $description).foregroundColor(ZDDesign.pureWhite)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Assignment") {
                        Picker("Assignee", selection: $assignee) {
                            ForEach(teamOptions, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Priority", selection: $priority) {
                            ForEach(TaskPriority.allCases, id: \.self) {
                                Label($0.rawValue, systemImage: $0.icon).tag($0)
                            }
                        }
                        DatePicker("Due", selection: $dueDate)
                            .colorScheme(.dark)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    Section("Location (Optional)") {
                        Toggle("Attach Location", isOn: $useLocation).tint(ZDDesign.cyanAccent)
                        if useLocation {
                            HStack {
                                Text("Lat").font(.caption).foregroundColor(.secondary).frame(width: 30)
                                TextField("0.000000", value: $lat, format: .number).keyboardType(.decimalPad).foregroundColor(ZDDesign.pureWhite)
                            }
                            HStack {
                                Text("Lon").font(.caption).foregroundColor(.secondary).frame(width: 30)
                                TextField("0.000000", value: $lon, format: .number).keyboardType(.decimalPad).foregroundColor(ZDDesign.pureWhite)
                            }
                            Button("Use Current Location") {
                                if let loc = LocationManager.shared.currentLocation {
                                    lat = loc.latitude
                                    lon = loc.longitude
                                }
                            }
                            .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let saved = AssignedTask(
                            id: task?.id ?? UUID(),
                            title: title,
                            description: description,
                            priority: priority,
                            assignee: assignee,
                            createdBy: AppConfig.deviceCallsign,
                            dueDate: dueDate,
                            latitude: useLocation ? lat : nil,
                            longitude: useLocation ? lon : nil,
                            status: task?.status ?? .pending,
                            completedAt: task?.completedAt
                        )
                        onSave(saved)
                    }
                    .fontWeight(.bold)
                    .disabled(title.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
