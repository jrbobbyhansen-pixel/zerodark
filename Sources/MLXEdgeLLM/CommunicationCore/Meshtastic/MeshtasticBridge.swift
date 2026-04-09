// MeshtasticBridge.swift — BLE Bridge to Meshtastic LoRa Hardware
// Connects to Meshtastic devices and bridges positions/messages into mesh

@preconcurrency import CoreBluetooth
import CoreLocation
import Foundation

// MARK: - Inline Protobuf Helpers (avoids folder group discovery issues)

private func pbReadVarint(_ bytes: [UInt8], offset: Int) -> (UInt64, Int)? {
    var result: UInt64 = 0; var shift = 0; var i = offset
    while i < bytes.count {
        let byte = bytes[i]; i += 1
        result |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 { return (result, i - offset) }
        shift += 7; if shift >= 64 { return nil }
    }
    return nil
}

private func pbReadFieldHeader(_ bytes: [UInt8], offset: Int) -> (tag: Int, wireType: Int, headerLen: Int)? {
    guard let (v, n) = pbReadVarint(bytes, offset: offset) else { return nil }
    return (Int(v >> 3), Int(v & 0x07), n)
}

private func pbEncodeVarint(_ value: UInt64) -> Data {
    var data = Data(); var v = value
    repeat { var byte = UInt8(v & 0x7F); v >>= 7; if v != 0 { byte |= 0x80 }; data.append(byte) } while v != 0
    return data
}

private func pbEncodeVarintField(tag: Int, value: UInt64) -> Data {
    var data = Data()
    data.append(contentsOf: pbEncodeVarint(UInt64(tag << 3 | 0)))
    data.append(contentsOf: pbEncodeVarint(value))
    return data
}

private func pbEncodeBytesField(tag: Int, value: Data) -> Data {
    var data = Data()
    data.append(contentsOf: pbEncodeVarint(UInt64(tag << 3 | 2)))
    data.append(contentsOf: pbEncodeVarint(UInt64(value.count)))
    data.append(value)
    return data
}

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

// MARK: - Drone Telemetry (v6.1)

struct DroneTelemetry: Codable, Identifiable {
    let id: String  // drone node ID
    let latitude: Double
    let longitude: Double
    let altitudeAGL: Double
    let batteryPercent: Int
    let heading: Double
    let speed: Double
    let status: DroneStatus
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum DroneStatus: Int, Codable {
    case idle = 0, flying = 1, returning = 2, landing = 3, emergency = 4
}

enum DroneCommand {
    case goto(CLLocationCoordinate2D, altitude: Double)
    case returnToBase
    case hover
    case land
}

@MainActor
final class MeshtasticBridge: NSObject, ObservableObject {
    static let shared = MeshtasticBridge()

    @Published var isConnected = false
    @Published var isScanning = false
    @Published var connectedDevice: String? = nil
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var meshNodes: [MeshtasticNode] = []
    @Published var droneNodes: [DroneTelemetry] = []

    // Drone portnum (private app range in Meshtastic spec)
    private let dronePortnum: Int = 256

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
            guard offset >= 0,
                  let (fieldTag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset),
                  offset + headerLen <= bytes.count else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (3, 2): // fromRadio.packet = MeshPacket (length-delimited)
                guard offset < bytes.count,
                      let (length, lenBytes) = pbReadVarint(bytes, offset: offset),
                      offset + lenBytes + Int(length) <= bytes.count else { return }
                offset += lenBytes
                let packetBytes = Array(bytes[offset..<offset + Int(length)])
                offset += Int(length)
                parseMeshPacket(packetBytes)

            default:
                // Skip unknown fields
                if wireType == 2, let (length, lenBytes) = pbReadVarint(bytes, offset: offset),
                   offset + lenBytes + Int(length) <= bytes.count {
                    offset += lenBytes + Int(length)
                } else if wireType == 0, let (_, varBytes) = pbReadVarint(bytes, offset: offset),
                          offset + varBytes <= bytes.count {
                    offset += varBytes
                } else {
                    return  // Malformed data, stop parsing
                }
            }
        }
    }

    private func parseMeshPacket(_ bytes: [UInt8]) {
        var nodeId: UInt32 = 0
        var offset = 0

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset),
                  offset + headerLen <= bytes.count else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (1, 0): // from (node ID)
                guard let (v, n) = pbReadVarint(bytes, offset: offset),
                      offset + n <= bytes.count else { return }
                nodeId = UInt32(v & 0xFFFFFFFF)
                offset += n
            case (6, 2): // decoded Data message
                guard let (length, lenBytes) = pbReadVarint(bytes, offset: offset),
                      offset + lenBytes + Int(length) <= bytes.count else { return }
                offset += lenBytes
                let dataBytes = Array(bytes[offset..<offset + Int(length)])
                offset += Int(length)
                parseDataMessage(dataBytes, nodeId: nodeId)
            default:
                if wireType == 2, let (length, lenBytes) = pbReadVarint(bytes, offset: offset),
                   offset + lenBytes + Int(length) <= bytes.count {
                    offset += lenBytes + Int(length)
                } else if wireType == 0, let (_, n) = pbReadVarint(bytes, offset: offset),
                          offset + n <= bytes.count {
                    offset += n
                } else { return }
            }
        }
    }

    private func parseDataMessage(_ bytes: [UInt8], nodeId: UInt32) {
        var portnum: Int = 0
        var payload = Data()
        var offset = 0

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset),
                  offset + headerLen <= bytes.count else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (1, 0): // portnum
                guard let (v, n) = pbReadVarint(bytes, offset: offset),
                      offset + n <= bytes.count else { return }
                portnum = Int(v); offset += n
            case (2, 2): // payload
                guard let (length, lenBytes) = pbReadVarint(bytes, offset: offset),
                      offset + lenBytes + Int(length) <= bytes.count else { return }
                offset += lenBytes
                payload = Data(bytes[offset..<offset + Int(length)])
                offset += Int(length)
            default:
                if wireType == 2, let (length, lenBytes) = pbReadVarint(bytes, offset: offset),
                   offset + lenBytes + Int(length) <= bytes.count {
                    offset += lenBytes + Int(length)
                } else if wireType == 0, let (_, n) = pbReadVarint(bytes, offset: offset),
                          offset + n <= bytes.count {
                    offset += n
                } else { return }
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
                // MeshRelay subscribes to $meshNodes and applies OpSec
                // checks before forwarding to MeshService
            }
        } else if portnum == dronePortnum { // DRONE_TELEMETRY (v6.1)
            parseDroneTelemetry(payload, nodeId: nodeId)
        }
    }

    private func parsePosition(_ data: Data) -> (Double, Double)? {
        let bytes = [UInt8](data)
        var lat: Int64 = 0; var lon: Int64 = 0
        var offset = 0
        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen
            if wireType == 0, let (v, n) = pbReadVarint(bytes, offset: offset) {
                if fieldTag == 1 { lat = Int64(bitPattern: v) }
                else if fieldTag == 2 { lon = Int64(bitPattern: v) }
                offset += n
            } else { break }
        }
        guard lat != 0 || lon != 0 else { return nil }
        return (Double(lat) / 1e7, Double(lon) / 1e7)
    }

    // MARK: - Drone Telemetry (v6.1)

    private func parseDroneTelemetry(_ data: Data, nodeId: UInt32) {
        // Decode JSON telemetry from drone payload
        guard let telemetry = try? JSONDecoder().decode(DroneTelemetry.self, from: data) else {
            return
        }

        let hexId = String(format: "%08x", nodeId)
        let updated = DroneTelemetry(
            id: hexId,
            latitude: telemetry.latitude,
            longitude: telemetry.longitude,
            altitudeAGL: telemetry.altitudeAGL,
            batteryPercent: telemetry.batteryPercent,
            heading: telemetry.heading,
            speed: telemetry.speed,
            status: telemetry.status,
            timestamp: Date()
        )

        if let idx = droneNodes.firstIndex(where: { $0.id == hexId }) {
            droneNodes[idx] = updated
        } else {
            droneNodes.append(updated)
        }
    }

    /// Send a command to a drone via Meshtastic mesh
    func sendDroneCommand(_ command: DroneCommand) {
        guard let char = toRadioChar, let peripheral = connectedPeripheral else { return }

        let commandData: Data
        switch command {
        case .goto(let coord, let altitude):
            let payload: [String: Any] = [
                "cmd": "goto",
                "lat": coord.latitude,
                "lon": coord.longitude,
                "alt": altitude
            ]
            commandData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        case .returnToBase:
            commandData = "{\"cmd\":\"rtb\"}".data(using: .utf8) ?? Data()
        case .hover:
            commandData = "{\"cmd\":\"hover\"}".data(using: .utf8) ?? Data()
        case .land:
            commandData = "{\"cmd\":\"land\"}".data(using: .utf8) ?? Data()
        }

        // Encode as Meshtastic data message with drone portnum
        var decoded = Data()
        decoded.append(contentsOf: pbEncodeVarintField(tag: 1, value: UInt64(dronePortnum)))
        decoded.append(contentsOf: pbEncodeBytesField(tag: 2, value: commandData))
        let packet = pbEncodeBytesField(tag: 1, value: decoded)

        peripheral.writeValue(packet, for: char, type: .withResponse)
    }

    // MARK: - Meshtastic-Specific Protobuf Encoding (uses shared ProtobufHelpers)

    private func encodeMeshtasticPosition(lat: Double, lon: Double, callsign: String) -> Data {
        var posPayload = Data()
        let latI = Int32(lat * 1e7)
        let lonI = Int32(lon * 1e7)
        posPayload.append(contentsOf: pbEncodeVarintField(tag: 1, value: UInt64(bitPattern: Int64(latI))))
        posPayload.append(contentsOf: pbEncodeVarintField(tag: 2, value: UInt64(bitPattern: Int64(lonI))))
        return pbEncodeBytesField(tag: 1, value: posPayload)
    }

    private func encodeMeshtasticText(_ text: String) -> Data {
        guard let textData = text.data(using: .utf8) else { return Data() }
        var decoded = Data()
        decoded.append(contentsOf: pbEncodeVarintField(tag: 1, value: 1))
        decoded.append(contentsOf: pbEncodeBytesField(tag: 2, value: textData))
        return pbEncodeBytesField(tag: 1, value: decoded)
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
