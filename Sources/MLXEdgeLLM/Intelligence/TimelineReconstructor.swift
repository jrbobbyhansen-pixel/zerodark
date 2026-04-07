import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TimelineReconstructor

class TimelineReconstructor: ObservableObject {
    @Published var events: [Event] = []
    @Published var gaps: [Gap] = []
    @Published var conflicts: [Conflict] = []

    func reconstructTimeline(from logs: [Log]) {
        var eventMap: [Date: Event] = [:]

        // Process each log to populate eventMap
        for log in logs {
            for observation in log.observations {
                if let event = eventMap[observation.timestamp] {
                    event.merge(observation)
                } else {
                    eventMap[observation.timestamp] = Event(observation: observation)
                }
            }
        }

        // Convert eventMap to sorted events array
        events = eventMap.values.sorted { $0.timestamp < $1.timestamp }

        // Identify gaps and conflicts
        identifyGaps()
        identifyConflicts()
    }

    private func identifyGaps() {
        gaps = []
        for i in 0..<events.count - 1 {
            let currentEvent = events[i]
            let nextEvent = events[i + 1]
            if currentEvent.timestamp.distance(to: nextEvent.timestamp) > 10.minutes {
                gaps.append(Gap(start: currentEvent.timestamp, end: nextEvent.timestamp))
            }
        }
    }

    private func identifyConflicts() {
        conflicts = []
        for i in 0..<events.count - 1 {
            let currentEvent = events[i]
            let nextEvent = events[i + 1]
            if currentEvent.location.distance(to: nextEvent.location) < 100 && currentEvent.timestamp.distance(to: nextEvent.timestamp) < 5.minutes {
                conflicts.append(Conflict(event1: currentEvent, event2: nextEvent))
            }
        }
    }
}

// MARK: - Event

struct Event: Identifiable, Comparable {
    let id = UUID()
    let timestamp: Date
    let location: CLLocationCoordinate2D
    var details: String

    init(observation: Observation) {
        self.timestamp = observation.timestamp
        self.location = observation.location
        self.details = observation.details
    }

    mutating func merge(_ observation: Observation) {
        if observation.timestamp == timestamp {
            details += ", \(observation.details)"
        }
    }

    static func < (lhs: Event, rhs: Event) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}

// MARK: - Observation

struct Observation {
    let timestamp: Date
    let location: CLLocationCoordinate2D
    let details: String
}

// MARK: - Gap

struct Gap {
    let start: Date
    let end: Date
}

// MARK: - Conflict

struct Conflict {
    let event1: Event
    let event2: Event
}

// MARK: - Log

struct Log {
    let observations: [Observation]
}