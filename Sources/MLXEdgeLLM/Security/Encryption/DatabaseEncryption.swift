import Foundation
import CryptoKit
import SQLite

// MARK: - Database Encryption

class DatabaseEncryption {
    private let keychainService = KeychainService()
    private let databasePath: String
    private let encryptionKey: SymmetricKey

    init(databasePath: String) throws {
        self.databasePath = databasePath
        self.encryptionKey = try keychainService.loadEncryptionKey()
    }

    func encryptDatabase() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: databasePath))
        let encryptedData = try encrypt(data: data)
        try encryptedData.write(to: URL(fileURLWithPath: databasePath))
    }

    func decryptDatabase() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: databasePath))
        let decryptedData = try decrypt(data: data)
        try decryptedData.write(to: URL(fileURLWithPath: databasePath))
    }

    private func encrypt(data: Data) throws -> Data {
        let sealedBox = try ChaChaPoly.seal(data, using: encryptionKey)
        return sealedBox.ciphertext + sealedBox.tag
    }

    private func decrypt(data: Data) throws -> Data {
        let sealedBox = try ChaChaPoly.SealedBox(combining: data[0..<32], authenticationTag: data[32..<64])
        return try ChaChaPoly.open(sealedBox, using: encryptionKey)
    }
}

// MARK: - Keychain Service

class KeychainService {
    private let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrKeyType as String: kSecAttrKeyTypeEC,
        kSecAttrKeySizeInBits as String: 256,
        kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        kSecAttrIsPermanent as String: true
    ]

    func loadEncryptionKey() throws -> SymmetricKey {
        let keychainQuery = keychainQuery.merging([
            kSecAttrLabel as String: "ZeroDarkEncryptionKey"
        ]) { (_, new) in new }

        var item: AnyObject?
        let status = SecItemCopyMatching(keychainQuery as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw KeychainError.unableToLoadKey
        }

        guard let keyData = item as? Data else {
            throw KeychainError.unableToLoadKey
        }

        return SymmetricKey(data: keyData)
    }

    func saveEncryptionKey(_ key: SymmetricKey) throws {
        let keychainQuery = keychainQuery.merging([
            kSecAttrLabel as String: "ZeroDarkEncryptionKey",
            kSecValueData as String: key.data
        ]) { (_, new) in new }

        let status = SecItemAdd(keychainQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSaveKey
        }
    }
}

enum KeychainError: Error {
    case unableToLoadKey
    case unableToSaveKey
}