import Foundation
import SwiftUI
import CryptoKit

// MARK: - E2eMessaging

class E2eMessaging: ObservableObject {
    @Published var messages: [EncryptedMessage] = []
    private let keyPair: KeyPair
    private let session: Session

    init() {
        self.keyPair = KeyPair()
        self.session = Session(keyPair: keyPair)
    }

    func sendMessage(to recipient: String, content: String) async throws {
        let encryptedMessage = try await session.encrypt(content: content, for: recipient)
        messages.append(encryptedMessage)
    }

    func receiveMessage(_ message: EncryptedMessage) async throws -> String {
        return try await session.decrypt(message: message)
    }
}

// MARK: - KeyPair

struct KeyPair {
    let privateKey: P256.PrivateKey
    let publicKey: P256.PublicKey

    init() {
        let privateKey = P256.PrivateKey()
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey
    }
}

// MARK: - Session

actor Session {
    let keyPair: KeyPair
    private var sharedKeys: [String: SymmetricKey] = [:]

    init(keyPair: KeyPair) {
        self.keyPair = keyPair
    }

    func encrypt(content: String, for recipient: String) async throws -> EncryptedMessage {
        let sharedKey = try await deriveSharedKey(for: recipient)
        let sealedBox = try ChaChaPoly.seal(content.data(using: .utf8)!, using: sharedKey)
        return EncryptedMessage(recipient: recipient, ciphertext: sealedBox.ciphertext, nonce: sealedBox.nonce)
    }

    func decrypt(message: EncryptedMessage) async throws -> String {
        let sharedKey = try await deriveSharedKey(for: message.recipient)
        let sealedBox = try ChaChaPoly.SealedBox(combined: message.ciphertext + message.nonce)
        let decryptedData = try ChaChaPoly.open(sealedBox, using: sharedKey)
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }

    private func deriveSharedKey(for recipient: String) async throws -> SymmetricKey {
        if let sharedKey = sharedKeys[recipient] {
            return sharedKey
        }

        // Placeholder for actual key derivation logic
        let sharedKey = SymmetricKey(size: .init(bitCount: 256))
        sharedKeys[recipient] = sharedKey
        return sharedKey
    }
}

// MARK: - EncryptedMessage

struct EncryptedMessage: Identifiable {
    let id = UUID()
    let recipient: String
    let ciphertext: Data
    let nonce: Data
}