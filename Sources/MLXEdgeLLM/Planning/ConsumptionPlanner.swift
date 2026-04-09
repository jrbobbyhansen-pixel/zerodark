import Foundation
import SwiftUI

// MARK: - ConsumptionPlanner

class ConsumptionPlanner: ObservableObject {
    @Published var water: Consumable = Consumable(name: "Water", dailyConsumption: 2, unit: "liters")
    @Published var food: Consumable = Consumable(name: "Food", dailyConsumption: 1.5, unit: "kg")
    @Published var batteries: Consumable = Consumable(name: "Batteries", dailyConsumption: 0.5, unit: "units")
    @Published var fuel: Consumable = Consumable(name: "Fuel", dailyConsumption: 10, unit: "liters")
    @Published var ammo: Consumable = Consumable(name: "Ammo", dailyConsumption: 50, unit: "bullets")
    
    @Published var missionDuration: TimeInterval = 0
    @Published var resupplyInterval: TimeInterval = 0
    
    @Published var actualWaterConsumption: Double = 0
    @Published var actualFoodConsumption: Double = 0
    @Published var actualBatteriesConsumption: Double = 0
    @Published var actualFuelConsumption: Double = 0
    @Published var actualAmmoConsumption: Double = 0
    
    func calculateResupplyRequirements() -> [String: Double] {
        var resupply: [String: Double] = [:]
        
        resupply["Water"] = calculateResupply(for: water)
        resupply["Food"] = calculateResupply(for: food)
        resupply["Batteries"] = calculateResupply(for: batteries)
        resupply["Fuel"] = calculateResupply(for: fuel)
        resupply["Ammo"] = calculateResupply(for: ammo)
        
        return resupply
    }
    
    func unitFor(key: String) -> String {
        switch key {
        case "Water": return water.unit
        case "Food": return food.unit
        case "Batteries": return batteries.unit
        case "Fuel": return fuel.unit
        case "Ammo": return ammo.unit
        default: return ""
        }
    }

    private func calculateResupply(for consumable: Consumable) -> Double {
        let totalConsumption = consumable.dailyConsumption * (missionDuration / 86400) // Convert seconds to days
        let resupplyNeeded = totalConsumption - consumable.dailyConsumption * (resupplyInterval / 86400)
        return max(0, resupplyNeeded)
    }
}

// MARK: - Consumable

struct Consumable: Identifiable {
    let id = UUID()
    let name: String
    let dailyConsumption: Double
    let unit: String
}

// MARK: - ConsumableTracker

class ConsumableTracker: ObservableObject {
    @Published var water: Double = 0
    @Published var food: Double = 0
    @Published var batteries: Double = 0
    @Published var fuel: Double = 0
    @Published var ammo: Double = 0
    
    func trackConsumption(water: Double, food: Double, batteries: Double, fuel: Double, ammo: Double) {
        self.water += water
        self.food += food
        self.batteries += batteries
        self.fuel += fuel
        self.ammo += ammo
    }
}

// MARK: - ConsumptionPlannerView

struct ConsumptionPlannerView: View {
    @StateObject private var planner = ConsumptionPlanner()
    @StateObject private var tracker = ConsumableTracker()

    var body: some View {
        Form {
            Section("Mission Parameters") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Duration: \(Int(planner.missionDuration / 3600))h \(Int(planner.missionDuration.truncatingRemainder(dividingBy: 3600) / 60))m")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: $planner.missionDuration, in: 0...86400 * 7)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resupply every: \(Int(planner.resupplyInterval / 3600))h")
                        .font(.caption).foregroundColor(.secondary)
                    Slider(value: $planner.resupplyInterval, in: 0...86400)
                }
            }

            Section("Resupply Requirements") {
                ForEach(planner.calculateResupplyRequirements().sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(String(format: "%.2f %@", value, planner.unitFor(key: key)))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Track Actual Usage") {
                HStack { Text("Water"); Spacer(); TextField("0.0", value: $tracker.water, formatter: NumberFormatter()).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Food"); Spacer(); TextField("0.0", value: $tracker.food, formatter: NumberFormatter()).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Batteries"); Spacer(); TextField("0.0", value: $tracker.batteries, formatter: NumberFormatter()).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Fuel"); Spacer(); TextField("0.0", value: $tracker.fuel, formatter: NumberFormatter()).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Ammo"); Spacer(); TextField("0.0", value: $tracker.ammo, formatter: NumberFormatter()).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }

                Button("Log Consumption") {
                    planner.actualWaterConsumption = tracker.water
                    planner.actualFoodConsumption = tracker.food
                    planner.actualBatteriesConsumption = tracker.batteries
                    planner.actualFuelConsumption = tracker.fuel
                    planner.actualAmmoConsumption = tracker.ammo
                }
            }
        }
        .navigationTitle("Consumption Planner")
    }
}

#Preview {
    NavigationStack { ConsumptionPlannerView() }
}