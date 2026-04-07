import Foundation
import SwiftUI
import CoreBluetooth

// MARK: - PulseOxInterface

class PulseOxInterface: ObservableObject {
    @Published var spo2: Double = 0.0
    @Published var pulseRate: Double = 0.0
    @Published var waveform: [Double] = []
    @Published var isConnected: Bool = false
    @Published var alert: String? = nil
    
    private let centralManager = CBCentralManager(delegate: self, queue: nil)
    private var peripheral: CBPeripheral?
    private var spo2Characteristic: CBCharacteristic?
    private var pulseRateCharacteristic: CBCharacteristic?
    private var waveformCharacteristic: CBCharacteristic?
    
    init() {
        centralManager.delegate = self
    }
    
    func startScanning() {
        centralManager.scanForPeripherals(withServices: [CBUUID(string: "00001808-0000-1000-8000-00805F9B34FB")], options: nil)
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
    
    func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PulseOxInterface: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name?.contains("PulseOx") == true {
            connect(to: peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: "00001808-0000-1000-8000-00805F9B34FB")])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        alert = "Failed to connect to pulse oximeter"
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        alert = "Disconnected from pulse oximeter"
    }
}

// MARK: - CBPeripheralDelegate

extension PulseOxInterface: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == CBUUID(string: "00002A5F-0000-1000-8000-00805F9B34FB") {
                spo2Characteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == CBUUID(string: "00002A37-0000-1000-8000-00805F9B34FB") {
                pulseRateCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == CBUUID(string: "00002A38-0000-1000-8000-00805F9B34FB") {
                waveformCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic == spo2Characteristic {
            if let data = characteristic.value, let spo2 = Double(data.withUnsafeBytes { $0.load(as: UInt8.self) }) {
                self.spo2 = Double(spo2) / 100.0
            }
        } else if characteristic == pulseRateCharacteristic {
            if let data = characteristic.value, let pulseRate = Double(data.withUnsafeBytes { $0.load(as: UInt8.self) }) {
                self.pulseRate = Double(pulseRate)
            }
        } else if characteristic == waveformCharacteristic {
            if let data = characteristic.value {
                self.waveform = data.map { Double($0) }
            }
        }
    }
}

// MARK: - PulseOxView

struct PulseOxView: View {
    @StateObject private var pulseOxInterface = PulseOxInterface()
    
    var body: some View {
        VStack {
            Text("Pulse Oximeter")
                .font(.largeTitle)
                .padding()
            
            HStack {
                VStack {
                    Text("SpO2")
                        .font(.headline)
                    Text("\(String(format: "%.2f", pulseOxInterface.spo2))%")
                        .font(.title)
                }
                VStack {
                    Text("Pulse Rate")
                        .font(.headline)
                    Text("\(String(format: "%.0f", pulseOxInterface.pulseRate)) bpm")
                        .font(.title)
                }
            }
            .padding()
            
            Button(action: {
                if pulseOxInterface.isConnected {
                    pulseOxInterface.disconnect()
                } else {
                    pulseOxInterface.startScanning()
                }
            }) {
                Text(pulseOxInterface.isConnected ? "Disconnect" : "Connect")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            
            if let alert = pulseOxInterface.alert {
                Text(alert)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear {
            pulseOxInterface.startScanning()
        }
        .onDisappear {
            pulseOxInterface.stopScanning()
            pulseOxInterface.disconnect()
        }
    }
}

// MARK: - Preview

struct PulseOxView_Previews: PreviewProvider {
    static var previews: some View {
        PulseOxView()
    }
}