import Foundation
import SwiftUI

// MARK: - BurnCalculator

class BurnCalculator: ObservableObject {
    @Published var burnPercentage: Double = 0.0
    @Published var fluidResuscitation: Double = 0.0
    @Published var errorMessage: String? = nil
    
    func calculateRuleOfNines(burnArea: Double) {
        guard burnArea >= 0 && burnArea <= 100 else {
            errorMessage = "Burn area must be between 0% and 100%"
            return
        }
        
        burnPercentage = burnArea
        calculateFluidResuscitation()
    }
    
    func calculateLundBrowder(burnArea: Double, age: Int, weight: Double) {
        guard burnArea >= 0 && burnArea <= 100, age > 0, weight > 0 else {
            errorMessage = "Invalid input values"
            return
        }
        
        let lundBrowderFactor: Double
        if age < 10 {
            lundBrowderFactor = 0.4
        } else if age < 18 {
            lundBrowderFactor = 0.5
        } else {
            lundBrowderFactor = 0.4
        }
        
        burnPercentage = burnArea * lundBrowderFactor
        calculateFluidResuscitation()
    }
    
    private func calculateFluidResuscitation() {
        fluidResuscitation = burnPercentage * weight * 4
    }
}

// MARK: - BurnCalculatorView

struct BurnCalculatorView: View {
    @StateObject private var calculator = BurnCalculator()
    @State private var burnArea: Double = 0.0
    @State private var age: Int = 0
    @State private var weight: Double = 0.0
    @State private var useRuleOfNines = true
    
    var body: some View {
        VStack {
            Toggle("Use Rule of Nines", isOn: $useRuleOfNines)
                .padding()
            
            if useRuleOfNines {
                TextField("Burn Area (%)", value: $burnArea, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
                    .padding()
            } else {
                VStack {
                    TextField("Burn Area (%)", value: $burnArea, formatter: NumberFormatter())
                        .keyboardType(.decimalPad)
                        .padding()
                    
                    TextField("Age", value: $age, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .padding()
                    
                    TextField("Weight (kg)", value: $weight, formatter: NumberFormatter())
                        .keyboardType(.decimalPad)
                        .padding()
                }
            }
            
            Button("Calculate") {
                if useRuleOfNines {
                    calculator.calculateRuleOfNines(burnArea: burnArea)
                } else {
                    calculator.calculateLundBrowder(burnArea: burnArea, age: age, weight: weight)
                }
            }
            .padding()
            
            if let errorMessage = calculator.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Text("Burn Percentage: \(String(format: "%.2f%%", calculator.burnPercentage))")
                .padding()
            
            Text("Fluid Resuscitation: \(String(format: "%.2f mL", calculator.fluidResuscitation))")
                .padding()
        }
        .navigationTitle("Burn Assessment Calculator")
    }
}

// MARK: - Preview

struct BurnCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        BurnCalculatorView()
    }
}