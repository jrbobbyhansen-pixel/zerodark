import Foundation
import SwiftUI
import CoreLocation

// MARK: - Resource Types

enum ResourceType: String, CaseIterable {
    case water
    case food
    case batteries
    case medicalSupplies
    case ammo
}

// MARK: - Resource

struct Resource {
    let type: ResourceType
    var quantity: Int
    let maxCapacity: Int
}

// MARK: - ResourceTracker

class ResourceTracker: ObservableObject {
    @Published private(set) var resources: [Resource]
    @Published private(set) var lowLevelAlerts: [ResourceType] = []
    
    private let lowLevelThreshold: Int = 10
    
    init(initialResources: [Resource]) {
        self.resources = initialResources
    }
    
    func consumeResource(of type: ResourceType, amount: Int) {
        if let index = resources.firstIndex(where: { $0.type == type }) {
            let currentResource = resources[index]
            let newQuantity = max(0, currentResource.quantity - amount)
            resources[index] = Resource(type: type, quantity: newQuantity, maxCapacity: currentResource.maxCapacity)
            checkLowLevels()
        }
    }
    
    func resupplyResource(of type: ResourceType, amount: Int) {
        if let index = resources.firstIndex(where: { $0.type == type }) {
            let currentResource = resources[index]
            let newQuantity = min(currentResource.maxCapacity, currentResource.quantity + amount)
            resources[index] = Resource(type: type, quantity: newQuantity, maxCapacity: currentResource.maxCapacity)
            checkLowLevels()
        }
    }
    
    private func checkLowLevels() {
        lowLevelAlerts = resources.filter { $0.quantity <= lowLevelThreshold }.map { $0.type }
    }
}

// MARK: - ResourceTrackerView

struct ResourceTrackerView: View {
    @StateObject private var resourceTracker = ResourceTracker(initialResources: [
        Resource(type: .water, quantity: 50, maxCapacity: 100),
        Resource(type: .food, quantity: 30, maxCapacity: 50),
        Resource(type: .batteries, quantity: 20, maxCapacity: 30),
        Resource(type: .medicalSupplies, quantity: 15, maxCapacity: 20),
        Resource(type: .ammo, quantity: 100, maxCapacity: 200)
    ])
    
    var body: some View {
        VStack {
            List(resourceTracker.resources) { resource in
                ResourceRow(resource: resource)
            }
            .listStyle(PlainListStyle())
            
            if !resourceTracker.lowLevelAlerts.isEmpty {
                VStack {
                    Text("Low Levels Alert:")
                        .font(.headline)
                    ForEach(resourceTracker.lowLevelAlerts, id: \.self) { type in
                        Text(type.rawValue.capitalized)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.2))
                .cornerRadius(10)
            }
        }
        .navigationTitle("Resource Tracker")
    }
}

// MARK: - ResourceRow

struct ResourceRow: View {
    let resource: Resource
    
    var body: some View {
        HStack {
            Text(resource.type.rawValue.capitalized)
                .font(.body)
            Spacer()
            Text("\(resource.quantity)/\(resource.maxCapacity)")
                .font(.caption)
        }
    }
}

// MARK: - Preview

struct ResourceTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        ResourceTrackerView()
    }
}