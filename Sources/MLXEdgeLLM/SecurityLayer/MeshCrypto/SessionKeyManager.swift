// SessionKeyManager.swift — Manages session keys for mesh encryption (NASA CryptoLib pattern)

import Foundation
import CryptoKit

/// Manages session keys for mesh encryption (NASA CryptoLib pattern)
public actor SessionKeyManager {
    public static let shared = SessionKeyManager()

    // Current session key
    private var currentKey: SymmetricKey?
    private var currentKeyID: UUID?
    private var keyCreatedAt: Date?

    // Key rotation settings
    private let keyLifetime: TimeInterval = 3600  // 1 hour
    private let keySize = SymmetricKeySize.bits256

    // Stored peer keys for group communication
    private var peerKeys: [String: (key: SymmetricKey, id: UUID)] = [:]

    private init() {}

    /// Generate a new session key
    public func generateSessionKey() -> (key: SymmetricKey, id: UUID) {
        let key = SymmetricKey(size: keySize)
        let id = UUID()

        currentKey = key
        currentKeyID = id
        keyCreatedAt = Date()

        return (key, id)
    }

    /// Get current session key, generating if needed or expired
    public func getCurrentKey() -> (key: SymmetricKey, id: UUID) {
        // Check if key exists and is not expired
        if let key = currentKey,
           let id = currentKeyID,
           let created = keyCreatedAt,
           Date().timeIntervalSince(created) < keyLifetime {
            return (key, id)
        }

        // Generate new key
        return generateSessionKey()
    }

    /// Store a peer's session key (received during key exchange)
    public func storePeerKey(_ key: SymmetricKey, id: UUID, for peerID: String) {
        peerKeys[peerID] = (key, id)
    }

    /// Get a peer's key by ID
    public func getKey(byID keyID: UUID) -> SymmetricKey? {
        if currentKeyID == keyID {
            return currentKey
        }
        return peerKeys.values.first { $0.id == keyID }?.key
    }

    /// Get shared group key (for broadcast messages)
    public func getGroupKey() -> (key: SymmetricKey, id: UUID) {
        // For now, use current session key for group
        // In production, would use a separate group key establishment protocol
        return getCurrentKey()
    }

    /// Rotate key if needed
    public func rotateIfNeeded() -> Bool {
        guard let created = keyCreatedAt else {
            _ = generateSessionKey()
            return true
        }

        if Date().timeIntervalSince(created) >= keyLifetime {
            _ = generateSessionKey()
            return true
        }

        return false
    }

    /// Clear all keys (for security wipe)
    public func clearAllKeys() {
        currentKey = nil
        currentKeyID = nil
        keyCreatedAt = nil
        peerKeys.removeAll()
    }
}
