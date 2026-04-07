import Foundation
import CoreBluetooth
import CoreLocation
import SwiftUI

// MARK: - InreachInterface

class InreachInterface: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isConnected: Bool = false
    @Published var messageQueue: [String] = []
    @Published var lastPosition: CLLocationCoordinate2D?
    
    private var centralManager: CBCentralManager!
    private var inreachPeripheral: CBPeripheral?
    private let serviceUUID = CBUUID(string: "YOUR_INREACH_SERVICE_UUID")
    private let characteristicUUID = CBUUID(string: "YOUR_INREACH_CHARACTERISTIC_UUID")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func connect() {
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    func disconnect() {
        centralManager.cancelPeripheralConnection(inreachPeripheral ?? CBPeripheral())
    }
    
    func sendMessage(_ message: String) {
        if isConnected {
            if let data = message.data(using: .utf8) {
                inreachPeripheral?.writeValue(data, for: characteristic, type: .withResponse)
            }
        } else {
            messageQueue.append(message)
        }
    }
    
    func triggerSOS() {
        // Implement SOS trigger logic
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connect()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name?.contains("InReach") == true {
            inreachPeripheral = peripheral
            centralManager.stopScan()
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value, let message = String(data: data, encoding: .utf8) {
            // Handle incoming message
        }
    }
}

// MARK: - InreachViewModel

class InreachViewModel: ObservableObject {
    @Published var inreachInterface: InreachInterface
    
    init() {
        inreachInterface = InreachInterface()
    }
    
    func connect() {
        inreachInterface.connect()
    }
    
    func disconnect() {
        inreachInterface.disconnect()
    }
    
    func sendMessage(_ message: String) {
        inreachInterface.sendMessage(message)
    }
    
    func triggerSOS() {
        inreachInterface.triggerSOS()
    }
}