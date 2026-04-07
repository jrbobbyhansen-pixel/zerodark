import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - BluetoothSensorHub

class BluetoothSensorHub: ObservableObject {
    @Published var discoveredSensors: [Sensor] = []
    @Published var pairedSensors: [Sensor] = []
    @Published var sensorData: [Sensor: Data] = [:]
    
    private let centralManager: CBCentralManager
    private var discoveredPeripherals: [CBPeripheral] = []
    
    init() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
    
    func pair(sensor: Sensor) {
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier == sensor.id }) else { return }
        centralManager.connect(peripheral, options: nil)
    }
    
    func unpair(sensor: Sensor) {
        guard let peripheral = pairedSensors.first(where: { $0.id == sensor.id })?.peripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }
}

// MARK: - Sensor

struct Sensor: Identifiable, Equatable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral?
    
    init(id: UUID, name: String, peripheral: CBPeripheral? = nil) {
        self.id = id
        self.name = name
        self.peripheral = peripheral
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothSensorHub: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let sensor = Sensor(id: peripheral.identifier, name: peripheral.name ?? "Unknown Sensor", peripheral: peripheral)
        if !discoveredSensors.contains(sensor) {
            discoveredSensors.append(sensor)
            discoveredPeripherals.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if let index = discoveredPeripherals.firstIndex(of: peripheral) {
            let sensor = discoveredSensors[index]
            pairedSensors.append(sensor)
            discoveredSensors.remove(at: index)
            discoveredPeripherals.remove(at: index)
            peripheral.delegate = self
            peripheral.discoverServices(nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let index = discoveredPeripherals.firstIndex(of: peripheral) {
            discoveredPeripherals.remove(at: index)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let index = pairedSensors.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
            let sensor = pairedSensors[index]
            discoveredSensors.append(sensor)
            pairedSensors.remove(at: index)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothSensorHub: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value {
            sensorData[Sensor(id: peripheral.identifier, name: peripheral.name ?? "Unknown Sensor", peripheral: peripheral)] = data
        }
    }
}