import Foundation
import HomeKit

// MARK: - Smart Home Control

/// Control HomeKit devices with natural language
@MainActor
public final class SmartHomeControl: NSObject, ObservableObject {
    
    public static let shared = SmartHomeControl()
    
    // MARK: - State
    
    @Published public var isAvailable: Bool = false
    @Published public var homes: [HMHome] = []
    @Published public var currentHome: HMHome?
    @Published public var rooms: [HMRoom] = []
    @Published public var accessories: [HMAccessory] = []
    
    private let homeManager = HMHomeManager()
    
    // MARK: - Init
    
    private override init() {
        super.init()
        homeManager.delegate = self
    }
    
    // MARK: - Query Devices
    
    public func getDevicesSummary() -> String {
        guard let home = currentHome else {
            return "No home configured in HomeKit"
        }
        
        var lines: [String] = []
        lines.append("Home: \(home.name)")
        lines.append("Rooms: \(home.rooms.count)")
        lines.append("")
        
        for room in home.rooms {
            lines.append("📍 \(room.name):")
            for accessory in room.accessories {
                let status = getAccessoryStatus(accessory)
                lines.append("  - \(accessory.name): \(status)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func getAccessoryStatus(_ accessory: HMAccessory) -> String {
        var statuses: [String] = []
        
        for service in accessory.services {
            for characteristic in service.characteristics {
                if characteristic.characteristicType == HMCharacteristicTypePowerState {
                    if let value = characteristic.value as? Bool {
                        statuses.append(value ? "On" : "Off")
                    }
                } else if characteristic.characteristicType == HMCharacteristicTypeBrightness {
                    if let value = characteristic.value as? Int {
                        statuses.append("\(value)% brightness")
                    }
                } else if characteristic.characteristicType == HMCharacteristicTypeCurrentTemperature {
                    if let value = characteristic.value as? Double {
                        statuses.append(String(format: "%.1f°", value))
                    }
                } else if characteristic.characteristicType == HMCharacteristicTypeTargetTemperature {
                    if let value = characteristic.value as? Double {
                        statuses.append(String(format: "Target: %.1f°", value))
                    }
                }
            }
        }
        
        return statuses.isEmpty ? "Unknown" : statuses.joined(separator: ", ")
    }
    
    // MARK: - Control Devices
    
    public func turnOn(_ deviceName: String) async throws {
        try await setDevicePower(deviceName, on: true)
    }
    
    public func turnOff(_ deviceName: String) async throws {
        try await setDevicePower(deviceName, on: false)
    }
    
    public func setBrightness(_ deviceName: String, to level: Int) async throws {
        let accessory = try findAccessory(named: deviceName)
        
        for service in accessory.services {
            for characteristic in service.characteristics where 
                characteristic.characteristicType == HMCharacteristicTypeBrightness {
                try await characteristic.writeValue(level)
                return
            }
        }
        
        throw SmartHomeError.characteristicNotFound("brightness")
    }
    
    public func setTemperature(_ deviceName: String, to temp: Double) async throws {
        let accessory = try findAccessory(named: deviceName)
        
        for service in accessory.services {
            for characteristic in service.characteristics where 
                characteristic.characteristicType == HMCharacteristicTypeTargetTemperature {
                try await characteristic.writeValue(temp)
                return
            }
        }
        
        throw SmartHomeError.characteristicNotFound("temperature")
    }
    
    public func setColor(_ deviceName: String, hue: Float, saturation: Float) async throws {
        let accessory = try findAccessory(named: deviceName)
        
        for service in accessory.services {
            for characteristic in service.characteristics {
                if characteristic.characteristicType == HMCharacteristicTypeHue {
                    try await characteristic.writeValue(hue)
                } else if characteristic.characteristicType == HMCharacteristicTypeSaturation {
                    try await characteristic.writeValue(saturation)
                }
            }
        }
    }
    
    // MARK: - Scenes
    
    public func listScenes() -> [String] {
        currentHome?.actionSets.map { $0.name } ?? []
    }
    
    public func runScene(_ sceneName: String) async throws {
        guard let home = currentHome else {
            throw SmartHomeError.noHome
        }
        
        guard let scene = home.actionSets.first(where: { 
            $0.name.lowercased() == sceneName.lowercased() 
        }) else {
            throw SmartHomeError.sceneNotFound(sceneName)
        }
        
        try await home.executeActionSet(scene)
    }
    
    // MARK: - Room Control
    
    public func turnOnRoom(_ roomName: String) async throws {
        let room = try findRoom(named: roomName)
        
        for accessory in room.accessories {
            try? await setAccessoryPower(accessory, on: true)
        }
    }
    
    public func turnOffRoom(_ roomName: String) async throws {
        let room = try findRoom(named: roomName)
        
        for accessory in room.accessories {
            try? await setAccessoryPower(accessory, on: false)
        }
    }
    
    // MARK: - Helpers
    
    private func setDevicePower(_ deviceName: String, on: Bool) async throws {
        let accessory = try findAccessory(named: deviceName)
        try await setAccessoryPower(accessory, on: on)
    }
    
    private func setAccessoryPower(_ accessory: HMAccessory, on: Bool) async throws {
        for service in accessory.services {
            for characteristic in service.characteristics where 
                characteristic.characteristicType == HMCharacteristicTypePowerState {
                try await characteristic.writeValue(on)
                return
            }
        }
        
        throw SmartHomeError.characteristicNotFound("power")
    }
    
    private func findAccessory(named name: String) throws -> HMAccessory {
        guard let home = currentHome else {
            throw SmartHomeError.noHome
        }
        
        let lowercased = name.lowercased()
        
        for room in home.rooms {
            for accessory in room.accessories {
                if accessory.name.lowercased().contains(lowercased) {
                    return accessory
                }
            }
        }
        
        throw SmartHomeError.deviceNotFound(name)
    }
    
    private func findRoom(named name: String) throws -> HMRoom {
        guard let home = currentHome else {
            throw SmartHomeError.noHome
        }
        
        let lowercased = name.lowercased()
        
        guard let room = home.rooms.first(where: { 
            $0.name.lowercased().contains(lowercased) 
        }) else {
            throw SmartHomeError.roomNotFound(name)
        }
        
        return room
    }
    
    // MARK: - Natural Language Parsing
    
    public struct SmartHomeCommand {
        public let action: Action
        public let target: String
        public let value: Any?
        
        public enum Action {
            case turnOn
            case turnOff
            case setBrightness(Int)
            case setTemperature(Double)
            case setColor(hue: Float, saturation: Float)
            case runScene
        }
    }
    
    public func parseCommand(_ input: String) -> SmartHomeCommand? {
        let lower = input.lowercased()
        
        // Turn on/off patterns
        if lower.contains("turn on") || lower.contains("switch on") {
            let target = extractTarget(from: lower, after: ["turn on", "switch on"])
            return SmartHomeCommand(action: .turnOn, target: target, value: nil)
        }
        
        if lower.contains("turn off") || lower.contains("switch off") {
            let target = extractTarget(from: lower, after: ["turn off", "switch off"])
            return SmartHomeCommand(action: .turnOff, target: target, value: nil)
        }
        
        // Brightness patterns
        if lower.contains("brightness") || lower.contains("dim") || lower.contains("brighten") {
            if let match = lower.range(of: #"\d+%?"#, options: .regularExpression) {
                let numStr = String(lower[match]).replacingOccurrences(of: "%", with: "")
                if let level = Int(numStr) {
                    let target = extractTarget(from: lower, before: ["to", "brightness"])
                    return SmartHomeCommand(action: .setBrightness(level), target: target, value: level)
                }
            }
        }
        
        // Temperature patterns
        if lower.contains("temperature") || lower.contains("thermostat") || lower.contains("degrees") {
            if let match = lower.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                if let temp = Double(String(lower[match])) {
                    let target = extractTarget(from: lower, before: ["to", "temperature"])
                    return SmartHomeCommand(action: .setTemperature(temp), target: target, value: temp)
                }
            }
        }
        
        // Scene patterns
        if lower.contains("scene") || lower.contains("activate") || lower.contains("run") {
            let target = extractTarget(from: lower, after: ["scene", "activate", "run"])
            return SmartHomeCommand(action: .runScene, target: target, value: nil)
        }
        
        return nil
    }
    
    private func extractTarget(from input: String, after keywords: [String]) -> String {
        for keyword in keywords {
            if let range = input.range(of: keyword) {
                let afterKeyword = input[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let words = afterKeyword.split(separator: " ")
                if let first = words.first {
                    return String(first)
                }
            }
        }
        return ""
    }
    
    private func extractTarget(from input: String, before keywords: [String]) -> String {
        for keyword in keywords {
            if let range = input.range(of: keyword) {
                let beforeKeyword = input[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let words = beforeKeyword.split(separator: " ")
                if let last = words.last {
                    return String(last)
                }
            }
        }
        return ""
    }
    
    // MARK: - Execute Natural Language
    
    public func executeNaturalLanguage(_ input: String) async throws -> String {
        guard let command = parseCommand(input) else {
            return "I couldn't understand that command. Try 'turn on living room lights' or 'set bedroom brightness to 50%'"
        }
        
        switch command.action {
        case .turnOn:
            try await turnOn(command.target)
            return "Turned on \(command.target)"
            
        case .turnOff:
            try await turnOff(command.target)
            return "Turned off \(command.target)"
            
        case .setBrightness(let level):
            try await setBrightness(command.target, to: level)
            return "Set \(command.target) brightness to \(level)%"
            
        case .setTemperature(let temp):
            try await setTemperature(command.target, to: temp)
            return "Set \(command.target) temperature to \(temp)°"
            
        case .setColor(let hue, let saturation):
            try await setColor(command.target, hue: hue, saturation: saturation)
            return "Changed \(command.target) color"
            
        case .runScene:
            try await runScene(command.target)
            return "Running scene: \(command.target)"
        }
    }
    
    // MARK: - Errors
    
    public enum SmartHomeError: Error, LocalizedError {
        case noHome
        case deviceNotFound(String)
        case roomNotFound(String)
        case sceneNotFound(String)
        case characteristicNotFound(String)
        
        public var errorDescription: String? {
            switch self {
            case .noHome: return "No home configured in HomeKit"
            case .deviceNotFound(let name): return "Device not found: \(name)"
            case .roomNotFound(let name): return "Room not found: \(name)"
            case .sceneNotFound(let name): return "Scene not found: \(name)"
            case .characteristicNotFound(let name): return "Characteristic not found: \(name)"
            }
        }
    }
}

// MARK: - HMHomeManagerDelegate

extension SmartHomeControl: HMHomeManagerDelegate {
    
    public func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            homes = manager.homes
            currentHome = manager.primaryHome ?? manager.homes.first
            isAvailable = !homes.isEmpty
            
            if let home = currentHome {
                rooms = home.rooms
                accessories = home.accessories
            }
        }
    }
}
