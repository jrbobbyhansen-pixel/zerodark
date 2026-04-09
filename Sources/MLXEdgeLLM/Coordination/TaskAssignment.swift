import Foundation
import SwiftUI
import CoreLocation

// MARK: - Task Model

struct AssignedTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String
    var priority: TaskPriority
    var dueDate: Date
    var location: CLLocationCoordinate2D
    var isCompleted: Bool = false
}

enum TaskPriority: String, Codable {
    case low, medium, high
}

// MARK: - Task Assignment Service

class TaskAssignmentService: ObservableObject {
    @Published private(set) var tasks: [AssignedTask] = []
    
    func addTask(title: String, description: String, priority: TaskPriority, dueDate: Date, location: CLLocationCoordinate2D) {
        let newTask = Task(id: UUID(), title: title, description: description, priority: priority, dueDate: dueDate, location: location)
        tasks.append(newTask)
    }
    
    func markTaskAsCompleted(id: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].isCompleted = true
        }
    }
    
    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
    }
}

// MARK: - Task Assignment View Model

class TaskAssignmentViewModel: ObservableObject {
    @Published var tasks: [AssignedTask] = []
    @Published var newTaskTitle: String = ""
    @Published var newTaskDescription: String = ""
    @Published var newTaskPriority: TaskPriority = .medium
    @Published var newTaskDueDate: Date = Date()
    @Published var newTaskLocation: CLLocationCoordinate2D?
    
    private let taskService: TaskAssignmentService
    
    init(taskService: TaskAssignmentService) {
        self.taskService = taskService
        self.tasks = taskService.tasks
    }
    
    func addTask() {
        guard let location = newTaskLocation else { return }
        taskService.addTask(title: newTaskTitle, description: newTaskDescription, priority: newTaskPriority, dueDate: newTaskDueDate, location: location)
        clearForm()
    }
    
    func markTaskAsCompleted(id: UUID) {
        taskService.markTaskAsCompleted(id: id)
    }
    
    func removeTask(id: UUID) {
        taskService.removeTask(id: id)
    }
    
    private func clearForm() {
        newTaskTitle = ""
        newTaskDescription = ""
        newTaskPriority = .medium
        newTaskDueDate = Date()
        newTaskLocation = nil
    }
}

// MARK: - Task Assignment View

struct TaskAssignmentView: View {
    @StateObject private var viewModel = TaskAssignmentViewModel(taskService: TaskAssignmentService())
    
    var body: some View {
        NavigationView {
            VStack {
                TaskFormView(viewModel: viewModel)
                TaskListView(tasks: viewModel.tasks, viewModel: viewModel)
            }
            .navigationTitle("Task Assignment")
        }
    }
}

struct TaskFormView: View {
    @ObservedObject var viewModel: TaskAssignmentViewModel
    
    var body: some View {
        Form {
            Section(header: Text("New Task")) {
                TextField("Title", text: $viewModel.newTaskTitle)
                TextField("Description", text: $viewModel.newTaskDescription)
                Picker("Priority", selection: $viewModel.newTaskPriority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Text(priority.rawValue.capitalized)
                    }
                }
                DatePicker("Due Date", selection: $viewModel.newTaskDueDate, displayedComponents: .date)
                if let location = viewModel.newTaskLocation {
                    Text("Location: \(location.latitude), \(location.longitude)")
                }
            }
            Button(action: viewModel.addTask) {
                Text("Add Task")
            }
            .disabled(viewModel.newTaskTitle.isEmpty || viewModel.newTaskLocation == nil)
        }
    }
}

struct TaskListView: View {
    let tasks: [AssignedTask]
    @ObservedObject var viewModel: TaskAssignmentViewModel
    
    var body: some View {
        List(tasks) { task in
            TaskRowView(task: task, viewModel: viewModel)
        }
    }
}

struct TaskRowView: View {
    let task: Task
    @ObservedObject var viewModel: TaskAssignmentViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(task.title)
                    .font(.headline)
                Text(task.description)
                    .font(.subheadline)
                Text("Due: \(task.dueDate, style: .date)")
                    .font(.caption)
            }
            Spacer()
            Button(action: {
                viewModel.markTaskAsCompleted(id: task.id)
            }) {
                Text(task.isCompleted ? "Completed" : "Mark as Completed")
                    .foregroundColor(task.isCompleted ? .green : .blue)
            }
            Button(action: {
                viewModel.removeTask(id: task.id)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
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