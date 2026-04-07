import Foundation
import SwiftUI
import Security

// MARK: - Key Management System

class KeyManager: ObservableObject {
    @Published private(set) var encryptionKey: Data?
    @Published private(set) var backupKey: Data?
    
    private let keychainService = KeychainService()
    
    init() {
        loadEncryptionKey()
        loadBackupKey()
    }
    
    func generateEncryptionKey() async {
        do {
            let key = try await generateKey()
            encryptionKey = key
            await saveEncryptionKey(key)
        } catch {
            print("Failed to generate encryption key: \(error)")
        }
    }
    
    func rotateEncryptionKey() async {
        do {
            let newKey = try await generateKey()
            encryptionKey = newKey
            await saveEncryptionKey(newKey)
            await revokeOldKey()
        } catch {
            print("Failed to rotate encryption key: \(error)")
        }
    }
    
    func revokeEncryptionKey() async {
        do {
            await revokeOldKey()
            encryptionKey = nil
        } catch {
            print("Failed to revoke encryption key: \(error)")
        }
    }
    
    func backupEncryptionKey() async {
        do {
            guard let encryptionKey = encryptionKey else {
                throw KeyManagementError.noEncryptionKey
            }
            backupKey = encryptionKey
            await saveBackupKey(encryptionKey)
        } catch {
            print("Failed to backup encryption key: \(error)")
        }
    }
    
    func restoreEncryptionKey() async {
        do {
            guard let backupKey = backupKey else {
                throw KeyManagementError.noBackupKey
            }
            encryptionKey = backupKey
            await saveEncryptionKey(backupKey)
        } catch {
            print("Failed to restore encryption key: \(error)")
        }
    }
    
    private func generateKey() async throws -> Data {
        let keySize = 32 // 256 bits
        let key = NSMutableData(length: keySize)!
        _ = SecRandomCopyBytes(kSecRandomDefault, keySize, key.mutableBytes.bindMemory(to: UInt8.self))
        return key as Data
    }
    
    private func saveEncryptionKey(_ key: Data) async {
        await keychainService.save(key, service: "ZeroDarkEncryptionKey")
    }
    
    private func loadEncryptionKey() {
        encryptionKey = keychainService.load(service: "ZeroDarkEncryptionKey")
    }
    
    private func saveBackupKey(_ key: Data) async {
        await keychainService.save(key, service: "ZeroDarkBackupKey")
    }
    
    private func loadBackupKey() {
        backupKey = keychainService.load(service: "ZeroDarkBackupKey")
    }
    
    private func revokeOldKey() async {
        await keychainService.delete(service: "ZeroDarkEncryptionKey")
    }
}

// MARK: - Keychain Service

class KeychainService {
    func save(_ data: Data, service: String) async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: service,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: service,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            return item as? Data
        }
        
        return nil
    }
    
    func delete(service: String) async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: service
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeyManagementError: Error {
    case noEncryptionKey
    case noBackupKey
}