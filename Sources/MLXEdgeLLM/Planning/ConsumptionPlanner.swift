import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

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

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var planner = ConsumptionPlanner()
    @StateObject private var tracker = ConsumableTracker()
    
    var body: some View {
        VStack {
            Text("Mission Duration: \(planner.missionDuration, specifier: "%.0f") seconds")
            Slider(value: $planner.missionDuration, in: 0...86400 * 7) // 7 days
                .padding()
            
            Text("Resupply Interval: \(planner.resupplyInterval, specifier: "%.0f") seconds")
            Slider(value: $planner.resupplyInterval, in: 0...86400 * 1) // 1 day
                .padding()
            
            Text("Resupply Requirements:")
            ForEach(planner.calculateResupplyRequirements().sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                Text("\(key): \(value, specifier: "%.2f") \(planner.water.unit)")
            }
            
            Text("Track Actual Consumption:")
            HStack {
                Text("Water:")
                TextField("0.0", value: $tracker.water, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
            }
            HStack {
                Text("Food:")
                TextField("0.0", value: $tracker.food, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
            }
            HStack {
                Text("Batteries:")
                TextField("0.0", value: $tracker.batteries, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
            }
            HStack {
                Text("Fuel:")
                TextField("0.0", value: $tracker.fuel, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
            }
            HStack {
                Text("Ammo:")
                TextField("0.0", value: $tracker.ammo, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
            }
            
            Button("Track") {
                planner.actualWaterConsumption = tracker.water
                planner.actualFoodConsumption = tracker.food
                planner.actualBatteriesConsumption = tracker.batteries
                planner.actualFuelConsumption = tracker.fuel
                planner.actualAmmoConsumption = tracker.ammo
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}