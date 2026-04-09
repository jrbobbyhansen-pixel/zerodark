import Foundation
import SwiftUI

// MARK: - Rope Rescue Calculation Models

struct RopeRescueCalculation {
    var mechanicalAdvantage: Double
    var edgeProtection: EdgeProtection
    var anchorLoad: Double
    var ropeStretch: Double
    var safetyFactor: Double
}

enum EdgeProtection {
    case none
    case carabiner
    case figureEight
    case munterMule
}

// MARK: - Rope Rescue Calculation Service

class RopeRescueCalculationService: ObservableObject {
    @Published var calculation: RopeRescueCalculation?

    func calculate(mechanicalAdvantage: Double, edgeProtection: EdgeProtection, anchorLoad: Double, ropeStretch: Double, safetyFactor: Double) {
        let calculation = RopeRescueCalculation(
            mechanicalAdvantage: mechanicalAdvantage,
            edgeProtection: edgeProtection,
            anchorLoad: anchorLoad,
            ropeStretch: ropeStretch,
            safetyFactor: safetyFactor
        )
        self.calculation = calculation
    }
}

// MARK: - Rope Rescue Calculation View Model

class RopeRescueCalculationViewModel: ObservableObject {
    @Published var mechanicalAdvantage: Double = 1.0
    @Published var edgeProtection: EdgeProtection = .none
    @Published var anchorLoad: Double = 0.0
    @Published var ropeStretch: Double = 0.0
    @Published var safetyFactor: Double = 1.0
    @Published var result: RopeRescueCalculation?

    private let calculationService: RopeRescueCalculationService

    init(calculationService: RopeRescueCalculationService) {
        self.calculationService = calculationService
    }

    func calculate() {
        calculationService.calculate(
            mechanicalAdvantage: mechanicalAdvantage,
            edgeProtection: edgeProtection,
            anchorLoad: anchorLoad,
            ropeStretch: ropeStretch,
            safetyFactor: safetyFactor
        )
        result = calculationService.calculation
    }
}

// MARK: - Rope Rescue Calculation View

struct RopeRescueCalculationView: View {
    @StateObject private var viewModel = RopeRescueCalculationViewModel(calculationService: RopeRescueCalculationService())

    var body: some View {
        VStack {
            Text("Rope Rescue Calculator")
                .font(.largeTitle)
                .padding()

            Form {
                Section(header: Text("Mechanical Advantage")) {
                    Slider(value: $viewModel.mechanicalAdvantage, in: 1...10, step: 1)
                    Text("Mechanical Advantage: \(viewModel.mechanicalAdvantage, specifier: "%.0f")")
                }

                Section(header: Text("Edge Protection")) {
                    Picker("Edge Protection", selection: $viewModel.edgeProtection) {
                        Text("None").tag(EdgeProtection.none)
                        Text("Carabiner").tag(EdgeProtection.carabiner)
                        Text("Figure Eight").tag(EdgeProtection.figureEight)
                        Text("Munter Mule").tag(EdgeProtection.munterMule)
                    }
                }

                Section(header: Text("Anchor Load")) {
                    Slider(value: $viewModel.anchorLoad, in: 0...1000, step: 10)
                    Text("Anchor Load: \(viewModel.anchorLoad, specifier: "%.0f") lbs")
                }

                Section(header: Text("Rope Stretch")) {
                    Slider(value: $viewModel.ropeStretch, in: 0...10, step: 0.1)
                    Text("Rope Stretch: \(viewModel.ropeStretch, specifier: "%.1f")%")
                }

                Section(header: Text("Safety Factor")) {
                    Slider(value: $viewModel.safetyFactor, in: 1...5, step: 0.1)
                    Text("Safety Factor: \(viewModel.safetyFactor, specifier: "%.1f")")
                }

                Button(action: viewModel.calculate) {
                    Text("Calculate")
                }
                .padding()
            }

            if let result = viewModel.result {
                ResultView(result: result)
            }
        }
        .navigationTitle("Rope Rescue Calculator")
    }
}

struct ResultView: View {
    let result: RopeRescueCalculation

    var body: some View {
        VStack {
            Text("Calculation Result")
                .font(.title2)
                .padding()

            Text("Mechanical Advantage: \(result.mechanicalAdvantage, specifier: "%.0f")")
            Text("Edge Protection: \(result.edgeProtection.description)")
            Text("Anchor Load: \(result.anchorLoad, specifier: "%.0f") lbs")
            Text("Rope Stretch: \(result.ropeStretch, specifier: "%.1f")%")
            Text("Safety Factor: \(result.safetyFactor, specifier: "%.1f")")
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - EdgeProtection Description

extension EdgeProtection: CustomStringConvertible {
    var description: String {
        switch self {
        case .none: return "None"
        case .carabiner: return "Carabiner"
        case .figureEight: return "Figure Eight"
        case .munterMule: return "Munter Mule"
        }
    }
}

// MARK: - Preview

struct RopeRescueCalculationView_Previews: PreviewProvider {
    static var previews: some View {
        RopeRescueCalculationView()
    }
}