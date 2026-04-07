import SwiftUI
import Foundation
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Task Model

struct Task: Identifiable, Codable {
    let id = UUID()
    var title: String
    var description: String
    var priority: Priority
    var deadline: Date
    var status: Status
    var assignedTo: String
}

enum Priority: String, Codable {
    case low, medium, high
}

enum Status: String, Codable {
    case pending, inProgress, completed
}

// MARK: - Task Assignment ViewModel

class TaskAssignmentViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var newTaskTitle = ""
    @Published var newTaskDescription = ""
    @Published var newTaskPriority: Priority = .medium
    @Published var newTaskDeadline = Date()
    @Published var newTaskAssignedTo = ""
    
    func addTask() {
        let newTask = Task(
            title: newTaskTitle,
            description: newTaskDescription,
            priority: newTaskPriority,
            deadline: newTaskDeadline,
            status: .pending,
            assignedTo: newTaskAssignedTo
        )
        tasks.append(newTask)
        clearNewTaskFields()
    }
    
    func clearNewTaskFields() {
        newTaskTitle = ""
        newTaskDescription = ""
        newTaskPriority = .medium
        newTaskDeadline = Date()
        newTaskAssignedTo = ""
    }
    
    func updateTaskStatus(_ task: Task, newStatus: Status) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].status = newStatus
        }
    }
}

// MARK: - Task Assignment View

struct TaskAssignmentView: View {
    @StateObject private var viewModel = TaskAssignmentViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                List(viewModel.tasks) { task in
                    TaskRow(task: task, viewModel: viewModel)
                }
                
                TaskForm(viewModel: viewModel)
            }
            .navigationTitle("Task Assignment")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        viewModel.addTask()
                    }) {
                        Label("Add Task", systemImage: "plus")
                    }
                }
            }
        }
    }
}

struct TaskRow: View {
    let task: Task
    @ObservedObject var viewModel: TaskAssignmentViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.title)
                    .font(.headline)
                Text(task.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(task.priority.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundColor(task.priority.color)
                Text(task.deadline, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(task.status == .completed ? Color.green.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            viewModel.updateTaskStatus(task, newStatus: task.status == .completed ? .pending : .completed)
        }
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

struct TaskForm: View {
    @ObservedObject var viewModel: TaskAssignmentViewModel
    
    var body: some View {
        Form {
            Section(header: Text("New Task")) {
                TextField("Title", text: $viewModel.newTaskTitle)
                TextField("Description", text: $viewModel.newTaskDescription)
                Picker("Priority", selection: $viewModel.newTaskPriority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(priority.rawValue.capitalized)
                            .tag(priority)
                    }
                }
                DatePicker("Deadline", selection: $viewModel.newTaskDeadline, displayedComponents: .date)
                TextField("Assigned To", text: $viewModel.newTaskAssignedTo)
            }
        }
    }
}

// MARK: - Preview

struct TaskAssignmentView_Previews: PreviewProvider {
    static var previews: some View {
        TaskAssignmentView()
    }
}