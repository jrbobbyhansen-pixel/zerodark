import Foundation
import SwiftUI

// MARK: - ResourceTracker

class ResourceTracker: ObservableObject {
    @Published var personnel: [Personnel] = []
    @Published var equipment: [Equipment] = []
    @Published var supplies: [Supply] = []
    
    @Published var resupplyNeeded: Bool = false
    
    func updateConsumption() {
        // Update consumption rates and check for resupply needs
        for person in personnel {
            person.consumptionRate.update()
        }
        
        for equip in equipment {
            equip.consumptionRate.update()
        }
        
        for supply in supplies {
            supply.consumptionRate.update()
        }
        
        checkResupplyNeeds()
    }
    
    private func checkResupplyNeeds() {
        resupplyNeeded = personnel.any { $0.consumptionRate.needsResupply } ||
                          equipment.any { $0.consumptionRate.needsResupply } ||
                          supplies.any { $0.consumptionRate.needsResupply }
    }
}

// MARK: - Resource

protocol Resource {
    var name: String { get }
    var consumptionRate: ConsumptionRate { get }
}

// MARK: - Personnel

struct Personnel: Resource, Identifiable {
    let id = UUID()
    var name: String
    var consumptionRate: ConsumptionRate
    
    init(name: String, consumptionRate: ConsumptionRate) {
        self.name = name
        self.consumptionRate = consumptionRate
    }
}

// MARK: - Equipment

struct Equipment: Resource, Identifiable {
    let id = UUID()
    var name: String
    var consumptionRate: ConsumptionRate
    
    init(name: String, consumptionRate: ConsumptionRate) {
        self.name = name
        self.consumptionRate = consumptionRate
    }
}

// MARK: - Supply

struct Supply: Resource, Identifiable {
    let id = UUID()
    var name: String
    var consumptionRate: ConsumptionRate
    
    init(name: String, consumptionRate: ConsumptionRate) {
        self.name = name
        self.consumptionRate = consumptionRate
    }
}

// MARK: - ConsumptionRate

class ConsumptionRate: ObservableObject {
    @Published var currentAmount: Int
    let maxAmount: Int
    let consumptionPerHour: Int
    
    init(currentAmount: Int, maxAmount: Int, consumptionPerHour: Int) {
        self.currentAmount = currentAmount
        self.maxAmount = maxAmount
        self.consumptionPerHour = consumptionPerHour
    }
    
    func update() {
        currentAmount -= consumptionPerHour
        if currentAmount <= 0 {
            currentAmount = 0
        }
    }
    
    var needsResupply: Bool {
        currentAmount <= maxAmount / 4
    }
}

// MARK: - ResourceTrackerView

struct ResourceTrackerView: View {
    @StateObject private var resourceTracker = ResourceTracker()
    
    var body: some View {
        VStack {
            Text("Resource Tracker")
                .font(.largeTitle)
                .padding()
            
            List {
                Section(header: Text("Personnel")) {
                    ForEach(resourceTracker.personnel) { person in
                        ResourceRow(resource: person)
                    }
                }
                
                Section(header: Text("Equipment")) {
                    ForEach(resourceTracker.equipment) { equip in
                        ResourceRow(resource: equip)
                    }
                }
                
                Section(header: Text("Supplies")) {
                    ForEach(resourceTracker.supplies) { supply in
                        ResourceRow(resource: supply)
                    }
                }
            }
            
            Button(action: {
                resourceTracker.updateConsumption()
            }) {
                Text("Update Consumption")
            }
            .padding()
            
            if resourceTracker.resupplyNeeded {
                Text("Resupply Needed!")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear {
            // Initialize resources with sample data
            resourceTracker.personnel = [
                Personnel(name: "John Doe", consumptionRate: ConsumptionRate(currentAmount: 100, maxAmount: 100, consumptionPerHour: 5))
            ]
            
            resourceTracker.equipment = [
                Equipment(name: "Rifle", consumptionRate: ConsumptionRate(currentAmount: 100, maxAmount: 100, consumptionPerHour: 2))
            ]
            
            resourceTracker.supplies = [
                Supply(name: "Ammunition", consumptionRate: ConsumptionRate(currentAmount: 100, maxAmount: 100, consumptionPerHour: 3))
            ]
        }
    }
}

// MARK: - ResourceRow

struct ResourceRow<ResourceType: Resource>: View {
    let resource: ResourceType
    
    var body: some View {
        HStack {
            Text(resource.name)
            Spacer()
            Text("\(resource.consumptionRate.currentAmount)/\(resource.consumptionRate.maxAmount)")
        }
    }
}

// MARK: - Preview

struct ResourceTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        ResourceTrackerView()
    }
}