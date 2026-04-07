// MeshKeychain.swift – Secure storage for mesh credentials

import Foundation
import Security

final class MeshKeychain {

    static let shared = MeshKeychain()

    private let serviceIdentifier = "com.zerodark.mesh"
    private let passphraseKey = "groupPassphrase"
    private let trustedDevicesKey = "trustedDevices"
    private let autoConnectKey = "autoConnect"

    private init() {}

    // MARK: - Passphrase Storage

    /// Save group passphrase to Keychain
    func savePassphrase(_ passphrase: String) -> Bool {
        guard let data = passphrase.data(using: .utf8) else { return false }

        // Delete existing first
        deletePassphrase()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: passphraseKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve group passphrase from Keychain
    func getPassphrase() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: passphraseKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let passphrase = String(data: data, encoding: .utf8) else {
            return nil
        }

        return passphrase
    }

    /// Delete passphrase from Keychain
    @discardableResult
    func deletePassphrase() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: passphraseKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if passphrase exists
    var hasPassphrase: Bool {
        getPassphrase() != nil
    }

    // MARK: - Auto-Connect Setting

    var autoConnectEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoConnectKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoConnectKey) }
    }

    // MARK: - Trusted Devices

    struct TrustedDevice: Codable, Identifiable {
        let id: String          // Device UUID
        var nickname: String    // User-assigned name
        let firstSeen: Date
        var lastSeen: Date
    }

    /// Save trusted device list
    func saveTrustedDevices(_ devices: [TrustedDevice]) {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        UserDefaults.standard.set(data, forKey: trustedDevicesKey)
    }

    /// Get trusted device list
    func getTrustedDevices() -> [TrustedDevice] {
        guard let data = UserDefaults.standard.data(forKey: trustedDevicesKey),
              let devices = try? JSONDecoder().decode([TrustedDevice].self, from: data) else {
            return []
        }
        return devices
    }

    /// Add or update trusted device
    func trustDevice(id: String, nickname: String) {
        var devices = getTrustedDevices()

        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].nickname = nickname
            devices[index].lastSeen = Date()
        } else {
            devices.append(TrustedDevice(
                id: id,
                nickname: nickname,
                firstSeen: Date(),
                lastSeen: Date()
            ))
        }

        saveTrustedDevices(devices)
    }

    /// Remove trusted device
    func removeTrustedDevice(id: String) {
        var devices = getTrustedDevices()
        devices.removeAll { $0.id == id }
        saveTrustedDevices(devices)
    }

    /// Check if device is trusted
    func isDeviceTrusted(id: String) -> Bool {
        getTrustedDevices().contains { $0.id == id }
    }

    /// Get nickname for device (or nil if not trusted)
    func nickname(for deviceId: String) -> String? {
        getTrustedDevices().first { $0.id == deviceId }?.nickname
    }

    // MARK: - Session Key Storage (v6.1 — geofence-aware)

    private let sessionKeyPrefix = "sessionKey:"

    /// Save an ephemeral session key to Keychain
    func saveSessionKey(_ keyData: Data, id: UUID, context: String) -> Bool {
        let account = "\(sessionKeyPrefix)\(id.uuidString)"

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Store key with context in label
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: context,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve session key by ID
    func getSessionKey(id: UUID) -> Data? {
        let account = "\(sessionKeyPrefix)\(id.uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    /// Clear all session keys from Keychain
    func clearSessionKeys() {
        // Query for all items with our service prefix
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier
        ]
        // This deletes all items for our service — we'll re-save passphrase if needed
        let savedPassphrase = getPassphrase()
        SecItemDelete(query as CFDictionary)
        if let passphrase = savedPassphrase {
            _ = savePassphrase(passphrase)
        }
    }

    /// Generate and store a new session key bound to a geofence crossing
    func rotateKeyForGeofence(fenceId: UUID, fenceName: String) {
        // Generate 256-bit random key
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        let keyData = Data(keyBytes)

        let keyId = UUID()
        let context = "geofence:\(fenceId.uuidString):\(fenceName)"
        _ = saveSessionKey(keyData, id: keyId, context: context)

        // Notify SessionKeyManager if available
        Task {
            await SessionKeyManager.shared.injectExternalKey(keyData, id: keyId)
        }
    }

    // MARK: - Full Reset

    func resetAll() {
        deletePassphrase()
        clearSessionKeys()
        UserDefaults.standard.removeObject(forKey: trustedDevicesKey)
        UserDefaults.standard.removeObject(forKey: autoConnectKey)
    }
}
