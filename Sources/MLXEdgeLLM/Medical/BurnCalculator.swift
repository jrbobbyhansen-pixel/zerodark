// BurnCalculator.swift — Burn area assessment + Parkland fluid resuscitation
// Lund-Browder age-adjusted TBSA + Rule of Nines

import Foundation
import SwiftUI

// MARK: - BurnCalculator

@MainActor
final class BurnCalculator: ObservableObject {
    @Published var burnPercentage: Double = 0.0
    @Published var fluidTotal: Double = 0.0        // Total 24hr fluid (mL)
    @Published var fluidRateFirst8: Double = 0.0   // mL/hr for first 8 hours
    @Published var fluidRateNext16: Double = 0.0   // mL/hr for next 16 hours
    @Published var patientWeight: Double = 70.0
    @Published var errorMessage: String?

    // MARK: - Rule of Nines (Adult)

    func calculateRuleOfNines(burnArea: Double, weight: Double) {
        guard burnArea > 0, burnArea <= 100 else {
            errorMessage = "Burn area must be 1–100%"
            return
        }
        guard weight >= 1 else {
            errorMessage = "Weight must be at least 1 kg"
            return
        }
        errorMessage = nil
        patientWeight = weight
        burnPercentage = burnArea
        calculateParkland(tbsa: burnArea, weight: weight)
    }

    // MARK: - Lund-Browder (Age-Adjusted)

    /// Lund-Browder chart provides more accurate TBSA for pediatrics.
    /// Factors adjust head and leg percentages based on age.
    func calculateLundBrowder(burnArea: Double, age: Int, weight: Double) {
        guard burnArea > 0, burnArea <= 100, weight >= 1 else {
            errorMessage = "Invalid input — burn area 1-100%, weight > 0"
            return
        }
        guard age >= 0 else {
            errorMessage = "Age must be 0 or greater"
            return
        }
        errorMessage = nil
        patientWeight = weight

        // Lund-Browder age correction factor for head/legs
        // Infants have proportionally larger heads; adults have proportionally larger legs
        let correctionFactor: Double
        switch age {
        case 0..<1:   correctionFactor = 1.19  // Infant: head 19% vs adult 7%
        case 1..<5:   correctionFactor = 1.13
        case 5..<10:  correctionFactor = 1.07
        case 10..<15: correctionFactor = 1.03
        default:      correctionFactor = 1.00  // Adult standard
        }

        burnPercentage = min(burnArea * correctionFactor, 100.0)
        calculateParkland(tbsa: burnPercentage, weight: weight)
    }

    // MARK: - Parkland Formula

    /// Parkland: 4 mL × kg × %TBSA = total 24hr crystalloid
    /// Half in first 8 hours from time of burn, half in next 16 hours
    private func calculateParkland(tbsa: Double, weight: Double) {
        fluidTotal = 4.0 * weight * tbsa
        fluidRateFirst8 = (fluidTotal / 2.0) / 8.0    // mL/hr first 8 hours
        fluidRateNext16 = (fluidTotal / 2.0) / 16.0   // mL/hr next 16 hours
    }

    func reset() {
        burnPercentage = 0
        fluidTotal = 0
        fluidRateFirst8 = 0
        fluidRateNext16 = 0
        errorMessage = nil
    }
}

// MARK: - BurnCalculatorView

struct BurnCalculatorView: View {
    @StateObject private var calc = BurnCalculator()
    @State private var burnArea: String = ""
    @State private var weight: String = "70"
    @State private var age: String = "30"
    @State private var useRuleOfNines = true

    var body: some View {
        Form { _ in
            Section("Method") {
                Picker("Assessment", selection: $useRuleOfNines) {
                    Text("Rule of Nines (Adult)").tag(true)
                    Text("Lund-Browder (Age-Adjusted)").tag(false)
                }
                .pickerStyle(.segmented)
            }

            Section("Patient Data") {
                HStack {
                    Text("Burn Area (% TBSA)")
                    Spacer()
                    TextField("0", text: $burnArea)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                HStack {
                    Text("Weight (kg)")
                    Spacer()
                    TextField("70", text: $weight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                if !useRuleOfNines {
                    HStack {
                        Text("Age (years)")
                        Spacer()
                        TextField("30", text: $age)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }

            if let error = calc.errorMessage {
                Section {
                    Text(error).foregroundColor(ZDDesign.signalRed).font(.caption)
                }
            }

            Section {
                Button {
                    let ba = Double(burnArea) ?? 0
                    let w = Double(weight) ?? 70
                    if useRuleOfNines {
                        calc.calculateRuleOfNines(burnArea: ba, weight: w)
                    } else {
                        calc.calculateLundBrowder(burnArea: ba, age: Int(age) ?? 30, weight: w)
                    }
                } label: {
                    Label("Calculate", systemImage: "flame.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZDDesign.signalRed)
            }

            if calc.fluidTotal > 0 {
                Section("Results") {
                    LabeledContent("Adjusted TBSA", value: String(format: "%.1f%%", calc.burnPercentage))
                    LabeledContent("Total 24hr Fluid", value: String(format: "%.0f mL", calc.fluidTotal))
                        .font(.headline)
                }

                Section("Parkland Fluid Schedule") {
                    HStack {
                        Image(systemName: "clock.fill").foregroundColor(ZDDesign.signalRed)
                        VStack(alignment: .leading) {
                            Text("First 8 Hours").font(.headline)
                            Text("\(String(format: "%.0f", calc.fluidTotal / 2)) mL total")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(String(format: "%.0f", calc.fluidRateFirst8)) mL/hr")
                            .font(.title3.bold()).foregroundColor(ZDDesign.signalRed)
                    }
                    HStack {
                        Image(systemName: "clock").foregroundColor(ZDDesign.safetyYellow)
                        VStack(alignment: .leading) {
                            Text("Next 16 Hours").font(.headline)
                            Text("\(String(format: "%.0f", calc.fluidTotal / 2)) mL total")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(String(format: "%.0f", calc.fluidRateNext16)) mL/hr")
                            .font(.title3.bold()).foregroundColor(ZDDesign.safetyYellow)
                    }
                }
            }
        }
        .navigationTitle("Burn Calculator")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack { BurnCalculatorView() }
}
