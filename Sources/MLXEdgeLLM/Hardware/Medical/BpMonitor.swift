import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - Blood Pressure Monitor Service

class BpMonitor: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var systolic: Int = 0
    @Published var diastolic: Int = 0
    @Published var map: Int = 0
    @Published var pulse: Int = 0
    @Published var trend: String = ""
    @Published var alertThreshold: Int = 140 // Default alert threshold for systolic blood pressure

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let bloodPressureServiceUUID = CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")
    private let bloodPressureMeasurementCharacteristicUUID = CBUUID(string: "00002A35-0000-1000-8000-00805F9B34FB")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        centralManager.scanForPeripherals(withServices: [bloodPressureServiceUUID], options: nil)
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([bloodPressureServiceUUID])
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == bloodPressureServiceUUID {
                peripheral.discoverCharacteristics([bloodPressureMeasurementCharacteristicUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == bloodPressureMeasurementCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        parseBloodPressureData(data)
    }

    private func parseBloodPressureData(_ data: Data) {
        // Example parsing logic, adjust based on actual data format
        if data.count >= 7 {
            systolic = Int(data[1]) << 8 | Int(data[2])
            diastolic = Int(data[3]) << 8 | Int(data[4])
            map = Int(data[5]) << 8 | Int(data[6])
            pulse = Int(data[7]) << 8 | Int(data[8])
            updateTrend()
        }
    }

    private func updateTrend() {
        // Simple trend tracking logic
        if systolic > alertThreshold {
            trend = "High"
        } else {
            trend = "Normal"
        }
    }
}

// MARK: - Blood Pressure Monitor View Model

class BpMonitorViewModel: ObservableObject {
    @ObservedObject var bpMonitor: BpMonitor

    init() {
        bpMonitor = BpMonitor()
        bpMonitor.startScanning()
    }
}

// MARK: - Blood Pressure Monitor View

struct BpMonitorView: View {
    @StateObject private var viewModel = BpMonitorViewModel()

    var body: some View {
        VStack {
            Text("Systolic: \(viewModel.bpMonitor.systolic)")
            Text("Diastolic: \(viewModel.bpMonitor.diastolic)")
            Text("MAP: \(viewModel.bpMonitor.map)")
            Text("Pulse: \(viewModel.bpMonitor.pulse)")
            Text("Trend: \(viewModel.bpMonitor.trend)")
            Text("Alert Threshold: \(viewModel.bpMonitor.alertThreshold)")
        }
        .onAppear {
            viewModel.bpMonitor.startScanning()
        }
        .onDisappear {
            viewModel.bpMonitor.stopScanning()
        }
    }
}