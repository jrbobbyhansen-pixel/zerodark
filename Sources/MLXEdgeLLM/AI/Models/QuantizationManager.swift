import Foundation
import SwiftUI

// MARK: - QuantizationManager

final class QuantizationManager: ObservableObject {
    @Published private(set) var currentQuantizationLevel: QuantizationLevel = .fullPrecision
    
    private let batteryService: BatteryService
    private let modelService: ModelService
    
    init(batteryService: BatteryService, modelService: ModelService) {
        self.batteryService = batteryService
        self.modelService = modelService
        updateQuantizationLevel()
    }
    
    func updateQuantizationLevel() {
        let batteryLevel = batteryService.currentBatteryLevel
        let newLevel = determineQuantizationLevel(from: batteryLevel)
        if newLevel != currentQuantizationLevel {
            currentQuantizationLevel = newLevel
            modelService.applyQuantizationLevel(newLevel)
        }
    }
    
    private func determineQuantizationLevel(from batteryLevel: Double) -> QuantizationLevel {
        switch batteryLevel {
        case 0...20:
            return .int8
        case 21...50:
            return .int16
        default:
            return .fullPrecision
        }
    }
}

// MARK: - QuantizationLevel

enum QuantizationLevel: String, Codable {
    case fullPrecision
    case int8
    case int16
}

// MARK: - BatteryService

protocol BatteryService {
    var currentBatteryLevel: Double { get }
}

// MARK: - ModelService

protocol ModelService {
    func applyQuantizationLevel(_ level: QuantizationLevel)
}