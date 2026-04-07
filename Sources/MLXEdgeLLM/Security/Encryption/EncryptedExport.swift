import Foundation
import SwiftUI
import CryptoKit

// MARK: - EncryptedExport

struct EncryptedExport {
    let data: Data
    let password: String
    
    func export() throws -> Data {
        let encryptedData = try encrypt(data: data, password: password)
        return encryptedData
    }
    
    func selfDecryptingExport() throws -> Data {
        let encryptedData = try encrypt(data: data, password: password)
        let selfDecryptingData = try createSelfDecryptingData(encryptedData: encryptedData, password: password)
        return selfDecryptingData
    }
    
    private func encrypt(data: Data, password: String) throws -> Data {
        let key = try deriveKey(from: password)
        let iv = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: iv)
        let ivData = iv.withUnsafeBytes { Data($0) }
        return ivData + sealedBox.ciphertext
    }
    
    private func deriveKey(from password: String) throws -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        let derivedKey = try HKDF<SHA256>.deriveKey(input: passwordData, salt: Data(), info: Data(), outputByteCount: 32)
        return SymmetricKey(data: derivedKey)
    }
    
    private func createSelfDecryptingData(encryptedData: Data, password: String) throws -> Data {
        let passwordData = password.data(using: .utf8)!
        let selfDecryptingData = "ZERODARK_SELF_DECRYPTING\(passwordData.base64EncodedString())\(encryptedData.base64EncodedString())"
        return selfDecryptingData.data(using: .utf8)!
    }
}

// MARK: - DecryptedExport

struct DecryptedExport {
    let encryptedData: Data
    let password: String
    
    func decrypt() throws -> Data {
        let key = try deriveKey(from: password)
        let ivData = encryptedData.prefix(AES.GCM.Nonce.byteCount)
        let ciphertext = encryptedData.suffix(from: AES.GCM.Nonce.byteCount)
        
        let iv = try AES.GCM.Nonce(data: ivData)
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let decryptedData = try AES.GCM.open(sealedBox, using: key, nonce: iv)
        return decryptedData
    }
    
    private func deriveKey(from password: String) throws -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        let derivedKey = try HKDF<SHA256>.deriveKey(input: passwordData, salt: Data(), info: Data(), outputByteCount: 32)
        return SymmetricKey(data: derivedKey)
    }
}

// MARK: - SelfDecryptingData

struct SelfDecryptingData {
    let data: Data
    
    func decrypt() throws -> Data {
        guard let selfDecryptingString = String(data: data, encoding: .utf8),
              selfDecryptingString.hasPrefix("ZERODARK_SELF_DECRYPTING") else {
            throw NSError(domain: "Invalid self-decrypting format", code: 1, userInfo: nil)
        }
        
        let passwordBase64 = selfDecryptingString.dropFirst("ZERODARK_SELF_DECRYPTING".count).prefix(while: { $0 != "=" })
        let encryptedDataBase64 = selfDecryptingString.dropFirst("ZERODARK_SELF_DECRYPTING".count + passwordBase64.count)
        
        guard let passwordData = Data(base64Encoded: String(passwordBase64)),
              let encryptedData = Data(base64Encoded: String(encryptedDataBase64)) else {
            throw NSError(domain: "Invalid base64 encoding", code: 2, userInfo: nil)
        }
        
        let password = String(data: passwordData, encoding: .utf8)!
        let decryptedData = try DecryptedExport(encryptedData: encryptedData, password: password).decrypt()
        return decryptedData
    }
}