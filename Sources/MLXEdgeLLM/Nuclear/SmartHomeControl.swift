import Foundation

// MARK: - Smart Home Control

/// Control HomeKit devices with natural language
/// Note: Requires HomeKit entitlement and iOS/macOS

#if canImport(HomeKit) && !os(watchOS)
import HomeKit

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
    
    // MARK: - Commands
    
    public struct HomeCommand {
        public let action: Action
        public let target: String
        public let value: Any?
        
        public enum Action: String {
            case turnOn = "turn on"
            case turnOff = "turn off"
            case setBrightness = "set brightness"
            case setTemperature = "set temperature"
            case lock = "lock"
            case unlock = "unlock"
            case setColor = "set color"
        }
    }
    
    /// Parse natural language into home command
    public func parseCommand(_ text: String) -> HomeCommand? {
        let lower = text.lowercased()
        
        if lower.contains("turn on") || lower.contains("switch on") {
            let target = extractTarget(from: lower)
            return HomeCommand(action: .turnOn, target: target, value: nil)
        }
        
        if lower.contains("turn off") || lower.contains("switch off") {
            let target = extractTarget(from: lower)
            return HomeCommand(action: .turnOff, target: target, value: nil)
        }
        
        if lower.contains("brightness") {
            let target = extractTarget(from: lower)
            let value = extractNumber(from: lower)
            return HomeCommand(action: .setBrightness, target: target, value: value)
        }
        
        return nil
    }
    
    private func extractTarget(from text: String) -> String {
        let commonTargets = ["lights", "light", "lamp", "fan", "thermostat", "lock", "door"]
        for target in commonTargets {
            if text.contains(target) {
                return target
            }
        }
        return "device"
    }
    
    private func extractNumber(from text: String) -> Int? {
        let pattern = "\\d+"
        if let match = text.range(of: pattern, options: .regularExpression) {
            return Int(text[match])
        }
        return nil
    }
    
    /// Execute home command
    public func execute(_ command: HomeCommand) async throws {
        guard let home = currentHome else {
            throw HomeError.noHomeSelected
        }
        
        let matchingAccessories = accessories.filter {
            $0.name.lowercased().contains(command.target)
        }
        
        guard let accessory = matchingAccessories.first else {
            throw HomeError.accessoryNotFound
        }
        
        for service in accessory.services {
            for characteristic in service.characteristics {
                switch command.action {
                case .turnOn:
                    if characteristic.characteristicType == HMCharacteristicTypePowerState {
                        try await characteristic.writeValue(true)
                    }
                case .turnOff:
                    if characteristic.characteristicType == HMCharacteristicTypePowerState {
                        try await characteristic.writeValue(false)
                    }
                case .setBrightness:
                    if characteristic.characteristicType == HMCharacteristicTypeBrightness,
                       let value = command.value as? Int {
                        try await characteristic.writeValue(value)
                    }
                default:
                    break
                }
            }
        }
    }
    
    public enum HomeError: Error {
        case noHomeSelected
        case accessoryNotFound
        case commandFailed
    }
}

extension SmartHomeControl: HMHomeManagerDelegate {
    public func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        homes = manager.homes
        currentHome = manager.primaryHome ?? homes.first
        
        if let home = currentHome {
            rooms = home.rooms
            accessories = home.accessories
        }
        
        isAvailable = !homes.isEmpty
    }
}

#else

// Stub for platforms without HomeKit
@MainActor
public final class SmartHomeControl: ObservableObject {
    public static let shared = SmartHomeControl()
    
    @Published public var isAvailable: Bool = false
    
    public struct HomeCommand {
        public let action: Action
        public let target: String
        public let value: Any?
        
        public enum Action: String {
            case turnOn = "turn on"
            case turnOff = "turn off"
            case setBrightness = "set brightness"
            case setTemperature = "set temperature"
            case lock = "lock"
            case unlock = "unlock"
            case setColor = "set color"
        }
    }
    
    public func parseCommand(_ text: String) -> HomeCommand? { nil }
    public func execute(_ command: HomeCommand) async throws {
        throw HomeError.notAvailable
    }
    
    public enum HomeError: Error {
        case notAvailable
    }
}

#endif
