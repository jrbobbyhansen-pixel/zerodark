import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - WorkingMemory

class WorkingMemory: ObservableObject {
    @Published var activeEntities: [Entity] = []
    @Published var goals: [Goal] = []
    @Published var constraints: [Constraint] = []
    @Published var context: Context = Context()

    func clear() {
        activeEntities = []
        goals = []
        constraints = []
        context = Context()
    }
}

// MARK: - Entity

struct Entity: Identifiable {
    let id: UUID
    let name: String
    let location: CLLocationCoordinate2D?
    let arAnchor: ARAnchor?

    init(id: UUID = UUID(), name: String, location: CLLocationCoordinate2D? = nil, arAnchor: ARAnchor? = nil) {
        self.id = id
        self.name = name
        self.location = location
        self.arAnchor = arAnchor
    }
}

// MARK: - Goal

struct Goal: Identifiable {
    let id: UUID
    let description: String
    let priority: Int

    init(id: UUID = UUID(), description: String, priority: Int) {
        self.id = id
        self.description = description
        self.priority = priority
    }
}

// MARK: - Constraint

struct Constraint: Identifiable {
    let id: UUID
    let description: String
    let isActive: Bool

    init(id: UUID = UUID(), description: String, isActive: Bool) {
        self.id = id
        self.description = description
        self.isActive = isActive
    }
}

// MARK: - Context

struct Context {
    var time: Date = Date()
    var location: CLLocationCoordinate2D?
    var environment: Environment = Environment()
}

// MARK: - Environment

struct Environment {
    var lighting: Lighting
    var weather: Weather
    var temperature: Double
}

// MARK: - Lighting

enum Lighting {
    case bright
    case dim
    case dark
}

// MARK: - Weather

enum Weather {
    case sunny
    case rainy
    case cloudy
    case stormy
}