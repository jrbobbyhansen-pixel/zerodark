import Foundation
import CoreBluetooth
import CoreLocation

// MARK: - ExternalGpsManager

class ExternalGpsManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var location: CLLocationCoordinate2D?
    @Published var isConnected: Bool = false
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let serviceUUID = CBUUID(string: "0000180A-0000-1000-8000-00805F9B34FB") // Generic Access Service
    private let characteristicUUID = CBUUID(string: "00002A05-0000-1000-8000-00805F9B34FB") // Device Name
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name?.contains("Garmin") == true || peripheral.name?.contains("Bad Elf") == true || peripheral.name?.contains("Dual XGPS") == true {
            self.peripheral = peripheral
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
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == characteristicUUID {
            if let name = String(data: characteristic.value ?? Data(), encoding: .utf8) {
                print("Connected to: \(name)")
            }
        }
    }
}

// MARK: - ExternalGpsView

struct ExternalGpsView: View {
    @StateObject private var gpsManager = ExternalGpsManager()
    
    var body: some View {
        VStack {
            if gpsManager.isConnected {
                Text("Connected to GPS")
                if let location = gpsManager.location {
                    Text("Latitude: \(location.latitude), Longitude: \(location.longitude)")
                }
            } else {
                Text("Searching for GPS device...")
            }
        }
        .onAppear {
            gpsManager.centralManager.scanForPeripherals(withServices: [gpsManager.serviceUUID], options: nil)
        }
    }
}