import Foundation
import SwiftUI
import CoreBluetooth

// MARK: - BatteryMonitor

class BatteryMonitor: ObservableObject {
    @Published var batteries: [Battery] = []
    
    private let centralManager: CBCentralManager
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharacteristicUUID = CBUUID(string: "2A19")
    
    init() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        centralManager.scanForPeripherals(withServices: [batteryServiceUUID], options: nil)
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
}

// MARK: - Battery

struct Battery: Identifiable {
    let id: UUID
    let name: String
    var level: Int
    var dischargeRate: Double
    var timeRemaining: TimeInterval
}

// MARK: - CBCentralManagerDelegate

extension BatteryMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name?.contains("Battery") == true {
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([batteryServiceUUID])
    }
}

// MARK: - CBPeripheralDelegate

extension BatteryMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([batteryLevelCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == batteryLevelCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == batteryLevelCharacteristicUUID {
            if let data = characteristic.value, let level = data.first {
                let battery = Battery(id: peripheral.identifier, name: peripheral.name ?? "Unknown", level: Int(level), dischargeRate: 0.0, timeRemaining: 0.0)
                if !batteries.contains(where: { $0.id == battery.id }) {
                    batteries.append(battery)
                }
            }
        }
    }
}