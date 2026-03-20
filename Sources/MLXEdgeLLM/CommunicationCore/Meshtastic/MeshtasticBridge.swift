// MeshtasticBridge.swift — BLE Bridge to Meshtastic LoRa Hardware
// Connects to Meshtastic devices and bridges positions/messages into mesh

import CoreBluetooth
import CoreLocation
import Foundation

// Official Meshtastic BLE service and characteristic UUIDs
private let meshtasticServiceUUID = CBUUID(string: "6BA1B218-15A8-461F-9FA8-5D651A2B8888")
private let toRadioCharUUID       = CBUUID(string: "F75C76D2-129E-4DAD-A1DD-7866124401E7")
private let fromRadioCharUUID     = CBUUID(string: "2C55E69E-4993-11ED-B878-0242AC120002")

struct MeshtasticNode: Identifiable {
    let id: String
    let shortName: String
    let longName: String
    var lastSeen: Date
    var coordinate: CLLocationCoordinate2D?
    var batteryLevel: Int?
    var snr: Float?
}

@MainActor
final class MeshtasticBridge: NSObject, ObservableObject {
    static let shared = MeshtasticBridge()

    @Published var isConnected = false
    @Published var isScanning = false
    @Published var connectedDevice: String? = nil
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var meshNodes: [MeshtasticNode] = []

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var toRadioChar: CBCharacteristic?

    override private init() {}

    func startScan() {
        centralManager = CBCentralManager(delegate: self, queue: .main)
        isScanning = true
    }

    func stopScan() {
        centralManager?.stopScan()
        isScanning = false
    }

    func connect(to peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let p = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(p)
        }
        isConnected = false
        connectedDevice = nil
        toRadioChar = nil
    }

    /// Send device position to Meshtastic mesh
    func sendPosition(coordinate: CLLocationCoordinate2D, callsign: String) {
        guard let char = toRadioChar, let peripheral = connectedPeripheral else { return }
        let packet = encodeMeshtasticPosition(
            lat: coordinate.latitude,
            lon: coordinate.longitude,
            callsign: callsign
        )
        peripheral.writeValue(packet, for: char, type: .withResponse)
    }

    /// Send text message to Meshtastic mesh
    func sendText(_ message: String) {
        guard let char = toRadioChar, let peripheral = connectedPeripheral else { return }
        let packet = encodeMeshtasticText(message)
        peripheral.writeValue(packet, for: char, type: .withResponse)
    }

    /// Parse incoming fromRadio packets
    private func handleIncomingPacket(_ data: Data) {
        var offset = 0
        let bytes = [UInt8](data)

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = readProtoFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (3, 2): // fromRadio.packet = MeshPacket (length-delimited)
                guard let (length, lenBytes) = readVarint(bytes, offset: offset) else { break }
                offset += lenBytes
                let packetBytes = Array(bytes[offset..<min(offset + Int(length), bytes.count)])
                offset += Int(length)
                parseMeshPacket(packetBytes)

            default:
                // Skip unknown fields
                if wireType == 2, let (length, lenBytes) = readVarint(bytes, offset: offset) {
                    offset += lenBytes + Int(length)
                } else if wireType == 0, let (_, varBytes) = readVarint(bytes, offset: offset) {
                    offset += varBytes
                } else {
                    offset = bytes.count
                }
            }
        }
    }

    private func parseMeshPacket(_ bytes: [UInt8]) {
        var nodeId: UInt32 = 0
        var offset = 0

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = readProtoFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (1, 0): // from (node ID)
                if let (v, n) = readVarint(bytes, offset: offset) {
                    nodeId = UInt32(v & 0xFFFFFFFF)
                    offset += n
                }
            case (6, 2): // decoded Data message
                if let (length, lenBytes) = readVarint(bytes, offset: offset) {
                    offset += lenBytes
                    let dataBytes = Array(bytes[offset..<min(offset + Int(length), bytes.count)])
                    offset += Int(length)
                    parseDataMessage(dataBytes, nodeId: nodeId)
                }
            default:
                if wireType == 2, let (length, lenBytes) = readVarint(bytes, offset: offset) {
                    offset += lenBytes + Int(length)
                } else if wireType == 0, let (_, n) = readVarint(bytes, offset: offset) {
                    offset += n
                } else { offset = bytes.count }
            }
        }
    }

    private func parseDataMessage(_ bytes: [UInt8], nodeId: UInt32) {
        var portnum: Int = 0
        var payload = Data()
        var offset = 0

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = readProtoFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (1, 0): // portnum
                if let (v, n) = readVarint(bytes, offset: offset) { portnum = Int(v); offset += n }
            case (2, 2): // payload
                if let (length, lenBytes) = readVarint(bytes, offset: offset) {
                    offset += lenBytes
                    payload = Data(bytes[offset..<min(offset + Int(length), bytes.count)])
                    offset += Int(length)
                }
            default:
                if wireType == 2, let (length, lenBytes) = readVarint(bytes, offset: offset) {
                    offset += lenBytes + Int(length)
                } else if wireType == 0, let (_, n) = readVarint(bytes, offset: offset) {
                    offset += n
                } else { offset = bytes.count }
            }
        }

        if portnum == 1 { // POSITION_APP
            if let (lat, lon) = parsePosition(payload) {
                let hexId = String(format: "%08x", nodeId)
                let node = MeshtasticNode(
                    id: hexId, shortName: hexId.prefix(4).uppercased(),
                    longName: "", lastSeen: Date(),
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                if let idx = meshNodes.firstIndex(where: { $0.id == hexId }) {
                    meshNodes[idx] = node
                } else {
                    meshNodes.append(node)
                }
                Task { @MainActor in
                    MeshService.shared.updatePeerFromMeshtastic(node)
                }
            }
        }
    }

    private func parsePosition(_ data: Data) -> (Double, Double)? {
        let bytes = [UInt8](data)
        var lat: Int64 = 0; var lon: Int64 = 0
        var offset = 0
        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = readProtoFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen
            if wireType == 0, let (v, n) = readVarint(bytes, offset: offset) {
                if fieldTag == 1 { lat = Int64(bitPattern: v) }
                else if fieldTag == 2 { lon = Int64(bitPattern: v) }
                offset += n
            } else { break }
        }
        guard lat != 0 || lon != 0 else { return nil }
        return (Double(lat) / 1e7, Double(lon) / 1e7)
    }

    // MARK: - Minimal Protobuf Encoding

    private func encodeVarint(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
        return data
    }

    private func encodeField(tag: Int, wireType: Int, value: Data) -> Data {
        var data = Data()
        data.append(contentsOf: encodeVarint(UInt64(tag << 3 | wireType)))
        data.append(contentsOf: encodeVarint(UInt64(value.count)))
        data.append(value)
        return data
    }

    private func encodeMeshtasticPosition(lat: Double, lon: Double, callsign: String) -> Data {
        var posPayload = Data()
        let latI = Int32(lat * 1e7)
        let lonI = Int32(lon * 1e7)
        posPayload.append(contentsOf: encodeField(tag: 1, wireType: 0,
            value: encodeVarint(UInt64(bitPattern: Int64(latI)))))
        posPayload.append(contentsOf: encodeField(tag: 2, wireType: 0,
            value: encodeVarint(UInt64(bitPattern: Int64(lonI)))))
        return encodeField(tag: 1, wireType: 2, value: posPayload)
    }

    private func encodeMeshtasticText(_ text: String) -> Data {
        guard let textData = text.data(using: .utf8) else { return Data() }
        var decoded = Data()
        decoded.append(contentsOf: encodeField(tag: 1, wireType: 0, value: encodeVarint(1)))
        decoded.append(contentsOf: encodeField(tag: 2, wireType: 2, value: textData))
        return encodeField(tag: 1, wireType: 2, value: decoded)
    }

    // MARK: - Minimal Protobuf Decoding Helpers

    private func readVarint(_ bytes: [UInt8], offset: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0; var shift = 0; var i = offset
        while i < bytes.count {
            let byte = bytes[i]; i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, i - offset) }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    private func readProtoFieldHeader(_ bytes: [UInt8], offset: Int) -> (tag: Int, wireType: Int, headerLen: Int)? {
        guard let (v, n) = readVarint(bytes, offset: offset) else { return nil }
        return (Int(v >> 3), Int(v & 0x07), n)
    }
}

// MARK: - CBCentralManagerDelegate

extension MeshtasticBridge: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            guard central.state == .poweredOn else { return }
            central.scanForPeripherals(
                withServices: [meshtasticServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discoveredDevices.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.connectedDevice = peripheral.name ?? peripheral.identifier.uuidString
            peripheral.discoverServices([meshtasticServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.connectedDevice = nil
        }
    }
}

// MARK: - CBPeripheralDelegate

extension MeshtasticBridge: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == meshtasticServiceUUID }) else {
            return
        }
        peripheral.discoverCharacteristics(
            [toRadioCharUUID, fromRadioCharUUID],
            for: service
        )
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        service.characteristics?.forEach { char in
            if char.uuid == toRadioCharUUID {
                DispatchQueue.main.async { [weak self] in
                    self?.toRadioChar = char
                }
            }
            if char.uuid == fromRadioCharUUID {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value, characteristic.uuid == fromRadioCharUUID else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleIncomingPacket(data)
        }
    }
}
