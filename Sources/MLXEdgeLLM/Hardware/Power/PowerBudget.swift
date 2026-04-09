import Foundation
import SwiftUI

// MARK: - PowerBudget

class PowerBudget: ObservableObject {
    @Published var deviceConsumption: Double = 0.0
    @Published var missionDuration: TimeInterval = 0.0
    @Published var batteryCapacity: Double = 0.0
    @Published var powerConstraints: [String] = []

    func calculatePowerBudget() {
        let totalPowerConsumption = deviceConsumption * missionDuration
        let remainingBattery = batteryCapacity - totalPowerConsumption

        if remainingBattery < 0 {
            powerConstraints.append("Insufficient battery for mission duration.")
        } else {
            powerConstraints.append("Battery sufficient for mission duration.")
        }
    }
}

// MARK: - PowerBudgetView

struct PowerBudgetView: View {
    @StateObject private var powerBudget = PowerBudget()

    var body: some View {
        VStack {
            Text("Power Budget Calculator")
                .font(.largeTitle)
                .padding()

            Group {
                TextField("Device Consumption (Watts)", value: $powerBudget.deviceConsumption, format: .number)
                    .keyboardType(.decimalPad)
                    .padding()

                TextField("Mission Duration (Hours)", value: $powerBudget.missionDuration, format: .number)
                    .keyboardType(.decimalPad)
                    .padding()

                TextField("Battery Capacity (Wh)", value: $powerBudget.batteryCapacity, format: .number)
                    .keyboardType(.decimalPad)
                    .padding()
            }
            .textFieldStyle(RoundedBorderTextFieldStyle())

            Button(action: {
                powerBudget.calculatePowerBudget()
            }) {
                Text("Calculate")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()

            List(powerBudget.powerConstraints, id: \.self) { constraint in
                Text(constraint)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct PowerBudgetView_Previews: PreviewProvider {
    static var previews: some View {
        PowerBudgetView()
    }
}