import Foundation
import SwiftUI

// MARK: - FileEncryptionManager

final class FileEncryptionManager: ObservableObject {
    @Published private(set) var encryptionProgress: Double = 0.0
    @Published private(set) var decryptionProgress: Double = 0.0
    @Published private(set) var isEncrypting: Bool = false
    @Published private(set) var isDecrypting: Bool = false
    
    private let encryptionQueue = DispatchQueue(label: "com.zerodark.encryptionQueue", qos: .userInitiated)
    private let decryptionQueue = DispatchQueue(label: "com.zerodark.decryptionQueue", qos: .userInitiated)
    
    private var encryptionTask: Task<Void, Never>?
    private var decryptionTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    func encryptFiles(at urls: [URL], withKey key: Data) {
        guard !isEncrypting else { return }
        
        isEncrypting = true
        encryptionProgress = 0.0
        
        encryptionTask = Task {
            for (index, url) in urls.enumerated() {
                do {
                    let encryptedData = try encryptData(at: url, withKey: key)
                    try encryptedData.write(to: url)
                } catch {
                    print("Failed to encrypt file at \(url): \(error)")
                }
                encryptionProgress = Double(index + 1) / Double(urls.count)
            }
            isEncrypting = false
        }
    }
    
    func decryptFiles(at urls: [URL], withKey key: Data) {
        guard !isDecrypting else { return }
        
        isDecrypting = true
        decryptionProgress = 0.0
        
        decryptionTask = Task {
            for (index, url) in urls.enumerated() {
                do {
                    let decryptedData = try decryptData(at: url, withKey: key)
                    try decryptedData.write(to: url)
                } catch {
                    print("Failed to decrypt file at \(url): \(error)")
                }
                decryptionProgress = Double(index + 1) / Double(urls.count)
            }
            isDecrypting = false
        }
    }
    
    func secureDeleteFiles(at urls: [URL]) {
        for url in urls {
            do {
                try secureDelete(at: url)
            } catch {
                print("Failed to securely delete file at \(url): \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func encryptData(at url: URL, withKey key: Data) throws -> Data {
        let data = try Data(contentsOf: url)
        return try AES256.encrypt(data: data, key: key)
    }
    
    private func decryptData(at url: URL, withKey key: Data) throws -> Data {
        let data = try Data(contentsOf: url)
        return try AES256.decrypt(data: data, key: key)
    }
    
    private func secureDelete(at url: URL) throws {
        guard let fileHandle = try? FileHandle(forWritingTo: url) else {
            throw NSError(domain: "SecureDeleteError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open file for secure deletion"])
        }
        
        let fileSize = fileHandle.seekToEndOfFile()
        fileHandle.seek(toFileOffset: 0)
        
        let bufferSize = 4096
        let buffer = [UInt8](repeating: 0, count: bufferSize)
        
        for _ in stride(from: 0, to: fileSize, by: bufferSize) {
            fileHandle.write(buffer)
        }
        
        try fileHandle.synchronize()
        fileHandle.closeFile()
        
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - AES256

struct AES256 {
    static func encrypt(data: Data, key: Data) throws -> Data {
        guard key.count == 32 else {
            throw NSError(domain: "AES256Error", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid key length"])
        }
        
        let iv = AES.randomIV()
        let cipher = try AES(key: key, blockMode: GCM(iv: iv), padding: .noPadding)
        let encryptedData = try cipher.encrypt(data)
        return iv + encryptedData
    }
    
    static func decrypt(data: Data, key: Data) throws -> Data {
        guard key.count == 32 else {
            throw NSError(domain: "AES256Error", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid key length"])
        }
        
        let ivSize = 12
        guard data.count > ivSize else {
            throw NSError(domain: "AES256Error", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid data length"])
        }
        
        let iv = data[0..<ivSize]
        let encryptedData = data[ivSize...]
        let cipher = try AES(key: key, blockMode: GCM(iv: iv), padding: .noPadding)
        return try cipher.decrypt(encryptedData)
    }
    
    private static func randomIV() -> Data {
        return Data.randomBytes(count: 12)
    }
}

// MARK: - Data Extension

extension Data {
    static func randomBytes(count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else {
            fatalError("Failed to generate random bytes")
        }
        return data
    }
}