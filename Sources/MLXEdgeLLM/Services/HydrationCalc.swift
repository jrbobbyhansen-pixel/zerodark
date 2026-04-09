import Foundation
import SwiftUI

// MARK: - HydrationCalculator

class HydrationCalculator: ObservableObject {
    @Published var bodyWeight: Double = 70.0 // in kg
    @Published var activityLevel: ActivityLevel = .moderate
    @Published var temperature: Double = 20.0 // in Celsius
    @Published var altitude: Double = 0.0 // in meters
    @Published var waterIntake: Double = 0.0 // in liters
    @Published var dehydrationRisk: DehydrationRisk = .none
    
    private let recommendedIntake: Double = 37.0 // in liters per day for an average adult
    
    enum ActivityLevel: String, CaseIterable {
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
    }
    
    enum DehydrationRisk: String {
        case none = "None"
        case low = "Low"
        case moderate = "Moderate"
        case high = "High"
    }
    
    func calculateWaterNeeds() -> Double {
        let baseIntake = recommendedIntake
        let activityFactor: Double = {
            switch activityLevel {
            case .low: return 0.8
            case .moderate: return 1.0
            case .high: return 1.2
            }
        }()
        
        let temperatureFactor: Double = max(0.0, 1.0 - (temperature - 20.0) / 10.0)
        let altitudeFactor: Double = max(0.0, 1.0 - altitude / 1000.0)
        
        let adjustedIntake = baseIntake * activityFactor * temperatureFactor * altitudeFactor
        return adjustedIntake
    }
    
    func updateDehydrationRisk() {
        let waterNeeds = calculateWaterNeeds()
        let hydrationPercentage = (waterIntake / waterNeeds) * 100
        
        dehydrationRisk = {
            if hydrationPercentage >= 100 {
                return .none
            } else if hydrationPercentage >= 75 {
                return .low
            } else if hydrationPercentage >= 50 {
                return .moderate
            } else {
                return .high
            }
        }()
    }
}

// MARK: - HydrationView

struct HydrationView: View {
    @StateObject private var viewModel = HydrationCalculator()
    
    var body: some View {
        VStack {
            Text("Hydration Calculator")
                .font(.largeTitle)
                .padding()
            
            Form {
                Section(header: Text("Personal Details")) {
                    TextField("Body Weight (kg)", value: $viewModel.bodyWeight, format: .number)
                        .keyboardType(.decimalPad)
                    
                    Picker("Activity Level", selection: $viewModel.activityLevel) {
                        ForEach(HydrationCalculator.ActivityLevel.allCases, id: \.self) {
                            Text($0.rawValue)
                        }
                    }
                }
                
                Section(header: Text("Environmental Factors")) {
                    TextField("Temperature (°C)", value: $viewModel.temperature, format: .number)
                        .keyboardType(.decimalPad)
                    
                    TextField("Altitude (m)", value: $viewModel.altitude, format: .number)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Water Intake")) {
                    TextField("Water Intake (L)", value: $viewModel.waterIntake, format: .number)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Dehydration Risk")) {
                    Text("Risk: \(viewModel.dehydrationRisk.rawValue)")
                        .font(.headline)
                }
            }
            .onChange(of: viewModel.waterIntake) { _ in
                viewModel.updateDehydrationRisk()
            }
            .onChange(of: viewModel.activityLevel) { _ in
                viewModel.updateDehydrationRisk()
            }
            .onChange(of: viewModel.temperature) { _ in
                viewModel.updateDehydrationRisk()
            }
            .onChange(of: viewModel.altitude) { _ in
                viewModel.updateDehydrationRisk()
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct HydrationView_Previews: PreviewProvider {
    static var previews: some View {
        HydrationView()
    }
}