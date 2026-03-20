// TAKBLEBridge.swift — TAK-BLE GATT Service Bridge
// Implements Bluetooth LE Cursor-on-Target relay using Raytheon's TAK-BLE GATT profile

import Foundation
import CoreBluetooth
import CoreLocation
import Combine

@MainActor
final class TAKBLEBridge: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = TAKBLEBridge()

    @Published var isScanning = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var isConnected = false
    @Published var lastError: String?

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var characteristicP2C: CBCharacteristic?  // Peripheral → Central (NOTIFY)
    private var characteristicC2P: CBCharacteristic?  // Central → Peripheral (WRITE)

    private var receiveBuffer = Data()
    private let eventDelimiter = "</event>".data(using: .utf8)!

    private let encoder = CoTEncoder.shared
    private let decoder = CoTDecoder.shared

    // TAK-BLE GATT Profile UUIDs (from Raytheon TAK-BLE source)
    private let TAK_BLE_SERVICE_UUID = CBUUID(string: "0000180D-0000-1000-8000-00805f9b34fb")
    private let PERIPHERAL_TO_CENTRAL_UUID = CBUUID(string: "00002a00-0000-1000-8000-00805f9b34fb")
    private let CENTRAL_TO_PERIPHERAL_UUID = CBUUID(string: "00002a0f-0000-1000-8000-00805f9b34fb")

    private let sendQueue = DispatchQueue(label: "com.zerodark.takble.send")
    private var pendingChunks: [Data] = []
    private var chunkSendTimer: Timer?

    private override init() {
        super.init()
        let queue = DispatchQueue(label: "com.zerodark.takble.central")
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Scanning & Connection

    func startScanning() {
        guard let centralManager = centralManager else { return }
        guard centralManager.state == .poweredOn else {
            lastError = "Bluetooth not available"
            return
        }

        discoveredPeripherals.removeAll()
        isScanning = true
        lastError = nil

        // Scan for TAK-BLE service UUID with 30-second timeout
        centralManager.scanForPeripherals(withServices: [TAK_BLE_SERVICE_UUID], options: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.stopScanning()
        }
    }

    func stopScanning() {
        guard let centralManager = centralManager else { return }
        centralManager.stopScan()
        isScanning = false
    }

    func connect(to peripheral: CBPeripheral) {
        guard let centralManager = centralManager else { return }
        stopScanning()
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        isConnected = false
        receiveBuffer.removeAll()
        chunkSendTimer?.invalidate()
    }

    // MARK: - Sending CoT Events over BLE

    func sendCoT(_ event: CoTEvent) {
        guard isConnected, let characteristic = characteristicC2P else { return }

        let xmlData = encoder.encode(event)

        // Chunk at MTU - 3 bytes (default MTU 512, usable 509)
        // MTU negotiation happens automatically, use safe default
        let chunkSize = 509
        var chunks: [Data] = []

        var offset = 0
        while offset < xmlData.count {
            let endIndex = min(offset + chunkSize, xmlData.count)
            let chunk = xmlData.subdata(in: offset..<endIndex)
            chunks.append(chunk)
            offset = endIndex
        }

        // Queue chunks with 500ms delay between sends (from TAK-BLE spec)
        pendingChunks = chunks
        sendNextChunk(characteristic: characteristic)
    }

    private func sendNextChunk(characteristic: CBCharacteristic) {
        guard !pendingChunks.isEmpty else { return }

        let chunk = pendingChunks.removeFirst()

        connectedPeripheral?.writeValue(chunk, for: characteristic, type: .withResponse)

        // Schedule next chunk with 500ms delay
        chunkSendTimer?.invalidate()
        chunkSendTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.sendNextChunk(characteristic: characteristic)
        }
    }

    // MARK: - Receiving CoT Events from BLE

    private func processNotification(_ data: Data) {
        receiveBuffer.append(data)

        // Search for complete events
        while let delimiterRange = receiveBuffer.range(of: eventDelimiter) {
            let eventEnd = delimiterRange.lowerBound + eventDelimiter.count
            let eventData = receiveBuffer.subdata(in: 0..<eventEnd)

            // Decode CoT event
            if let event = decoder.decode(eventData) {
                handleReceivedEvent(event)
            }

            receiveBuffer.removeFirst(eventEnd)
        }
    }

    private func handleReceivedEvent(_ event: CoTEvent) {
        DispatchQueue.main.async {
            // Forward to FreeTAK connector peer list if connected
            if FreeTAKConnector.shared.isConnected {
                FreeTAKConnector.shared.peers.append(event)
            }

            // Also forward to mesh service if it's a location event
            if event.type.contains("a-f") || event.type.contains("a-h") {
                let coordinate = CLLocationCoordinate2D(latitude: event.lat, longitude: event.lon)
                MeshService.shared.shareLocation(coordinate)
            }
        }
    }

    // MARK: - CBCentralManagerDelegate

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            switch central.state {
            case .poweredOn:
                self.lastError = nil
            case .poweredOff:
                self.lastError = "Bluetooth is off"
                self.isConnected = false
            case .unauthorized:
                self.lastError = "Bluetooth permission denied"
            case .unsupported:
                self.lastError = "Bluetooth not supported"
            default:
                self.lastError = "Bluetooth unavailable"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didDiscover peripheral: CBPeripheral,
                                   advertisementData: [String: Any],
                                   rssi RSSI: NSNumber) {
        DispatchQueue.main.async {
            if !self.discoveredPeripherals.contains(peripheral) {
                self.discoveredPeripherals.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.connectedPeripheral = peripheral
            self.isConnected = true
            self.lastError = nil
        }

        peripheral.delegate = self
        peripheral.discoverServices([self.TAK_BLE_SERVICE_UUID])
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didFailToConnect peripheral: CBPeripheral,
                                   error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.lastError = error?.localizedDescription ?? "Connection failed"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                   didDisconnectPeripheral peripheral: CBPeripheral,
                                   error: Error?) {
        DispatchQueue.main.async {
            if self.connectedPeripheral?.identifier == peripheral.identifier {
                self.connectedPeripheral = nil
                self.isConnected = false
                self.lastError = error?.localizedDescription ?? "Disconnected"
            }
        }
    }

    // MARK: - CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                               didDiscoverServices error: Error?) {
        guard error == nil else { return }

        for service in peripheral.services ?? [] {
            if service.uuid == TAK_BLE_SERVICE_UUID {
                peripheral.discoverCharacteristics(
                    [PERIPHERAL_TO_CENTRAL_UUID, CENTRAL_TO_PERIPHERAL_UUID],
                    for: service
                )
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                               didDiscoverCharacteristicsFor service: CBService,
                               error: Error?) {
        guard error == nil else { return }

        DispatchQueue.main.async {
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == self.PERIPHERAL_TO_CENTRAL_UUID {
                    self.characteristicP2C = characteristic
                    // Enable notifications
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == self.CENTRAL_TO_PERIPHERAL_UUID {
                    self.characteristicC2P = characteristic
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                               didUpdateNotificationStateFor characteristic: CBCharacteristic,
                               error: Error?) {
        if error != nil {
            DispatchQueue.main.async {
                self.lastError = error?.localizedDescription ?? "Notification setup failed"
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                               didUpdateValueFor characteristic: CBCharacteristic,
                               error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        DispatchQueue.main.async {
            self.processNotification(data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                               didWriteValueFor characteristic: CBCharacteristic,
                               error: Error?) {
        if error != nil {
            DispatchQueue.main.async {
                self.lastError = error?.localizedDescription ?? "Write failed"
            }
        }
    }
}
