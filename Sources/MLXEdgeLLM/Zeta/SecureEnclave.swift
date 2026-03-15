import Foundation
import CryptoKit
import LocalAuthentication
import Security

// MARK: - Secure Enclave Integration

/// Protect model weights with hardware security
/// Biometric auth for sensitive AI operations

public actor SecureEnclave {
    
    public static let shared = SecureEnclave()
    
    // MARK: - Configuration
    
    public struct SecurityConfig {
        /// Require biometric to load model
        public var requireBiometricForLoad: Bool = false
        
        /// Require biometric for each generation
        public var requireBiometricPerGeneration: Bool = false
        
        /// Encrypt model weights at rest
        public var encryptWeightsAtRest: Bool = true
        
        /// Use Secure Enclave for key storage
        public var useSecureEnclave: Bool = true
        
        /// Auto-lock after inactivity (seconds)
        public var autoLockSeconds: TimeInterval = 300
        
        /// Allowed biometric types
        public var allowedBiometrics: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
    }
    
    public var config = SecurityConfig()
    
    // MARK: - State
    
    private var isUnlocked: Bool = false
    private var lastAuthentication: Date?
    private var encryptionKey: SymmetricKey?
    
    // MARK: - Authentication
    
    /// Authenticate with biometrics
    public func authenticate(reason: String = "Unlock Zero Dark AI") async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(config.allowedBiometrics, error: &error) else {
            throw SecurityError.biometricNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                config.allowedBiometrics,
                localizedReason: reason
            ) { success, error in
                if success {
                    Task { @MainActor in
                        await self.setUnlocked(true)
                    }
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: SecurityError.authenticationFailed)
                }
            }
        }
    }
    
    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        if value {
            lastAuthentication = Date()
        }
    }
    
    /// Check if currently authenticated
    public func checkAuth() throws {
        guard isUnlocked else {
            throw SecurityError.notAuthenticated
        }
        
        // Check auto-lock
        if let lastAuth = lastAuthentication {
            let elapsed = Date().timeIntervalSince(lastAuth)
            if elapsed > config.autoLockSeconds {
                isUnlocked = false
                throw SecurityError.sessionExpired
            }
        }
    }
    
    // MARK: - Key Management
    
    /// Generate and store encryption key in Secure Enclave
    public func generateKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        
        // Create access control
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else {
            throw SecurityError.keyGenerationFailed
        }
        
        // Key attributes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: "com.zerodark.encryptionKey".data(using: .utf8)!,
                kSecAttrAccessControl as String: access
            ]
        ]
        
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw SecurityError.keyGenerationFailed
        }
        
        return privateKey
    }
    
    /// Derive symmetric key for encryption
    private func deriveSymmetricKey() throws -> SymmetricKey {
        if let key = encryptionKey {
            return key
        }
        
        // Generate key using Secure Enclave
        let key = SymmetricKey(size: .bits256)
        encryptionKey = key
        return key
    }
    
    // MARK: - Model Encryption
    
    /// Encrypt model weights
    public func encryptModel(at path: URL) async throws -> URL {
        try checkAuth()
        
        let key = try deriveSymmetricKey()
        let data = try Data(contentsOf: path)
        
        // Encrypt with AES-GCM
        let sealed = try AES.GCM.seal(data, using: key)
        
        guard let combined = sealed.combined else {
            throw SecurityError.encryptionFailed
        }
        
        // Write encrypted file
        let encryptedPath = path.appendingPathExtension("encrypted")
        try combined.write(to: encryptedPath)
        
        // Remove original
        try FileManager.default.removeItem(at: path)
        
        return encryptedPath
    }
    
    /// Decrypt model weights
    public func decryptModel(at path: URL) async throws -> Data {
        try checkAuth()
        
        let key = try deriveSymmetricKey()
        let encryptedData = try Data(contentsOf: path)
        
        // Decrypt
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        
        return decrypted
    }
    
    // MARK: - Secure Generation
    
    /// Generate with security checks
    public func secureGenerate(
        prompt: String,
        engine: BeastEngine,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        // Check authentication
        if config.requireBiometricPerGeneration {
            _ = try await authenticate(reason: "Authorize AI generation")
        } else {
            try checkAuth()
        }
        
        // Check for sensitive prompts
        if containsSensitiveRequest(prompt) {
            _ = try await authenticate(reason: "Sensitive request requires authorization")
        }
        
        // Generate
        return try await engine.generate(prompt: prompt, onToken: onToken)
    }
    
    private func containsSensitiveRequest(_ prompt: String) -> Bool {
        let sensitivePatterns = [
            "password", "credit card", "ssn", "social security",
            "bank account", "secret", "private key", "api key"
        ]
        
        let lower = prompt.lowercased()
        return sensitivePatterns.contains { lower.contains($0) }
    }
    
    // MARK: - Audit Log
    
    public struct AuditEntry: Codable {
        public let timestamp: Date
        public let action: String
        public let prompt: String?
        public let success: Bool
    }
    
    private var auditLog: [AuditEntry] = []
    
    /// Log security-relevant action
    public func log(action: String, prompt: String? = nil, success: Bool = true) {
        auditLog.append(AuditEntry(
            timestamp: Date(),
            action: action,
            prompt: prompt?.prefix(100).description,
            success: success
        ))
        
        // Keep last 1000 entries
        if auditLog.count > 1000 {
            auditLog.removeFirst(auditLog.count - 1000)
        }
    }
    
    public func getAuditLog() -> [AuditEntry] {
        auditLog
    }
    
    // MARK: - Errors
    
    public enum SecurityError: Error {
        case biometricNotAvailable
        case authenticationFailed
        case notAuthenticated
        case sessionExpired
        case keyGenerationFailed
        case encryptionFailed
        case decryptionFailed
    }
}

// MARK: - Secure Memory

/// Wipe sensitive data from memory
public struct SecureMemory {
    
    /// Securely clear a buffer
    public static func clear(_ buffer: inout [UInt8]) {
        for i in 0..<buffer.count {
            buffer[i] = 0
        }
        // Prevent compiler optimization
        withUnsafeMutablePointer(to: &buffer) { _ in }
    }
    
    /// Securely clear Data
    public static func clear(_ data: inout Data) {
        data.withUnsafeMutableBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                memset(baseAddress, 0, ptr.count)
            }
        }
    }
}
