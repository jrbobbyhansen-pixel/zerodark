import Foundation
import CryptoKit
import Security

struct EncryptionEngine {
    private let keychainService = KeychainService()
    
    func encrypt(data: Data, password: String) throws -> EncryptedData {
        let key = try deriveKey(from: password)
        let iv = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: iv)
        return EncryptedData(iv: iv, sealedBox: sealedBox)
    }
    
    func decrypt(encryptedData: EncryptedData, password: String) throws -> Data {
        let key = try deriveKey(from: password)
        return try AES.GCM.open(encryptedData.sealedBox, using: key)
    }
    
    private func deriveKey(from password: String) throws -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        let salt = SymmetricKey(size: .aes256)
        let derivedKey = try PBKDF2(password: passwordData, salt: salt, iterations: 10000, derivedKeyLength: 32).deriveKey()
        return SymmetricKey(data: derivedKey)
    }
}

struct EncryptedData: Codable {
    let iv: AES.GCM.Nonce
    let sealedBox: AES.GCM.SealedBox
    
    enum CodingKeys: String, CodingKey {
        case iv
        case sealedBox
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ivData = try container.decode(Data.self, forKey: .iv)
        self.iv = try AES.GCM.Nonce(data: ivData)
        let sealedBoxData = try container.decode(Data.self, forKey: .sealedBox)
        self.sealedBox = try AES.GCM.SealedBox(combined: sealedBoxData)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(iv.withUnsafeBytes { Data($0) }, forKey: .iv)
        try container.encode(sealedBox.combined, forKey: .sealedBox)
    }
}

class KeychainService {
    func save(key: SymmetricKey, service: String, account: String) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrKeyClass as String: kSecAttrKeyClassSymmetric,
            kSecAttrKeyType as String: kSecAttrKeyTypeAES,
            kSecAttrKeySizeInBits as String: 256
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    func load(service: String, account: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecAttrKeyClass as String: kSecAttrKeyClassSymmetric
        ]
        
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let keyData = item as? Data else {
            throw KeychainError.unhandledError(status: status)
        }
        
        return SymmetricKey(data: keyData)
    }
}

enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}