import Foundation
import SwiftUI
import CoreBluetooth

// MARK: - HeartRateMonitor

class HeartRateMonitor: ObservableObject {
    @Published var heartRate: Int? = nil
    @Published var heartRateZones: [HeartRateZone] = []
    @Published var fatigueLevel: FatigueLevel = .normal
    @Published var isMonitoring: Bool = false
    
    private let centralManager = CBCentralManager(delegate: self, queue: nil)
    private var heartRatePeripheral: CBPeripheral?
    
    func startMonitoring() {
        isMonitoring = true
        centralManager.scanForPeripherals(withServices: [CBUUID(string: "180D")], options: nil)
    }
    
    func stopMonitoring() {
        isMonitoring = false
        centralManager.stopScan()
        heartRatePeripheral?.disconnect()
    }
}

// MARK: - HeartRateZone

struct HeartRateZone {
    let name: String
    let range: ClosedRange<Int>
}

// MARK: - FatigueLevel

enum FatigueLevel: String {
    case veryLow = "Very Low"
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case veryHigh = "Very High"
}

// MARK: - CBCentralManagerDelegate

extension HeartRateMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startMonitoring()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name?.contains("Heart Rate") == true {
            heartRatePeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
            centralManager.stopScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: "180D")])
    }
}

// MARK: - CBPeripheralDelegate

extension HeartRateMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, characteristic.properties.contains(.notify) else { return }
        let heartRate = Int(data.withUnsafeBytes { $0.load(as: UInt8.self) })
        self.heartRate = heartRate
        updateHeartRateZones()
        updateFatigueLevel()
    }
}

// MARK: - HeartRateMonitorView

struct HeartRateMonitorView: View {
    @StateObject private var heartRateMonitor = HeartRateMonitor()
    
    var body: some View {
        VStack {
            Text("Heart Rate: \(heartRateMonitor.heartRate ?? 0)")
                .font(.largeTitle)
            
            ForEach(heartRateMonitor.heartRateZones) { zone in
                Text("\(zone.name): \(zone.range.lowerBound) - \(zone.range.upperBound)")
            }
            
            Text("Fatigue Level: \(heartRateMonitor.fatigueLevel.rawValue)")
                .font(.title2)
            
            Button(action: {
                if heartRateMonitor.isMonitoring {
                    heartRateMonitor.stopMonitoring()
                } else {
                    heartRateMonitor.startMonitoring()
                }
            }) {
                Text(heartRateMonitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
            }
            .padding()
            .background(heartRateMonitor.isMonitoring ? Color.red : Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}

// MARK: - Private Methods

private extension HeartRateMonitor {
    func updateHeartRateZones() {
        guard let heartRate = heartRate else { return }
        heartRateZones = [
            HeartRateZone(name: "Zone 1", range: 0...50),
            HeartRateZone(name: "Zone 2", range: 51...100),
            HeartRateZone(name: "Zone 3", range: 101...150),
            HeartRateZone(name: "Zone 4", range: 151...200),
            HeartRateZone(name: "Zone 5", range: 201...300)
        ].filter { $0.range.contains(heartRate) }
    }
    
    func updateFatigueLevel() {
        guard let heartRate = heartRate else { return }
        switch heartRate {
        case 0...50:
            fatigueLevel = .veryLow
        case 51...100:
            fatigueLevel = .low
        case 101...150:
            fatigueLevel = .normal
        case 151...200:
            fatigueLevel = .high
        case 201...300:
            fatigueLevel = .veryHigh
        default:
            fatigueLevel = .normal
        }
    }
}