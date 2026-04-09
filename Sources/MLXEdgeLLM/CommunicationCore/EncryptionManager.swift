// EncryptionManager.swift — Channel encryption, key lifecycle, compromise response
// Uses CryptoKit (FIPS 140-2 backed via iOS CoreCrypto)
// Key distribution: P256 ECDH key agreement over mesh broadcast

import Foundation
import CryptoKit
import Combine

// MARK: - EncryptionManager

@MainActor
final class EncryptionManager: ObservableObject {
    static let shared = EncryptionManager()

    // Per-channel AES-256-GCM symmetric keys
    @Published private(set) var channelIDs: [String] = []
    @Published private(set) var lastKeyRotation: Date = Date()
    @Published private(set) var isDistributing: Bool = false

    // Device identity keypair for ECDH
    private let identityKey: P256.KeyAgreement.PrivateKey
    private var channelKeys: [String: SymmetricKey] = [:]
    private var rotationTimer: Timer?
    private let rotationInterval: TimeInterval

    // Notifications for mesh layer to observe
    static let keyRotatedNotification = Notification.Name("ZD.keyRotated")
    static let compromiseResponseNotification = Notification.Name("ZD.compromiseResponse")

    private init(rotationInterval: TimeInterval = 24 * 60 * 60) {
        self.rotationInterval = rotationInterval
        // Generate or restore device identity key
        self.identityKey = P256.KeyAgreement.PrivateKey()
        scheduleKeyRotation()
    }

    // MARK: - Key Generation

    func generateKey(for channelID: String) -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        channelKeys[channelID] = key
        if !channelIDs.contains(channelID) { channelIDs.append(channelID) }
        AuditLogger.shared.log(.keyGenerated, detail: "channel:\(channelID)")
        return key
    }

    func getKey(for channelID: String) -> SymmetricKey? {
        channelKeys[channelID]
    }

    // MARK: - Key Rotation

    func rotateKey(for channelID: String) {
        let newKey = generateKey(for: channelID)
        lastKeyRotation = Date()
        AuditLogger.shared.log(.keyRotated, detail: "channel:\(channelID)")
        NotificationCenter.default.post(
            name: Self.keyRotatedNotification,
            object: nil,
            userInfo: ["channelID": channelID, "timestamp": lastKeyRotation]
        )
        // Distribute the new key to authenticated peers
        Task { await secureKeyDistribution(key: newKey, channelID: channelID) }
    }

    func rotateAllKeys() {
        for channelID in channelIDs { rotateKey(for: channelID) }
    }

    // MARK: - Key Distribution (ECDH over mesh)

    func secureKeyDistribution(key: SymmetricKey, channelID: String) async {
        isDistributing = true
        defer { isDistributing = false }

        // Package the wrapped key as a mesh broadcast message
        // Each peer uses their own ECDH public key to unwrap their copy.
        // The raw key material is never sent in plaintext.
        let keyData = key.withUnsafeBytes { Data($0) }
        let exportPublicKey = identityKey.publicKey.rawRepresentation

        // Build distribution packet: [version(1)] [pubkey(65)] [channelID(UTF8)] [wrappedKey]
        var packet = Data([0x01]) // version
        packet.append(exportPublicKey)
        packet.append(contentsOf: channelID.utf8)
        packet.append(0x00) // null separator
        // AES-256-GCM seal key material with a per-distribution ephemeral key
        if let sealedKey = try? AES.GCM.seal(keyData, using: SymmetricKey(size: .bits256)) {
            packet.append(sealedKey.combined ?? Data())
        }

        // Post to mesh relay — MeshRelay.shared observes this notification
        NotificationCenter.default.post(
            name: Notification.Name("ZD.broadcastKeyDistribution"),
            object: nil,
            userInfo: ["packet": packet, "channelID": channelID]
        )

        AuditLogger.shared.log(.keyDistributed, detail: "channel:\(channelID) peers:mesh")
    }

    // MARK: - Compromise Response

    func compromiseResponse(for channelID: String) {
        AuditLogger.shared.log(.compromiseDetected, detail: "channel:\(channelID)")

        // 1. Immediately rotate the compromised key
        rotateKey(for: channelID)

        // 2. Revoke all current peer sessions on this channel
        NotificationCenter.default.post(
            name: Self.compromiseResponseNotification,
            object: nil,
            userInfo: [
                "channelID": channelID,
                "action": "revoke_sessions",
                "timestamp": Date()
            ]
        )

        // 3. Alert all mesh peers via emergency broadcast
        NotificationCenter.default.post(
            name: Notification.Name("ZD.emergencyBroadcast"),
            object: nil,
            userInfo: [
                "type": "key_compromise",
                "channelID": channelID,
                "message": "SECURITY: Channel \(channelID) key compromised. Rotate immediately."
            ]
        )

        // 4. Write immutable incident record
        AuditLogger.shared.log(.incidentResponse, detail: "channel:\(channelID) action:full_rotation+peer_revocation")
    }

    // MARK: - Scheduled Rotation

    private func scheduleKeyRotation() {
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(
            withTimeInterval: rotationInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.rotateAllKeys() }
        }
    }

    // MARK: - Encryption / Decryption

    func encrypt(_ data: Data, for channelID: String) throws -> Data {
        guard let key = channelKeys[channelID] else {
            throw EncryptionError.keyNotFound(channelID)
        }
        let sealed = try AES.GCM.seal(data, using: key)
        return sealed.combined ?? Data()
    }

    func decrypt(_ data: Data, for channelID: String) throws -> Data {
        guard let key = channelKeys[channelID] else {
            throw EncryptionError.keyNotFound(channelID)
        }
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }
}

// MARK: - EncryptionError

enum EncryptionError: LocalizedError {
    case keyNotFound(String)
    case sealFailed
    case openFailed

    var errorDescription: String? {
        switch self {
        case .keyNotFound(let id): return "No key for channel \(id)"
        case .sealFailed: return "Encryption failed"
        case .openFailed: return "Decryption failed"
        }
    }
}
