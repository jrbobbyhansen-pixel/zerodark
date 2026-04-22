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
//
// PR-C12 split rewarming into active vs passive paths based on the Swiss
// staging system (Durrer et al., Wilderness Med Soc). Passive (shivering,
// insulation, warm fluids) works when the patient can still thermoregulate —
// typically stage 1 and mild stage 2 with intact shiver response. Active
// (heat packs to trunk, forced-air warming, warmed IV) is required when
// shiver has failed or core temp is severely low.

public enum RewarmingMethod: String {
    case passive = "Passive external"
    case activeExternal = "Active external"
    case activeInternal = "Active internal"
    case noneRequired = "None required"

    public var description: String {
        switch self {
        case .passive:
            return "Shelter, dry insulation, warm sweet fluids. Relies on the patient's own shiver to rewarm."
        case .activeExternal:
            return "Heat packs to trunk (axilla, groin, chest), forced-air warming, warmed blankets."
        case .activeInternal:
            return "Warmed IV fluids (40–42 °C), warmed humidified oxygen, consider ECMO at hospital."
        case .noneRequired:
            return "No rewarming needed. Continue monitoring for latent symptoms."
        }
    }
}

public struct RewarmingRecommendations {
    public let stage: HypothermiaStage
    public let primaryMethod: RewarmingMethod
    public let recommendations: [String]

    public init(stage: HypothermiaStage) {
        self.stage = stage
        switch stage {
        case .noRisk:
            self.primaryMethod = .noneRequired
            self.recommendations = [
                "Stay warm and dry.",
                "Monitor for shivering if conditions deteriorate."
            ]
        case .stage1:
            self.primaryMethod = .passive
            self.recommendations = [
                "Passive rewarming: move to a warm environment, change into dry clothes.",
                "Warm sweet fluids if patient can swallow safely.",
                "Expect shivering — this is the body's primary rewarming mechanism.",
                "Monitor every 5 minutes; if shivering stops, escalate to active external."
            ]
        case .stage2:
            self.primaryMethod = .activeExternal
            self.recommendations = [
                "Active external rewarming: heat packs to axilla, groin, chest wall.",
                "Forced-air warming blanket if available; warmed sleeping bag otherwise.",
                "Warm IV fluids if available (NS, 40–42 °C).",
                "Do NOT rewarm extremities aggressively — risk of core afterdrop.",
                "Transport to definitive care; monitor for arrhythmia on handling."
            ]
        case .stage3:
            self.primaryMethod = .activeInternal
            self.recommendations = [
                "Active internal rewarming — hospital level.",
                "Warmed humidified oxygen (40–46 °C) immediately.",
                "Warmed IV crystalloid via large-bore access.",
                "Handle gently — jostling can trigger V-fib in severe hypothermia.",
                "Consider ECMO / cardiopulmonary bypass at receiving facility.",
                "\"Not dead until warm and dead\": continue CPR even with prolonged arrest."
            ]
        }
    }
}