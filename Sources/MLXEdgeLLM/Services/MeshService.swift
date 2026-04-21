// MeshService.swift — Real Mesh Networking via MultipeerKit + AES-GCM Encryption

import Foundation
import MultipeerKit
import CryptoSwift
import Combine
import CoreLocation

// MeshtasticNode defined in MeshtasticBridge.swift
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Message Types

enum ZDMessageType: String, Codable {
    case text
    case location
    case sos
    case intel
    case ping
    case acknowledgment
    case audioChunk
    case haptic
    case dtn
    case scanOverlay
    case checkIn
}

struct ZDMeshMessage: Codable {
    let id: UUID
    let type: ZDMessageType
    let senderId: String
    let senderName: String
    let timestamp: Date
    let payload: Data  // AES-GCM encrypted
    let iv: Data       // Initialization vector
    let tag: Data      // Authentication tag
}

struct ZDPeer: Identifiable, Hashable {
    let id: String
    let name: String
    var lastSeen: Date
    var location: CLLocationCoordinate2D?
    var batteryLevel: Int?
    var status: PeerStatus
    
    enum PeerStatus: String, Codable {
        case online
        case away
        case sos
        case offline
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ZDPeer, rhs: ZDPeer) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Mesh Service

@MainActor
final class MeshService: ObservableObject {
    static let shared = MeshService()
    
    // MARK: Published State
    @Published var isActive = false
    @Published var peers: [ZDPeer] = []
    @Published var messages: [DecryptedMessage] = []
    @Published var sosActive = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isRemembered: Bool = false
    @Published var trustedDevices: [MeshKeychain.TrustedDevice] = []
    
    enum ConnectionStatus {
        case disconnected
        case scanning
        case connected(peerCount: Int)
    }
    
    struct DecryptedMessage: Identifiable {
        let id: UUID
        let type: ZDMessageType
        let senderId: String
        let senderName: String
        let timestamp: Date
        let content: String
    }
    
    // MARK: Private
    private var transceiver: MultipeerTransceiver?
    private var encryptionKey: [UInt8]?
    private var cancellables = Set<AnyCancellable>()
    private let keychain = MeshKeychain.shared
    #if canImport(UIKit)
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    private let deviceName = UIDevice.current.name
    #else
    private let deviceId = UUID().uuidString
    private let deviceName = Host.current().localizedName ?? "Mac"
    #endif
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func start(groupKey: String) {
        // Derive 256-bit key from group passphrase
        encryptionKey = deriveKey(from: groupKey)
        
        // Configure MultipeerKit
        var config = MultipeerConfiguration.default
        config.serviceType = "zerodark-mesh" // Max 15 chars, lowercase + hyphens
        config.peerName = deviceName
        config.security = .default
        
        transceiver = MultipeerTransceiver(configuration: config)
        
        // Setup handlers
        setupHandlers()
        
        // Resume (start advertising + browsing)
        transceiver?.resume()
        isActive = true
        connectionStatus = .scanning
        
        // Start peer keepalive
        startKeepalive()
    }
    
    func stop() {
        transceiver?.stop()
        transceiver = nil
        isActive = false
        peers.removeAll()
        connectionStatus = .disconnected
    }

    // MARK: - Persistence

    /// Start mesh with saved credentials (auto-connect)
    func autoStart() {
        guard keychain.autoConnectEnabled,
              let passphrase = keychain.getPassphrase() else {
            return
        }

        start(groupKey: passphrase)
        isRemembered = true
        loadTrustedDevices()
    }

    /// Save current passphrase for auto-connect
    func rememberNetwork(passphrase: String) {
        keychain.savePassphrase(passphrase)
        keychain.autoConnectEnabled = true
        isRemembered = true
    }

    /// Forget saved network
    func forgetNetwork() {
        keychain.deletePassphrase()
        keychain.autoConnectEnabled = false
        isRemembered = false
        stop()
    }

    /// Check if we have saved credentials
    var hasSavedNetwork: Bool {
        keychain.hasPassphrase
    }

    // MARK: - Trusted Devices

    /// Load trusted devices from storage
    func loadTrustedDevices() {
        trustedDevices = keychain.getTrustedDevices()
    }

    /// Trust a peer (add to trusted list)
    func trustPeer(_ peer: ZDPeer, nickname: String? = nil) {
        let name = nickname ?? peer.name
        keychain.trustDevice(id: peer.id, nickname: name)
        loadTrustedDevices()
    }

    /// Remove peer from trusted list
    func untrustPeer(id: String) {
        keychain.removeTrustedDevice(id: id)
        loadTrustedDevices()
    }

    /// Get display name for peer (nickname if trusted, otherwise device name)
    func displayName(for peer: ZDPeer) -> String {
        keychain.nickname(for: peer.id) ?? peer.name
    }

    /// Update lastSeen for trusted device when we see them
    private func updateTrustedDeviceLastSeen(id: String) {
        var devices = keychain.getTrustedDevices()
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].lastSeen = Date()
            keychain.saveTrustedDevices(devices)
        }
    }

    // MARK: - Handlers
    
    private func setupHandlers() {
        guard let transceiver else { return }
        
        // Peer discovery
        transceiver.peerAdded = { [weak self] peer in
            Task { @MainActor in
                guard let self else { return }
                let newPeer = ZDPeer(
                    id: peer.id, // Unique hash of MCPeerID
                    name: peer.name,
                    lastSeen: Date(),
                    location: nil,
                    batteryLevel: nil,
                    status: .online
                )
                if !self.peers.contains(where: { $0.id == newPeer.id }) {
                    self.peers.append(newPeer)
                }
                if self.keychain.isDeviceTrusted(id: newPeer.id) {
                    self.updateTrustedDeviceLastSeen(id: newPeer.id)
                }
                self.updateConnectionStatus()
            }
        }
        
        transceiver.peerRemoved = { [weak self] peer in
            Task { @MainActor in
                guard let self else { return }
                self.peers.removeAll { $0.id == peer.id }
                self.updateConnectionStatus()
            }
        }
        
        // Message reception
        transceiver.receive(ZDMeshMessage.self) { [weak self] message, peer in
            Task { @MainActor in
                self?.handleMessage(message, from: peer)
            }
        }
    }
    
    private func handleMessage(_ message: ZDMeshMessage, from peer: MultipeerKit.Peer) {
        // Decrypt payload
        guard let key = encryptionKey,
              let decrypted = decrypt(data: message.payload, iv: message.iv, tag: message.tag, key: key) else {
            return
        }
        
        // Parse based on type
        switch message.type {
        case .text:
            if let text = String(data: decrypted, encoding: .utf8) {
                let msg = DecryptedMessage(
                    id: message.id,
                    type: .text,
                    senderId: message.senderId,
                    senderName: message.senderName,
                    timestamp: message.timestamp,
                    content: text
                )
                messages.append(msg)
            }
            
        case .location:
            if let locationData = try? JSONDecoder().decode(LocationPayload.self, from: decrypted) {
                updatePeerLocation(peerId: message.senderId, location: locationData)
            }
            
        case .sos:
            handleSOSReceived(from: message.senderName, senderId: message.senderId)
            
        case .intel:
            if let intelText = String(data: decrypted, encoding: .utf8) {
                let msg = DecryptedMessage(
                    id: message.id,
                    type: .intel,
                    senderId: message.senderId,
                    senderName: message.senderName,
                    timestamp: message.timestamp,
                    content: "INTEL: \(intelText)"
                )
                messages.append(msg)
            }
            
        case .ping:
            // Update peer lastSeen
            if let index = peers.firstIndex(where: { $0.id == message.senderId }) {
                peers[index].lastSeen = Date()
            }
            
        case .acknowledgment:
            break

        case .audioChunk:
            // Decrypt audio data and forward to PTT controller
            PTTController.shared.receiveAudio(data: decrypted, fromPeer: message.senderName)

        case .haptic:
            if let codeStr = String(data: decrypted, encoding: .utf8),
               let code = TacticalHapticCode(rawValue: codeStr) {
                HapticComms.shared.receive(code, from: message.senderName)
                messages.append(DecryptedMessage(
                    id: message.id,
                    type: .haptic,
                    senderId: message.senderId,
                    senderName: message.senderName,
                    timestamp: message.timestamp,
                    content: "HAPTIC: \(code.displayName)"
                ))
            }

        case .scanOverlay:
            ScanOverlayStore.shared.applyIncoming(decrypted)

        case .checkIn:
            // Post raw decrypted bytes; CheckInSystem decodes the CheckInMeshPayload.
            NotificationCenter.default.post(
                name: Notification.Name("ZD.checkInReceived"),
                object: nil,
                userInfo: [
                    "data": decrypted,
                    "senderId": message.senderId,
                    "senderName": message.senderName
                ]
            )

        @unknown default:
            break
        }
    }

    // MARK: - Sending
    
    func sendText(_ text: String) {
        guard let encrypted = encryptPayload(Data(text.utf8)) else { return }
        
        let message = ZDMeshMessage(
            id: UUID(),
            type: .text,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )
        
        transceiver?.broadcast(message)
        
        // Add to local messages
        messages.append(DecryptedMessage(
            id: message.id,
            type: .text,
            senderId: deviceId,
            senderName: "You",
            timestamp: Date(),
            content: text
        ))
    }
    
    func shareLocation(_ coordinate: CLLocationCoordinate2D) {
        let payload = LocationPayload(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let data = try? JSONEncoder().encode(payload),
              let encrypted = encryptPayload(data) else { return }
        
        let message = ZDMeshMessage(
            id: UUID(),
            type: .location,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )
        
        transceiver?.broadcast(message)
    }
    
    func broadcastSOS() {
        sosActive = true
        
        guard let encrypted = encryptPayload(Data("SOS".utf8)) else { return }
        
        let message = ZDMeshMessage(
            id: UUID(),
            type: .sos,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )
        
        // Broadcast repeatedly
        for _ in 0..<3 {
            transceiver?.broadcast(message)
        }
        
        // Trigger haptic
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
    
    func cancelSOS() {
        sosActive = false
    }
    
    func shareIntel(_ intel: String) {
        guard let encrypted = encryptPayload(Data(intel.utf8)) else { return }

        let message = ZDMeshMessage(
            id: UUID(),
            type: .intel,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )

        transceiver?.broadcast(message)
    }

    func broadcastText(_ text: String) {
        shareIntel(text)
    }

    func broadcastAudio(data: Data, callsign: String) {
        // Encrypt audio data with callsign prefix
        var audioPayload = Data(callsign.utf8)
        audioPayload.append(data)

        guard let encrypted = encryptPayload(audioPayload) else { return }

        let message = ZDMeshMessage(
            id: UUID(),
            type: .audioChunk,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )

        transceiver?.broadcast(message)
    }

    /// Broadcast binary data (DTN bundles, AAR reports, etc.) over mesh
    func broadcastData(_ data: Data, type: ZDMessageType = .dtn) {
        guard let encrypted = encryptPayload(data) else { return }

        let message = ZDMeshMessage(
            id: UUID(),
            type: type,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )

        transceiver?.broadcast(message)
    }

    /// Send binary data to a specific peer (broadcasts with destination header)
    func sendData(_ data: Data, to peerID: String, type: ZDMessageType = .dtn) -> Bool {
        guard peers.contains(where: { $0.id == peerID }) else { return false }

        // Prefix payload with destination ID for targeted filtering on receive
        var targeted = Data(peerID.utf8.prefix(40))
        targeted.append(UInt8(0)) // null separator
        targeted.append(data)

        guard let encrypted = encryptPayload(targeted) else { return false }

        let message = ZDMeshMessage(
            id: UUID(),
            type: type,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )

        transceiver?.broadcast(message)
        return true
    }

    func sendHapticCode(_ code: TacticalHapticCode) {
        guard let encrypted = encryptPayload(Data(code.rawValue.utf8)) else { return }

        let message = ZDMeshMessage(
            id: UUID(),
            type: .haptic,
            senderId: deviceId,
            senderName: deviceName,
            timestamp: Date(),
            payload: encrypted.ciphertext,
            iv: encrypted.iv,
            tag: encrypted.tag
        )

        transceiver?.broadcast(message)

        // Add to local messages
        messages.append(DecryptedMessage(
            id: message.id,
            type: .haptic,
            senderId: deviceId,
            senderName: "You",
            timestamp: Date(),
            content: "HAPTIC: \(code.displayName)"
        ))
    }

    // MARK: - Encryption (AES-256-GCM)
    
    private struct EncryptedPayload {
        let ciphertext: Data
        let iv: Data
        let tag: Data
    }
    
    private func deriveKey(from passphrase: String) -> [UInt8]? {
        // PBKDF2 key derivation — no fallback; refuse to encrypt with weak key
        let salt = "ZeroDarkMesh2026".bytes
        do {
            return try PKCS5.PBKDF2(
                password: Array(passphrase.utf8),
                salt: salt,
                iterations: 10000,
                keyLength: 32,
                variant: .sha2(.sha256)
            ).calculate()
        } catch {
            assertionFailure("PBKDF2 key derivation failed: \(error)")
            return nil
        }
    }
    
    private func encryptPayload(_ data: Data) -> EncryptedPayload? {
        guard let key = encryptionKey else { return nil }
        
        do {
            let iv = AES.randomIV(12) // 96-bit IV for GCM
            let gcm = GCM(iv: iv, mode: .combined)
            let aes = try AES(key: key, blockMode: gcm, padding: .noPadding)
            let dataBytes = Array(data)
            let encrypted = try aes.encrypt(dataBytes)
            
            // GCM appends 16-byte tag to ciphertext
            let ciphertext = Array(encrypted.dropLast(16))
            let tag = Array(encrypted.suffix(16))
            
            return EncryptedPayload(
                ciphertext: Data(ciphertext),
                iv: Data(iv),
                tag: Data(tag)
            )
        } catch {
            return nil
        }
    }
    
    private func decrypt(data: Data, iv: Data, tag: Data, key: [UInt8]) -> Data? {
        do {
            let ivBytes = Array(iv)
            let tagBytes = Array(tag)
            let gcm = GCM(iv: ivBytes, authenticationTag: tagBytes, mode: .combined)
            let aes = try AES(key: key, blockMode: gcm, padding: .noPadding)
            let dataBytes = Array(data)
            let decrypted = try aes.decrypt(dataBytes)
            return Data(decrypted)
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private struct LocationPayload: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    private func updatePeerLocation(peerId: String, location: LocationPayload) {
        if let index = peers.firstIndex(where: { $0.id == peerId }) {
            peers[index].location = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
            peers[index].lastSeen = Date()
        }
    }

    /// Update or insert peer from Meshtastic node
    func updatePeerFromMeshtastic(_ node: MeshtasticNode) {
        let newPeer = ZDPeer(
            id: node.id,
            name: node.longName.isEmpty ? node.shortName : node.longName,
            lastSeen: node.lastSeen,
            location: node.coordinate,
            batteryLevel: node.batteryLevel ?? 0,
            status: .online
        )

        if let index = peers.firstIndex(where: { $0.id == newPeer.id }) {
            peers[index] = newPeer
        } else {
            peers.append(newPeer)
        }
    }

    private func handleSOSReceived(from name: String, senderId: String) {
        // Mark peer as SOS
        if let index = peers.firstIndex(where: { $0.id == senderId }) {
            peers[index].status = .sos
        }
        
        // Add to messages
        messages.append(DecryptedMessage(
            id: UUID(),
            type: .sos,
            senderId: senderId,
            senderName: name,
            timestamp: Date(),
            content: "EMERGENCY SOS FROM \(name.uppercased())"
        ))
        
        // Strong haptic
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }
    
    private func updateConnectionStatus() {
        let onlinePeers = peers.filter { $0.status != .offline }.count
        if onlinePeers > 0 {
            connectionStatus = .connected(peerCount: onlinePeers)
        } else if isActive {
            connectionStatus = .scanning
        } else {
            connectionStatus = .disconnected
        }
    }
    
    private func startKeepalive() {
        // Send ping every 30 seconds
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let encrypted = self.encryptPayload(Data("ping".utf8)) else { return }
                
                let message = ZDMeshMessage(
                    id: UUID(),
                    type: .ping,
                    senderId: self.deviceId,
                    senderName: self.deviceName,
                    timestamp: Date(),
                    payload: encrypted.ciphertext,
                    iv: encrypted.iv,
                    tag: encrypted.tag
                )
                
                self.transceiver?.broadcast(message)
                
                // Mark stale peers as offline
                let staleThreshold = Date().addingTimeInterval(-120) // 2 minutes
                for i in self.peers.indices {
                    if self.peers[i].lastSeen < staleThreshold {
                        self.peers[i].status = .offline
                    }
                }
                self.updateConnectionStatus()
            }
            .store(in: &cancellables)
    }
}
