import Foundation
import SwiftUI

// MARK: - ModelSwitcher

class ModelSwitcher: ObservableObject {
    @Published private(set) var currentModel: LLMModel
    
    init() {
        self.currentModel = .small
    }
    
    func switchModel(for task: TaskType) {
        switch task {
        case .simpleQuery:
            currentModel = .small
        case .complexReasoning:
            currentModel = .large
        }
    }
}

// MARK: - LLMModel

enum LLMModel {
    case small
    case large
}

// MARK: - TaskType

enum TaskType {
    case simpleQuery
    case complexReasoning
}

// MARK: - BatteryAwareModelSelector

class BatteryAwareModelSelector: ObservableObject {
    @Published private(set) var selectedModel: LLMModel
    
    init() {
        self.selectedModel = .small
        NotificationCenter.default.addObserver(self, selector: #selector(batteryLevelDidChange), name: UIDevice.batteryLevelDidChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
    }
    
    @objc private func batteryLevelDidChange() {
        if UIDevice.current.batteryLevel < 0.2 {
            selectedModel = .small
        } else {
            selectedModel = .large
        }
    }
}