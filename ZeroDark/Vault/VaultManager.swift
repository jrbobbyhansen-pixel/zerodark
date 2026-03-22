import Foundation
import CryptoKit
import UIKit

/// AES-256-GCM encrypted local vault. All ZeroDark data lives here.
/// Key derived from device identifierForVendor — unique per device/app install.
final class VaultManager {
    static let shared = VaultManager()
    private let vaultURL: URL
    private let key: SymmetricKey

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        vaultURL = docs.appendingPathComponent("ZeroDarkVault")
        try? FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        // Derive a 256-bit key from the device UUID
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "ZeroDarkFallback"
        let keyData = SHA256.hash(data: Data(deviceID.utf8))
        key = SymmetricKey(data: keyData)
    }

    // MARK: - Core Operations

    func save(data: Data, filename: String) throws {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw VaultError.encryptionFailed
        }
        let url = vaultURL.appendingPathComponent(filename)
        try combined.write(to: url, options: .atomic)
    }

    func load(filename: String) throws -> Data {
        let url = vaultURL.appendingPathComponent(filename)
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
        let url = vaultURL.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: url)
    }

    /// Decrypts to a temp file for ShareLink. Caller is responsible for cleanup.
    func exportURL(filename: String) throws -> URL {
        let data = try load(filename: filename)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: tmp, options: .atomic)
        return tmp
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
