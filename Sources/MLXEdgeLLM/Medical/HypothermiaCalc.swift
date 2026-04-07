import Foundation
import SwiftUI

// MARK: - Hypothermia Risk Calculator

struct HypothermiaRiskCalculator {
    // Constants for the Swiss staging system
    private static let stage1Threshold = 35.0
    private static let stage2Threshold = 32.0
    private static let stage3Threshold = 28.0
    
    // Calculate the hypothermia risk based on temperature, wind, wetness, and activity level
    func calculateRisk(temperature: Double, windSpeed: Double, wetness: Bool, activityLevel: ActivityLevel) -> HypothermiaStage {
        let adjustedTemperature = calculateAdjustedTemperature(temperature: temperature, windSpeed: windSpeed, wetness: wetness)
        let metabolicRate = calculateMetabolicRate(activityLevel: activityLevel)
        
        if adjustedTemperature > stage1Threshold {
            return .noRisk
        } else if adjustedTemperature > stage2Threshold {
            return .stage1
        } else if adjustedTemperature > stage3Threshold {
            return .stage2
        } else {
            return .stage3
        }
    }
    
    // Adjust temperature based on wind chill and wetness
    private func calculateAdjustedTemperature(temperature: Double, windSpeed: Double, wetness: Bool) -> Double {
        let windChill = calculateWindChill(temperature: temperature, windSpeed: windSpeed)
        return wetness ? windChill - 2.0 : windChill
    }
    
    // Calculate wind chill using the formula
    private func calculateWindChill(temperature: Double, windSpeed: Double) -> Double {
        if temperature > 10 || windSpeed < 4.8 {
            return temperature
        }
        let windChill = 13.12 + 0.6215 * temperature - 11.37 * pow(windSpeed, 0.16) + 0.3965 * temperature * pow(windSpeed, 0.16)
        return windChill
    }
    
    // Calculate metabolic rate based on activity level
    private func calculateMetabolicRate(activityLevel: ActivityLevel) -> Double {
        switch activityLevel {
        case .sedentary:
            return 1.0
        case .light:
            return 1.3
        case .moderate:
            return 1.6
        case .heavy:
            return 2.0
        }
    }
}

// MARK: - Hypothermia Stage

enum HypothermiaStage: String, Identifiable {
    case noRisk = "No Risk"
    case stage1 = "Stage 1: Mild Hypothermia"
    case stage2 = "Stage 2: Moderate Hypothermia"
    case stage3 = "Stage 3: Severe Hypothermia"
    
    var id: String { self.rawValue }
}

// MARK: - Activity Level

enum ActivityLevel: String, Identifiable {
    case sedentary = "Sedentary"
    case light = "Light Activity"
    case moderate = "Moderate Activity"
    case heavy = "Heavy Activity"
    
    var id: String { self.rawValue }
}

// MARK: - ViewModel

class HypothermiaViewModel: ObservableObject {
    @Published var temperature: Double = 0.0
    @Published var windSpeed: Double = 0.0
    @Published var wetness: Bool = false
    @Published var activityLevel: ActivityLevel = .sedentary
    @Published var riskStage: HypothermiaStage = .noRisk
    
    private let calculator = HypothermiaRiskCalculator()
    
    func calculateRisk() {
        riskStage = calculator.calculateRisk(temperature: temperature, windSpeed: windSpeed, wetness: wetness, activityLevel: activityLevel)
    }
}

// MARK: - Rewarming Recommendations

struct RewarmingRecommendations {
    let stage: HypothermiaStage
    let recommendations: [String]
}

extension RewarmingRecommendations {
    init(stage: HypothermiaStage) {
        self.stage = stage
        switch stage {
        case .noRisk:
            self.recommendations = ["Stay warm and dry."]
        case .stage1:
            self.recommendations = ["Move to a warm environment.", "Change into dry clothes.", "Drink warm fluids."]
        case .stage2:
            self.recommendations = ["Seek medical attention.", "Warm the body gradually.", "Avoid hot baths or showers."]
        case .stage3:
            self.recommendations = ["Emergency medical care is required.", "Do not attempt to warm the body.", "Handle gently and seek immediate help."]
        }
    }
}