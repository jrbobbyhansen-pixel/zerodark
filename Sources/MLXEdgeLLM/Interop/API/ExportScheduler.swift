import Foundation
import SwiftUI
import Combine

// MARK: - ExportScheduler

class ExportScheduler: ObservableObject {
    @Published var exportTasks: [ExportTask] = []
    @Published var lastExportResult: ExportResult?
    
    private var cancellables = Set<AnyCancellable>()
    
    func scheduleExport(format: ExportFormat, destination: URL) {
        let task = ExportTask(format: format, destination: destination)
        exportTasks.append(task)
        
        task.$status
            .dropFirst()
            .filter { $0 == .completed || $0 == .failed }
            .sink { [weak self] status in
                self?.lastExportResult = ExportResult(task: task, status: status)
                self?.exportTasks.removeAll { $0.id == task.id }
            }
            .store(in: &cancellables)
        
        task.start()
    }
}

// MARK: - ExportTask

class ExportTask: ObservableObject, Identifiable {
    let id = UUID()
    let format: ExportFormat
    let destination: URL
    
    @Published var status: ExportStatus = .pending
    
    init(format: ExportFormat, destination: URL) {
        self.format = format
        self.destination = destination
    }
    
    func start() {
        status = .inProgress
        // Simulate export process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            let success = Bool.random()
            self.status = success ? .completed : .failed
        }
    }
}

// MARK: - ExportFormat

enum ExportFormat {
    case csv
    case json
    case xml
}

// MARK: - ExportStatus

enum ExportStatus {
    case pending
    case inProgress
    case completed
    case failed
}

// MARK: - ExportResult

struct ExportResult {
    let task: ExportTask
    let status: ExportStatus
}