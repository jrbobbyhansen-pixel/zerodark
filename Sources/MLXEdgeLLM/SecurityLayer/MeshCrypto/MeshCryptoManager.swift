// MeshCryptoManager.swift — Manages encryption for mesh communications (NASA CryptoLib pattern)

import Foundation
import CryptoKit

/// Manages encryption for mesh communications (NASA CryptoLib pattern)
public actor MeshCryptoManager {
    public static let shared = MeshCryptoManager()

    private let keyManager = SessionKeyManager.shared

    // Replay protection
    private var seenNonces: Set<Data> = []
    private let maxNonceAge: TimeInterval = 300  // 5 minutes
    private var nonceTimestamps: [Data: Date] = [:]

    private init() {}

    // MARK: - Encryption

    /// Encrypt data for transmission
    public func encrypt(_ plaintext: Data) async throws -> EncryptedMessage {
        let (key, keyID) = await keyManager.getCurrentKey()

        // Generate random nonce (12 bytes for AES-GCM)
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        let result = SecRandomCopyBytes(kSecRandomDefault, 12, &nonceBytes)
        guard result == errSecSuccess else {
            throw CryptoError.nonceGenerationFailed
        }
        let nonce = Data(nonceBytes)

        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: AES.GCM.Nonce(data: nonce)
        )

        return EncryptedMessage(
            keyID: keyID,
            nonce: nonce,
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    /// Encrypt data for a specific peer
    public func encrypt(_ plaintext: Data, for peerID: String) async throws -> EncryptedMessage {
        // For now, use same key. Could use peer-specific keys.
        return try await encrypt(plaintext)
    }

    // MARK: - Decryption

    /// Decrypt received message
    public func decrypt(_ message: EncryptedMessage) async throws -> Data {
        // Replay protection: check nonce
        guard !seenNonces.contains(message.nonce) else {
            throw CryptoError.replayDetected
        }

        // Check message age
        let age = Date().timeIntervalSince(message.timestamp)
        guard age < maxNonceAge && age > -60 else {  // Allow 60s clock skew
            throw CryptoError.messageExpired
        }

        // Get the key used for encryption
        guard let key = await keyManager.getKey(byID: message.keyID) else {
            throw CryptoError.unknownKey
        }

        // Reconstruct sealed box
        let nonce = try AES.GCM.Nonce(data: message.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: message.ciphertext,
            tag: message.tag
        )

        // Decrypt
        let plaintext = try AES.GCM.open(sealedBox, using: key)

        // Record nonce for replay protection
        seenNonces.insert(message.nonce)
        nonceTimestamps[message.nonce] = Date()

        // Prune old nonces
        await pruneOldNonces()

        return plaintext
    }

    // MARK: - Convenience Methods

    /// Encrypt a Codable message
    public func encrypt<T: Codable>(_ message: T) async throws -> EncryptedMessage {
        let data = try JSONEncoder().encode(message)
        return try await encrypt(data)
    }

    /// Decrypt to a Codable type
    public func decrypt<T: Codable>(_ message: EncryptedMessage, as type: T.Type) async throws -> T {
        let data = try await decrypt(message)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Maintenance

    /// Remove old nonces to prevent memory growth
    private func pruneOldNonces() async {
        let cutoff = Date().addingTimeInterval(-maxNonceAge)
        for (nonce, timestamp) in nonceTimestamps {
            if timestamp < cutoff {
                seenNonces.remove(nonce)
                nonceTimestamps.removeValue(forKey: nonce)
            }
        }
    }

    /// Rotate session key
    public func rotateKey() async {
        _ = await keyManager.rotateIfNeeded()
    }

    /// Clear all crypto state (security wipe)
    public func wipe() async {
        seenNonces.removeAll()
        nonceTimestamps.removeAll()
        _ = await keyManager.clearAllKeys()
    }
}

public enum CryptoError: Error {
    case nonceGenerationFailed
    case replayDetected
    case messageExpired
    case unknownKey
    case decryptionFailed
}
