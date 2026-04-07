import Foundation
import SwiftUI
import CryptoKit

// MARK: - SecureBroadcast

class SecureBroadcast: ObservableObject {
    @Published var encryptedMessages: [String] = []
    @Published var groupKey: SymmetricKey?
    
    private let keychainService = KeychainService()
    
    init() {
        loadGroupKey()
    }
    
    func generateGroupKey() {
        let newKey = SymmetricKey(size: .aes256)
        groupKey = newKey
        saveGroupKey(newKey)
    }
    
    func encryptMessage(_ message: String) -> String? {
        guard let key = groupKey else { return nil }
        let sealedBox = try? ChaChaPoly.seal(message.data(using: .utf8)!, using: key)
        return sealedBox?.ciphertext.base64EncodedString()
    }
    
    func decryptMessage(_ encryptedMessage: String) -> String? {
        guard let key = groupKey, let sealedBox = try? ChaChaPoly.SealedBox(combined: Data(base64Encoded: encryptedMessage)!) else { return nil }
        let decryptedData = try? ChaChaPoly.open(sealedBox, using: key)
        return String(data: decryptedData!, encoding: .utf8)
    }
    
    private func saveGroupKey(_ key: SymmetricKey) {
        keychainService.save(key, forKey: "groupKey")
    }
    
    private func loadGroupKey() {
        if let keyData = keychainService.load(forKey: "groupKey"), let key = SymmetricKey(data: keyData) {
            groupKey = key
        }
    }
}

// MARK: - KeychainService

class KeychainService {
    func save(_ value: SymmetricKey, forKey key: String) {
        let data = value.data
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyClass as String: kSecAttrKeyClassSymmetric,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrLabel as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyClass as String: kSecAttrKeyClassSymmetric,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrLabel as String: key,
            kSecReturnData as String: kCFBooleanTrue
        ]
        
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? item as? Data : nil
    }
}