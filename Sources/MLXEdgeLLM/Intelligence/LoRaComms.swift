//
//  LoRaComms.swift
//  ZeroDark
//
//  Encrypted LoRa radio communications for off-grid messaging
//  Supports: Emergency beacons, location sharing, dead drop waypoints
//

import Foundation
import CoreBluetooth
import CoreLocation
import CryptoKit
#if os(iOS)
import UIKit
#endif

// MARK: - LoRa Communications Manager

@MainActor
public class LoRaCommsManager: NSObject, ObservableObject {
    public static let shared = LoRaCommsManager()
    
    // MARK: - Published State
    @Published public var isConnected = false
    @Published public var signalStrength: Int = 0 // dBm
    @Published public var lastMessageTime: Date?
    @Published public var pendingMessages: [LoRaMessage] = []
    @Published public var receivedMessages: [LoRaMessage] = []
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    
    // MARK: - Bluetooth
    private var centralManager: CBCentralManager?
    private var loraPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var readCharacteristic: CBCharacteristic?
    
    // MARK: - Encryption
    private var symmetricKey: SymmetricKey?
    
    // MARK: - Constants
    private let loraServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") // Nordic UART
    private let txCharUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    public enum ConnectionStatus: String {
        case disconnected = "Disconnected"
        case scanning = "Scanning..."
        case connecting = "Connecting..."
        case connected = "Connected"
        case error = "Error"
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        setupEncryption()
    }
    
    private func setupEncryption() {
        // Generate or load encryption key
        // In production: derive from shared secret or PKI
        symmetricKey = SymmetricKey(size: .bits256)
    }
    
    // MARK: - Connection Management
    
    public func startScanning() {
        connectionStatus = .scanning
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    public func disconnect() {
        if let peripheral = loraPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        loraPeripheral = nil
        isConnected = false
        connectionStatus = .disconnected
    }
    
    // MARK: - Message Sending
    
    /// Send an emergency beacon with current location
    public func sendEmergencyBeacon(location: CLLocationCoordinate2D?) {
        let message = LoRaMessage(
            type: .emergency,
            payload: EmergencyPayload(
                timestamp: Date(),
                location: location,
                batteryLevel: getBatteryLevel(),
                additionalInfo: "EMERGENCY BEACON"
            ),
            encrypted: true
        )
        
        sendMessage(message)
        print("🚨 Emergency beacon sent")
    }
    
    /// Send current location to trusted contacts
    public func sendLocation(_ location: CLLocationCoordinate2D, to recipient: String? = nil) {
        let message = LoRaMessage(
            type: .location,
            payload: LocationPayload(
                coordinate: location,
                altitude: nil,
                accuracy: 10,
                timestamp: Date()
            ),
            encrypted: true,
            recipient: recipient
        )
        
        sendMessage(message)
    }
    
    /// Send a text message
    public func sendTextMessage(_ text: String, to recipient: String? = nil) {
        let message = LoRaMessage(
            type: .text,
            payload: TextPayload(content: text),
            encrypted: true,
            recipient: recipient
        )
        
        sendMessage(message)
    }
    
    /// Create a dead drop waypoint
    public func createDeadDrop(at location: CLLocationCoordinate2D, message: String, validUntil: Date) {
        let message = LoRaMessage(
            type: .deadDrop,
            payload: DeadDropPayload(
                location: location,
                encryptedMessage: message,
                validUntil: validUntil,
                fingerprint: nil // Will be set by LiDAR
            ),
            encrypted: true
        )
        
        sendMessage(message)
    }
    
    // MARK: - Private Methods
    
    private func sendMessage(_ message: LoRaMessage) {
        guard isConnected, let characteristic = writeCharacteristic else {
            pendingMessages.append(message)
            print("⚠️ LoRa not connected - message queued")
            return
        }
        
        do {
            let data = try encodeAndEncrypt(message)
            loraPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
            lastMessageTime = Date()
        } catch {
            print("❌ Failed to send message: \(error)")
        }
    }
    
    private func encodeAndEncrypt(_ message: LoRaMessage) throws -> Data {
        let encoder = JSONEncoder()
        let plainData = try encoder.encode(message)
        
        guard message.encrypted, let key = symmetricKey else {
            return plainData
        }
        
        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(plainData, using: key)
        return sealedBox.combined!
    }
    
    private func decryptAndDecode(_ data: Data) throws -> LoRaMessage {
        guard let key = symmetricKey else {
            return try JSONDecoder().decode(LoRaMessage.self, from: data)
        }
        
        // Decrypt with AES-GCM
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        return try JSONDecoder().decode(LoRaMessage.self, from: decryptedData)
    }
    
    private func getBatteryLevel() -> Int {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int(UIDevice.current.batteryLevel * 100)
        #else
        return 100
        #endif
    }
    
    private func processReceivedData(_ data: Data) {
        do {
            let message = try decryptAndDecode(data)
            receivedMessages.insert(message, at: 0)
            
            // Handle special message types
            switch message.type {
            case .emergency:
                handleEmergency(message)
            case .deadDrop:
                handleDeadDrop(message)
            default:
                break
            }
        } catch {
            print("❌ Failed to decode received message: \(error)")
        }
    }
    
    private func handleEmergency(_ message: LoRaMessage) {
        // Alert user to emergency beacon from another device
        print("🚨 EMERGENCY BEACON RECEIVED")
    }
    
    private func handleDeadDrop(_ message: LoRaMessage) {
        // Store dead drop for later retrieval
        print("📍 Dead drop marker received")
    }
}

// MARK: - CBCentralManagerDelegate

extension LoRaCommsManager: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                central.scanForPeripherals(withServices: [loraServiceUUID], options: nil)
            case .poweredOff:
                connectionStatus = .error
            default:
                break
            }
        }
    }
    
    public nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            // Found LoRa device
            central.stopScan()
            loraPeripheral = peripheral
            connectionStatus = .connecting
            central.connect(peripheral, options: nil)
        }
    }
    
    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            peripheral.discoverServices([loraServiceUUID])
        }
    }
    
    public nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnected = false
            connectionStatus = .disconnected
        }
    }
}

// MARK: - CBPeripheralDelegate

extension LoRaCommsManager: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }
            for service in services {
                peripheral.discoverCharacteristics([txCharUUID, rxCharUUID], for: service)
            }
        }
    }
    
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics {
                if characteristic.uuid == txCharUUID {
                    writeCharacteristic = characteristic
                } else if characteristic.uuid == rxCharUUID {
                    readCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            
            if writeCharacteristic != nil && readCharacteristic != nil {
                isConnected = true
                connectionStatus = .connected
                
                // Send any pending messages
                for message in pendingMessages {
                    sendMessage(message)
                }
                pendingMessages.removeAll()
            }
        }
    }
    
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }
            processReceivedData(data)
        }
    }
    
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        Task { @MainActor in
            signalStrength = RSSI.intValue
        }
    }
}

// MARK: - Message Types

public struct LoRaMessage: Codable, Identifiable {
    public let id: UUID
    public let type: MessageType
    public let payload: MessagePayload
    public let encrypted: Bool
    public let timestamp: Date
    public let recipient: String?
    public let sender: String?
    
    public enum MessageType: String, Codable {
        case text
        case location
        case emergency
        case deadDrop
        case ping
        case ack
    }
    
    init(type: MessageType, payload: any Codable, encrypted: Bool, recipient: String? = nil) {
        self.id = UUID()
        self.type = type
        self.payload = MessagePayload(wrapping: payload)
        self.encrypted = encrypted
        self.timestamp = Date()
        self.recipient = recipient
        self.sender = nil // Will be set by device ID
    }
}

public struct MessagePayload: Codable {
    private let data: Data
    
    init(wrapping value: any Codable) {
        self.data = (try? JSONEncoder().encode(AnyEncodable(value))) ?? Data()
    }
    
    func decode<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}

// Type erasure helper
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    
    init(_ value: any Encodable) {
        self.encode = { encoder in
            try value.encode(to: encoder)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

// MARK: - Payload Types

public struct TextPayload: Codable {
    public let content: String
}

public struct LocationPayload: Codable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let accuracy: Double
    public let timestamp: Date
    
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(coordinate: CLLocationCoordinate2D, altitude: Double?, accuracy: Double, timestamp: Date) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.altitude = altitude
        self.accuracy = accuracy
        self.timestamp = timestamp
    }
}

public struct EmergencyPayload: Codable {
    public let timestamp: Date
    public let latitude: Double?
    public let longitude: Double?
    public let batteryLevel: Int
    public let additionalInfo: String?
    
    public var location: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    public init(timestamp: Date, location: CLLocationCoordinate2D?, batteryLevel: Int, additionalInfo: String?) {
        self.timestamp = timestamp
        self.latitude = location?.latitude
        self.longitude = location?.longitude
        self.batteryLevel = batteryLevel
        self.additionalInfo = additionalInfo
    }
}

public struct DeadDropPayload: Codable {
    public let latitude: Double
    public let longitude: Double
    public let encryptedMessage: String
    public let validUntil: Date
    public let fingerprint: Data? // LiDAR spatial fingerprint
    
    public var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    public init(location: CLLocationCoordinate2D, encryptedMessage: String, validUntil: Date, fingerprint: Data?) {
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.encryptedMessage = encryptedMessage
        self.validUntil = validUntil
        self.fingerprint = fingerprint
    }
}
