// AppLockManager.swift — App-launch lock gate with biometric, PIN, and duress PIN.
//
// Three unlock paths:
//   1. Biometric (Face ID / Touch ID) — preferred when available & enrolled
//   2. Regular PIN — 4–8 digits, PBKDF2-hashed in the Keychain
//   3. Duress PIN — distinct hash; matching it appears to succeed but triggers
//      an emergency wipe first. The app then proceeds to a minimal/neutral state.
//
// PIN storage:
//   Keychain, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
//   PBKDF2-HMAC-SHA256, 100_000 iterations, 16-byte random per-PIN salt.
//   The salt is stored alongside the hash; PINs are never kept in plain form.
//
// Wipe actions (performWipe):
//   - Remove every Keychain item whose kSecAttrService begins with "com.zerodark."
//   - Remove files in Documents/ recursively
//   - Post .zdAppWipeRequested so subsystems (MeshService, caches) can shut down
//
// The manager does NOT reset iCloud, Photos, or anything outside the app sandbox.
// iOS app sandboxing means that's the extent of damage we can do and still return
// the user to a working (empty) app.

import Foundation
import Combine
import CryptoKit
import LocalAuthentication
import Security

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published private(set) var isUnlocked: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var isWiping: Bool = false

    /// True iff a regular PIN has been enrolled. If false, the gate still shows
    /// biometric-only; we fall back to a public "Skip" path so first-run flows work.
    @Published private(set) var hasPin: Bool = false
    @Published private(set) var hasDuressPin: Bool = false

    private let context = LAContext()

    private enum Kind {
        case regular, duress
        var account: String {
            switch self {
            case .regular: return "app.pin.regular"
            case .duress:  return "app.pin.duress"
            }
        }
    }

    private static let service = "com.zerodark.applock"
    private static let pbkdfIterations: UInt32 = 100_000

    private init() {
        refreshPinFlags()
    }

    // MARK: - Biometric

    /// Returns true iff the device has biometrics available and enrolled.
    var canUseBiometrics: Bool {
        var err: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    func attemptBiometricUnlock(reason: String = "Unlock ZeroDark") async {
        guard canUseBiometrics else {
            lastError = "Biometric authentication is not available"
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if ok {
                isUnlocked = true
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - PIN

    /// Validate a PIN. Returns one of:
    ///  - .ok       — regular PIN matched; gate unlocks
    ///  - .duress   — duress PIN matched; wipe executed before unlocking
    ///  - .mismatch — no match; gate stays locked
    enum PinResult { case ok, duress, mismatch }

    func submitPin(_ pin: String) async -> PinResult {
        if hasDuressPin, let h = read(kind: .duress), verify(pin: pin, hash: h) {
            await performWipe()
            // Appear to succeed so an observer (e.g. captor) sees a working app.
            isUnlocked = true
            return .duress
        }
        if hasPin, let h = read(kind: .regular), verify(pin: pin, hash: h) {
            isUnlocked = true
            return .ok
        }
        return .mismatch
    }

    /// Enroll or replace the regular PIN.
    func enrollRegularPin(_ pin: String) {
        store(pin: pin, kind: .regular)
        refreshPinFlags()
    }

    /// Enroll or replace the duress PIN.
    func enrollDuressPin(_ pin: String) {
        store(pin: pin, kind: .duress)
        refreshPinFlags()
    }

    /// Remove a PIN of the given kind.
    func clearPin(duress: Bool) {
        delete(kind: duress ? .duress : .regular)
        refreshPinFlags()
    }

    /// Lock the app (e.g. from Settings → Lock Now).
    func lock() {
        isUnlocked = false
    }

    /// Permit unlock when no PIN is enrolled AND biometrics are unavailable —
    /// a fallback so the app is usable on first run before a PIN is set. After
    /// first run, settings should prompt the user to enroll a PIN.
    func attemptBypassForFirstRun() {
        if !hasPin && !hasDuressPin && !canUseBiometrics {
            isUnlocked = true
        }
    }

    // MARK: - Wipe

    /// Destroy everything this app can touch: Documents, app-scoped Keychain items,
    /// mesh crypto state. iOS sandbox confines the blast radius to our app.
    func performWipe() async {
        isWiping = true
        defer { isWiping = false }

        // 1. Keychain items whose service starts with com.zerodark.*
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true
        ]
        var items: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
           let array = items as? [[CFString: Any]] {
            for attrs in array {
                if let svc = attrs[kSecAttrService] as? String, svc.hasPrefix("com.zerodark.") {
                    var del: [CFString: Any] = [
                        kSecClass: kSecClassGenericPassword,
                        kSecAttrService: svc
                    ]
                    if let account = attrs[kSecAttrAccount] as? String {
                        del[kSecAttrAccount] = account
                    }
                    SecItemDelete(del as CFDictionary)
                }
            }
        }

        // 2. Documents/ — recursive remove.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let contents = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // 3. Tell mesh + downstream subsystems to shut down.
        NotificationCenter.default.post(name: .zdAppWipeRequested, object: nil)

        // 4. Reset in-memory state.
        refreshPinFlags()
    }

    // MARK: - Keychain helpers

    private struct StoredHash: Codable {
        let salt: Data
        let hash: Data
    }

    private func store(pin: String, kind: Kind) {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        let salt = Data(saltBytes)
        let hash = pbkdf2(pin: pin, salt: salt)
        let payload = StoredHash(salt: salt, hash: hash)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: kind.account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func read(kind: Kind) -> StoredHash? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: kind.account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredHash.self, from: data)
    }

    private func delete(kind: Kind) {
        let del: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: kind.account
        ]
        SecItemDelete(del as CFDictionary)
    }

    private func refreshPinFlags() {
        hasPin = (read(kind: .regular) != nil)
        hasDuressPin = (read(kind: .duress) != nil)
    }

    private func verify(pin: String, hash stored: StoredHash) -> Bool {
        let candidate = pbkdf2(pin: pin, salt: stored.salt)
        // Constant-time compare.
        guard candidate.count == stored.hash.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<candidate.count {
            diff |= candidate[i] ^ stored.hash[i]
        }
        return diff == 0
    }

    private func pbkdf2(pin: String, salt: Data) -> Data {
        // HMAC-SHA256 based PBKDF2 using CryptoKit.
        let password = Array(pin.utf8)
        let saltBytes = [UInt8](salt)
        let blockSize = 32 // SHA256 output
        let iterations = Int(Self.pbkdfIterations)
        let derivedLength = 32

        var derived = [UInt8](repeating: 0, count: derivedLength)
        var block: [UInt8] = []
        let blocksNeeded = (derivedLength + blockSize - 1) / blockSize
        for blockIdx in 1...blocksNeeded {
            var blockData = saltBytes
            blockData.append(UInt8((blockIdx >> 24) & 0xff))
            blockData.append(UInt8((blockIdx >> 16) & 0xff))
            blockData.append(UInt8((blockIdx >> 8) & 0xff))
            blockData.append(UInt8(blockIdx & 0xff))

            var u = Array(HMAC<SHA256>.authenticationCode(for: blockData, using: SymmetricKey(data: password)))
            var result = u
            for _ in 1..<iterations {
                u = Array(HMAC<SHA256>.authenticationCode(for: u, using: SymmetricKey(data: password)))
                for i in 0..<blockSize { result[i] ^= u[i] }
            }
            block.append(contentsOf: result)
        }
        for i in 0..<derivedLength { derived[i] = block[i] }
        return Data(derived)
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted when the user has triggered an emergency wipe (duress PIN or manual).
    /// Subsystems should flush in-memory state, close connections, and not attempt
    /// to write more data to Documents — it's being torn down.
    static let zdAppWipeRequested = Notification.Name("ZDAppWipeRequested")
}
