// MeshRelay.swift — Unified TAK/Meshtastic/Mesh relay with OpSec geofence deny-list
// Bridges CoT events and Meshtastic nodes through mesh with geofence enforcement
// BUILD_SPEC v6.2: MeshRelay protobuf TAK parser + OpSec geofence deny

import Foundation
import CoreLocation
import Combine

@MainActor
final class MeshRelay: ObservableObject {
    static let shared = MeshRelay()

    // MARK: - Published State

    @Published var relayedPeers: [ZDPeer] = []
    @Published var deniedPeerIDs: Set<String> = []
    @Published var relayCount: Int = 0
    @Published var isRunning = false

    // MARK: - Dependencies

    private let mesh = MeshService.shared
    private let geofenceManager = GeofenceManager.shared
    private let meshtastic = MeshtasticBridge.shared
    private let cotDecoder = CoTDecoder.shared
    private let cotEncoder = CoTEncoder.shared
    private let activity = ActivityFeed.shared

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Subscribe to Meshtastic node updates and route through OpSec
        meshtastic.$meshNodes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nodes in
                self?.handleMeshtasticNodes(nodes)
            }
            .store(in: &cancellables)

        // Subscribe to incoming mesh intel messages for CoT relay
        mesh.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.handleIntelMessages(messages)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        isRunning = false
    }

    // MARK: - Meshtastic Node Relay

    private func handleMeshtasticNodes(_ nodes: [MeshtasticNode]) {
        for node in nodes {
            let peer = meshtasticNodeToPeer(node)

            if opSecCheck(peer: peer) {
                // Allowed — forward to MeshService
                mesh.updatePeerFromMeshtastic(node)
                deniedPeerIDs.remove(peer.id)

                if !relayedPeers.contains(where: { $0.id == peer.id }) {
                    relayedPeers.append(peer)
                } else if let idx = relayedPeers.firstIndex(where: { $0.id == peer.id }) {
                    relayedPeers[idx] = peer
                }
            } else {
                // Denied by geofence
                deniedPeerIDs.insert(peer.id)
                relayedPeers.removeAll { $0.id == peer.id }
                activity.log(.geofenceDeny, message: "Denied relay: \(peer.name) (out-of-zone)")
            }
        }
    }

    private func meshtasticNodeToPeer(_ node: MeshtasticNode) -> ZDPeer {
        ZDPeer(
            id: node.id,
            name: node.longName.isEmpty ? node.shortName : node.longName,
            lastSeen: node.lastSeen,
            location: node.coordinate,
            batteryLevel: node.batteryLevel ?? 0,
            status: .online
        )
    }

    // MARK: - Intel Message Relay (CoT detection)

    private var lastProcessedMessageCount = 0

    private func handleIntelMessages(_ messages: [MeshService.DecryptedMessage]) {
        // Only process new messages
        guard messages.count > lastProcessedMessageCount else { return }
        let newMessages = messages.suffix(from: lastProcessedMessageCount)
        lastProcessedMessageCount = messages.count

        for msg in newMessages where msg.type == .intel {
            // Try to parse as CoT XML
            if let data = msg.content.replacingOccurrences(of: "INTEL: ", with: "").data(using: .utf8),
               let peer = parseTAKCoT(data) {
                if opSecCheck(peer: peer) {
                    if let idx = relayedPeers.firstIndex(where: { $0.id == peer.id }) {
                        relayedPeers[idx] = peer
                    } else {
                        relayedPeers.append(peer)
                    }
                    relayCount += 1
                    activity.log(.cotRelayed, message: "CoT relay: \(peer.name)")
                } else {
                    deniedPeerIDs.insert(peer.id)
                    activity.log(.geofenceDeny, message: "Denied CoT relay: \(peer.name)")
                }
            }
        }
    }

    // MARK: - Protobuf Parsing

    /// Parse raw protobuf position data into ZDPeer array
    func parseProtobuf(_ data: Data) -> [ZDPeer]? {
        let bytes = [UInt8](data)
        var peers: [ZDPeer] = []
        var offset = 0

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen

            if fieldTag == 3 && wireType == 2 {
                // MeshPacket (length-delimited)
                guard let (length, lenBytes) = pbReadVarint(bytes, offset: offset) else { break }
                offset += lenBytes
                let packetEnd = min(offset + Int(length), bytes.count)
                let packetBytes = Array(bytes[offset..<packetEnd])
                offset = packetEnd

                if let peer = parseMeshPacketToPeer(packetBytes) {
                    peers.append(peer)
                }
            } else {
                // Skip unknown fields
                if let skip = pbSkipField(bytes, offset: offset, wireType: wireType) {
                    offset += skip
                } else {
                    break
                }
            }
        }

        return peers.isEmpty ? nil : peers
    }

    private func parseMeshPacketToPeer(_ bytes: [UInt8]) -> ZDPeer? {
        var nodeId: UInt32 = 0
        var lat: Double = 0
        var lon: Double = 0
        var offset = 0

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (1, 0): // from (node ID)
                if let (v, n) = pbReadVarint(bytes, offset: offset) {
                    nodeId = UInt32(v & 0xFFFFFFFF)
                    offset += n
                }
            case (6, 2): // decoded Data message
                if let (length, lenBytes) = pbReadVarint(bytes, offset: offset) {
                    offset += lenBytes
                    let dataBytes = Array(bytes[offset..<min(offset + Int(length), bytes.count)])
                    offset += Int(length)

                    // Parse position from data message
                    if let pos = parsePositionFromDataMessage(dataBytes) {
                        lat = pos.0
                        lon = pos.1
                    }
                }
            default:
                if let skip = pbSkipField(bytes, offset: offset, wireType: wireType) {
                    offset += skip
                } else { break }
            }
        }

        guard nodeId != 0 && (lat != 0 || lon != 0) else { return nil }

        let hexId = String(format: "%08x", nodeId)
        return ZDPeer(
            id: hexId,
            name: hexId.prefix(4).uppercased(),
            lastSeen: Date(),
            location: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            batteryLevel: nil,
            status: .online
        )
    }

    private func parsePositionFromDataMessage(_ bytes: [UInt8]) -> (Double, Double)? {
        var portnum: Int = 0
        var payload = Data()
        var offset = 0

        while offset < bytes.count {
            guard let (fieldTag, wireType, headerLen) = pbReadFieldHeader(bytes, offset: offset) else { break }
            offset += headerLen

            switch (fieldTag, wireType) {
            case (1, 0):
                if let (v, n) = pbReadVarint(bytes, offset: offset) { portnum = Int(v); offset += n }
            case (2, 2):
                if let (length, lenBytes) = pbReadVarint(bytes, offset: offset) {
                    offset += lenBytes
                    payload = Data(bytes[offset..<min(offset + Int(length), bytes.count)])
                    offset += Int(length)
                }
            default:
                if let skip = pbSkipField(bytes, offset: offset, wireType: wireType) {
                    offset += skip
                } else { break }
            }
        }

        guard portnum == 1 else { return nil } // POSITION_APP

        // Parse position fields
        let posBytes = [UInt8](payload)
        var lat: Int64 = 0; var lon: Int64 = 0
        var posOffset = 0
        while posOffset < posBytes.count {
            guard let (fieldTag, wireType, headerLen) = pbReadFieldHeader(posBytes, offset: posOffset) else { break }
            posOffset += headerLen
            if wireType == 0, let (v, n) = pbReadVarint(posBytes, offset: posOffset) {
                if fieldTag == 1 { lat = Int64(bitPattern: v) }
                else if fieldTag == 2 { lon = Int64(bitPattern: v) }
                posOffset += n
            } else { break }
        }

        guard lat != 0 || lon != 0 else { return nil }
        return (Double(lat) / 1e7, Double(lon) / 1e7)
    }

    // MARK: - TAK CoT Parsing

    /// Parse CoT XML data into a ZDPeer
    func parseTAKCoT(_ data: Data) -> ZDPeer? {
        guard let event = cotDecoder.decode(data) else { return nil }

        let callsign = event.detail?.contact?.callsign ?? event.uid
        let battery = event.detail?.status?.battery

        return ZDPeer(
            id: event.uid,
            name: callsign,
            lastSeen: event.time,
            location: CLLocationCoordinate2D(latitude: event.lat, longitude: event.lon),
            batteryLevel: battery,
            status: cotTypeToStatus(event.type)
        )
    }

    private func cotTypeToStatus(_ type: String) -> ZDPeer.PeerStatus {
        if type.contains("b-a-o-tbl-sos") { return .sos }
        if type.hasPrefix("a-f") { return .online }
        if type.hasPrefix("a-h") { return .online }
        return .online
    }

    // MARK: - OpSec Geofence Check

    /// Returns true if the peer is allowed (inside all keep-in, outside all keep-out zones)
    /// Returns true if no geofences are active (permissive default when unconfigured)
    func opSecCheck(peer: ZDPeer) -> Bool {
        // No geofences configured — allow all
        guard !geofenceManager.geofences.isEmpty else { return true }

        return geofenceManager.shouldAllowRelay(to: peer.location)
    }

    // MARK: - CoT → Protobuf Encoding

    /// Convert a CoTEvent to lightweight protobuf for bandwidth-efficient mesh relay
    func cotToProtobuf(_ event: CoTEvent) -> Data {
        var payload = Data()

        // Field 1: uid (string)
        payload.append(contentsOf: pbEncodeStringField(tag: 1, value: event.uid))

        // Field 2: lat (as scaled int32 * 1e7)
        let latI = Int32(event.lat * 1e7)
        payload.append(contentsOf: pbEncodeVarintField(tag: 2, value: UInt64(bitPattern: Int64(latI))))

        // Field 3: lon (as scaled int32 * 1e7)
        let lonI = Int32(event.lon * 1e7)
        payload.append(contentsOf: pbEncodeVarintField(tag: 3, value: UInt64(bitPattern: Int64(lonI))))

        // Field 4: type (string)
        payload.append(contentsOf: pbEncodeStringField(tag: 4, value: event.type))

        // Field 5: callsign (string, if available)
        if let callsign = event.detail?.contact?.callsign {
            payload.append(contentsOf: pbEncodeStringField(tag: 5, value: callsign))
        }

        // Field 6: battery (varint, if available)
        if let battery = event.detail?.status?.battery {
            payload.append(contentsOf: pbEncodeVarintField(tag: 6, value: UInt64(battery)))
        }

        // Field 7: stale time (seconds from epoch)
        payload.append(contentsOf: pbEncodeVarintField(tag: 7, value: UInt64(event.stale.timeIntervalSince1970)))

        return payload
    }

    // MARK: - Relay to Mesh

    /// Relay a CoT event through the mesh (as protobuf, encrypted by MeshService)
    func relayToMesh(_ event: CoTEvent) {
        let protobufData = cotToProtobuf(event)
        let base64 = protobufData.base64EncodedString()

        // Send as intel message with protobuf prefix for identification
        mesh.shareIntel("PB:\(base64)")
        relayCount += 1
        activity.log(.cotRelayed, message: "Relayed CoT: \(event.detail?.contact?.callsign ?? event.uid)")
    }

    // MARK: - Stats

    struct RelayStats {
        var totalRelayed: Int = 0
        var totalDenied: Int = 0
        var activePeers: Int = 0
    }

    var stats: RelayStats {
        RelayStats(
            totalRelayed: relayCount,
            totalDenied: deniedPeerIDs.count,
            activePeers: relayedPeers.count
        )
    }
}
