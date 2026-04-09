import Foundation
import SwiftUI

// MARK: - Entity Types

enum EntityType {
    case person
    case place
    case equipment
    case time
}

// MARK: - Entity

struct Entity {
    let id: UUID
    let type: EntityType
    let name: String
    let referenceCount: Int
}

// MARK: - EntityTracker

class EntityTracker: ObservableObject {
    @Published private(set) var entities: [Entity] = []
    
    func addEntity(_ name: String, type: EntityType) {
        if let existingEntity = entities.first(where: { $0.name == name && $0.type == type }) {
            updateEntity(existingEntity, incrementReferenceCount: true)
        } else {
            let newEntity = Entity(id: UUID(), type: type, name: name, referenceCount: 1)
            entities.append(newEntity)
        }
    }
    
    func removeEntity(_ name: String, type: EntityType) {
        if let existingEntity = entities.first(where: { $0.name == name && $0.type == type }) {
            updateEntity(existingEntity, incrementReferenceCount: false)
        }
    }
    
    private func updateEntity(_ entity: Entity, incrementReferenceCount: Bool) {
        if incrementReferenceCount {
            if entity.referenceCount > 0 {
                if let index = entities.firstIndex(of: entity) {
                    entities[index] = Entity(id: entity.id, type: entity.type, name: entity.name, referenceCount: entity.referenceCount + 1)
                }
            }
        } else {
            if entity.referenceCount > 1 {
                if let index = entities.firstIndex(of: entity) {
                    entities[index] = Entity(id: entity.id, type: entity.type, name: entity.name, referenceCount: entity.referenceCount - 1)
                }
            } else {
                if let index = entities.firstIndex(of: entity) {
                    entities.remove(at: index)
                }
            }
        }
    }
}

// MARK: - EntityTrackerViewModel

class EntityTrackerViewModel: ObservableObject {
    @Published var entities: [Entity] = []
    
    private let entityTracker: EntityTracker
    
    init(entityTracker: EntityTracker) {
        self.entityTracker = entityTracker
        self.entityTracker.$entities.assign(to: &$entities)
    }
    
    func addPerson(name: String) {
        entityTracker.addEntity(name, type: .person)
    }
    
    func removePerson(name: String) {
        entityTracker.removeEntity(name, type: .person)
    }
    
    func addPlace(name: String) {
        entityTracker.addEntity(name, type: .place)
    }
    
    func removePlace(name: String) {
        entityTracker.removeEntity(name, type: .place)
    }
    
    func addEquipment(name: String) {
        entityTracker.addEntity(name, type: .equipment)
    }
    
    func removeEquipment(name: String) {
        entityTracker.removeEntity(name, type: .equipment)
    }
    
    func addTime(name: String) {
        entityTracker.addEntity(name, type: .time)
    }
    
    func removeTime(name: String) {
        entityTracker.removeEntity(name, type: .time)
    }
}

// MARK: - EntityTrackerView

struct EntityTrackerView: View {
    @StateObject private var viewModel = EntityTrackerViewModel(entityTracker: EntityTracker())
    
    var body: some View {
        VStack {
            List(viewModel.entities) { entity in
                Text("\(entity.name) (\(entity.type.rawValue)) - References: \(entity.referenceCount)")
            }
            .navigationTitle("Entity Tracker")
            
            HStack {
                Button("Add Person") {
                    viewModel.addPerson(name: "John Doe")
                }
                Button("Remove Person") {
                    viewModel.removePerson(name: "John Doe")
                }
            }
            
            HStack {
                Button("Add Place") {
                    viewModel.addPlace(name: "Central Park")
                }
                Button("Remove Place") {
                    viewModel.removePlace(name: "Central Park")
                }
            }
            
            HStack {
                Button("Add Equipment") {
                    viewModel.addEquipment(name: "Rifle")
                }
                Button("Remove Equipment") {
                    viewModel.removeEquipment(name: "Rifle")
                }
            }
            
            HStack {
                Button("Add Time") {
                    viewModel.addTime(name: "10:00 AM")
                }
                Button("Remove Time") {
                    viewModel.removeTime(name: "10:00 AM")
                }
            }
        }
    }
}

// MARK: - Preview

struct EntityTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        EntityTrackerView()
    }
}