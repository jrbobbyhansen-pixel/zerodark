import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ScenarioEngine

class ScenarioEngine: ObservableObject {
    @Published var isRunning = false
    @Published var speed: Double = 1.0
    @Published var currentTime: TimeInterval = 0.0
    @Published var logEntries: [String] = []

    private var scenario: Scenario?
    private var timer: Timer?
    private var startTime: Date?

    func loadScenario(_ scenario: Scenario) {
        self.scenario = scenario
        reset()
    }

    func start() {
        guard let scenario = scenario else { return }
        isRunning = true
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / scenario.frameRate, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard let scenario = scenario else { return }
        isRunning = true
        startTime = Date().addingTimeInterval(-currentTime)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / scenario.frameRate, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func reset() {
        isRunning = false
        currentTime = 0.0
        logEntries = []
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        guard let scenario = scenario else { return }
        currentTime = Date().timeIntervalSince(startTime ?? Date())
        let frame = scenario.frame(at: currentTime * speed)
        processFrame(frame)
    }

    private func processFrame(_ frame: ScenarioFrame) {
        for event in frame.events {
            handleEvent(event)
        }
    }

    private func handleEvent(_ event: ScenarioEvent) {
        switch event {
        case .inject(let inject):
            log("Injecting: \(inject)")
            // Handle inject
        case .trigger(let trigger):
            log("Triggering: \(trigger)")
            // Handle trigger
        }
    }

    private func log(_ message: String) {
        logEntries.append(message)
    }
}

// MARK: - Scenario

struct Scenario {
    let frameRate: Double
    let frames: [ScenarioFrame]

    func frame(at time: TimeInterval) -> ScenarioFrame {
        guard let frame = frames.first(where: { $0.startTime <= time && time < $0.endTime }) else {
            return ScenarioFrame(startTime: 0, endTime: 0, events: [])
        }
        return frame
    }
}

// MARK: - ScenarioFrame

struct ScenarioFrame {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let events: [ScenarioEvent]
}

// MARK: - ScenarioEvent

enum ScenarioEvent {
    case inject(ScenarioInject)
    case trigger(ScenarioTrigger)
}

// MARK: - ScenarioInject

struct ScenarioInject {
    let type: String
    let data: Any
}

// MARK: - ScenarioTrigger

struct ScenarioTrigger {
    let type: String
    let conditions: [String: Any]
}