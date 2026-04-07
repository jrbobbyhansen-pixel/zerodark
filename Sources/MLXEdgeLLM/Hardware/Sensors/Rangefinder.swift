import Foundation
import CoreBluetooth
import ARKit
import SwiftUI

// MARK: - Rangefinder Service

class RangefinderService: ObservableObject {
    @Published var distance: Double = 0.0
    @Published var angle: Double = 0.0
    @Published var height: Double = 0.0
    @Published var isConnected: Bool = false
    
    private let centralManager = CBCentralManager()
    private var rangefinderPeripheral: CBPeripheral?
    
    init() {
        centralManager.delegate = self
        centralManager.scanForPeripherals(withServices: [CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")], options: nil)
    }
    
    func connect(to peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = rangefinderPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}

extension RangefinderService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")], options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name?.contains("Rangefinder") == true {
            rangefinderPeripheral = peripheral
            connect(to: peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: "0000180F-0000-1000-8000-00805F9B34FB")])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
    }
}

extension RangefinderService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([CBUUID(string: "00002A56-0000-1000-8000-00805F9B34FB")], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        // Parse data to extract distance, angle, height
        // Example: Assuming data is a 12-byte array with distance, angle, height in that order
        if data.count == 12 {
            let distanceData = data.subdata(in: 0..<4)
            let angleData = data.subdata(in: 4..<8)
            let heightData = data.subdata(in: 8..<12)
            
            distance = Double(distanceData.withUnsafeBytes { $0.load(as: Float.self) })
            angle = Double(angleData.withUnsafeBytes { $0.load(as: Float.self) })
            height = Double(heightData.withUnsafeBytes { $0.load(as: Float.self) })
        }
    }
}

// MARK: - Rangefinder View Model

class RangefinderViewModel: ObservableObject {
    @Published var rangefinderService: RangefinderService
    
    init(rangefinderService: RangefinderService) {
        self.rangefinderService = rangefinderService
    }
    
    func connectRangefinder() {
        if let peripheral = rangefinderService.rangefinderPeripheral {
            rangefinderService.connect(to: peripheral)
        }
    }
    
    func disconnectRangefinder() {
        rangefinderService.disconnect()
    }
}

// MARK: - Rangefinder View

struct RangefinderView: View {
    @StateObject private var viewModel = RangefinderViewModel(rangefinderService: RangefinderService())
    
    var body: some View {
        VStack {
            Text("Distance: \(viewModel.rangefinderService.distance, specifier: "%.2f") m")
            Text("Angle: \(viewModel.rangefinderService.angle, specifier: "%.2f")°")
            Text("Height: \(viewModel.rangefinderService.height, specifier: "%.2f") m")
            
            Button(action: {
                viewModel.connectRangefinder()
            }) {
                Text("Connect Rangefinder")
            }
            .disabled(viewModel.rangefinderService.isConnected)
            
            Button(action: {
                viewModel.disconnectRangefinder()
            }) {
                Text("Disconnect Rangefinder")
            }
            .disabled(!viewModel.rangefinderService.isConnected)
        }
        .padding()
    }
}

// MARK: - Preview

struct RangefinderView_Previews: PreviewProvider {
    static var previews: some View {
        RangefinderView()
    }
}