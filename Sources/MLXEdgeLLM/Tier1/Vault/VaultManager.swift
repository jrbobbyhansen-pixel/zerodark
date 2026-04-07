import Foundation
import CryptoKit
import Security

/// AES-256-GCM encrypted local vault. All ZeroDark data lives here.
/// Key stored in iOS Keychain — survives app restarts and OS updates,
/// scoped to this device only (kSecAttrAccessibleWhenUnlockedThisDeviceOnly).
final class VaultManager {
    static let shared = VaultManager()
    private let vaultURL: URL
    private let key: SymmetricKey

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        vaultURL = docs.appendingPathComponent("ZeroDarkVault")
        try? FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        key = VaultManager.loadOrCreateKey()
    }

    // MARK: - Key Management (Keychain)

    private static let keychainTag = "ai.zerodark.vault.key"

    private static func loadOrCreateKey() -> SymmetricKey {
        // Try to load existing key from Keychain
        if let existing = loadKeyFromKeychain() {
            return existing
        }
        // First run — generate a random 256-bit key and persist it
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        return newKey
    }

    private static func loadKeyFromKeychain() -> SymmetricKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainTag,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainTag,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: keyData
        ]
        // Delete any stale entry first, then add
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    // MARK: - Core Operations

    func save(data: Data, filename: String) throws {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw VaultError.encryptionFailed
        }
        try combined.write(to: vaultURL.appendingPathComponent(filename), options: .atomic)
    }

    func load(filename: String) throws -> Data {
        let url = vaultURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultError.fileNotFound(filename)
        }
        let combined = try Data(contentsOf: url)
        let sealed = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealed, using: key)
    }

    func saveJSON<T: Encodable>(_ value: T, filename: String) throws {
        let data = try JSONEncoder().encode(value)
        try save(data: data, filename: filename)
    }

    func loadJSON<T: Decodable>(_ type: T.Type, filename: String) throws -> T {
        let data = try load(filename: filename)
        return try JSONDecoder().decode(type, from: data)
    }

    func listFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: vaultURL.path)) ?? []
    }

    func delete(filename: String) throws {
        try FileManager.default.removeItem(at: vaultURL.appendingPathComponent(filename))
    }

    /// Decrypts to a temp file for ShareLink. Call cleanupExport(filename:) after sharing.
    func exportURL(filename: String) throws -> URL {
        let data = try load(filename: filename)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: tmp, options: .atomic)
        return tmp
    }

    func cleanupExport(filename: String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: tmp)
    }
}

enum VaultError: Error, LocalizedError {
    case encryptionFailed
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "AES-GCM encryption failed"
        case .fileNotFound(let f): return "Vault file not found: \(f)"
        }
    }
}
