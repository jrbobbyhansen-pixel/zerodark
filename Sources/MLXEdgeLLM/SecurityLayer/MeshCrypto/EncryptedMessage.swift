// EncryptedMessage.swift — Encrypted message format (inspired by CCSDS SDLS)

import Foundation

/// Encrypted message format (inspired by CCSDS SDLS)
public struct EncryptedMessage: Codable {
    public let version: UInt8 = 1
    public let keyID: UUID              // Identifies which session key was used
    public let nonce: Data              // 12 bytes for AES-GCM
    public let ciphertext: Data         // Encrypted payload
    public let tag: Data                // 16 bytes authentication tag
    public let timestamp: Date          // For replay protection

    public init(keyID: UUID, nonce: Data, ciphertext: Data, tag: Data) {
        self.keyID = keyID
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
        self.timestamp = Date()
    }
}
