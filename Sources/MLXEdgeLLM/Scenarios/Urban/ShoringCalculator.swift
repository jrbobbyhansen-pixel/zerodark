import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ShoringCalculator

class ShoringCalculator: ObservableObject {
    @Published var loadEstimate: Double = 0.0
    @Published var materialRequirements: String = ""
    @Published var safetyFactor: Double = 1.0
    @Published var errorMessage: String? = nil
    
    func calculateShoringRequirements() {
        guard loadEstimate > 0 else {
            errorMessage = "Load estimate must be greater than zero."
            return
        }
        
        // Placeholder calculation logic
        let requiredMaterial = loadEstimate * safetyFactor
        materialRequirements = "Required material: \(requiredMaterial) units"
        errorMessage = nil
    }
}

// MARK: - ShoringCalculatorView

struct ShoringCalculatorView: View {
    @StateObject private var calculator = ShoringCalculator()
    
    var body: some View {
        VStack {
            Text("Shoring Calculator")
                .font(.largeTitle)
                .padding()
            
            TextField("Load Estimate (units)", value: $calculator.loadEstimate, formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            TextField("Safety Factor", value: $calculator.safetyFactor, formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button(action: {
                calculator.calculateShoringRequirements()
            }) {
                Text("Calculate")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            
            if let errorMessage = calculator.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
            
            Text(calculator.materialRequirements)
                .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct ShoringCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        ShoringCalculatorView()
    }
}