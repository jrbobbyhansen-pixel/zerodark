import Foundation
import SwiftUI
import CoreLocation

// MARK: - PaceCalculator

class PaceCalculator: ObservableObject {
    @Published var terrainType: TerrainType = .flat
    @Published var loadWeight: Double = 0.0 // in kilograms
    @Published var fitnessLevel: FitnessLevel = .average
    @Published var weatherCondition: WeatherCondition = .clear
    @Published var distance: CLLocationDistance = 1000.0 // in meters
    @Published var estimatedTime: TimeInterval = 0.0

    func calculatePace() {
        let baseSpeed = baseSpeed(for: terrainType, fitnessLevel: fitnessLevel)
        let loadFactor = loadFactor(for: loadWeight)
        let weatherFactor = weatherFactor(for: weatherCondition)
        
        let adjustedSpeed = baseSpeed * loadFactor * weatherFactor
        estimatedTime = distance / adjustedSpeed
    }

    private func baseSpeed(for terrain: TerrainType, fitnessLevel: FitnessLevel) -> Double {
        switch terrain {
        case .flat:
            return fitnessLevel.baseSpeedOnFlat
        case .hilly:
            return fitnessLevel.baseSpeedOnHilly
        case .mountainous:
            return fitnessLevel.baseSpeedOnMountainous
        }
    }

    private func loadFactor(for weight: Double) -> Double {
        // Naismith's rule correction for load
        return 1.0 - (weight / 100.0) * 0.05
    }

    private func weatherFactor(for condition: WeatherCondition) -> Double {
        switch condition {
        case .clear:
            return 1.0
        case .rainy:
            return 0.8
        case .snowy:
            return 0.5
        }
    }
}

// MARK: - TerrainType

enum TerrainType {
    case flat
    case hilly
    case mountainous
}

// MARK: - FitnessLevel

enum FitnessLevel {
    case beginner
    case average
    case advanced

    var baseSpeedOnFlat: Double {
        switch self {
        case .beginner:
            return 4.0 // km/h
        case .average:
            return 5.0 // km/h
        case .advanced:
            return 6.0 // km/h
        }
    }

    var baseSpeedOnHilly: Double {
        switch self {
        case .beginner:
            return 3.0 // km/h
        case .average:
            return 4.0 // km/h
        case .advanced:
            return 5.0 // km/h
        }
    }

    var baseSpeedOnMountainous: Double {
        switch self {
        case .beginner:
            return 2.0 // km/h
        case .average:
            return 3.0 // km/h
        case .advanced:
            return 4.0 // km/h
        }
    }
}

// MARK: - WeatherCondition

enum WeatherCondition {
    case clear
    case rainy
    case snowy
}