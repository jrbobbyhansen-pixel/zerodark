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

    // MARK: - Full Reset

    func resetAll() {
        deletePassphrase()
        UserDefaults.standard.removeObject(forKey: trustedDevicesKey)
        UserDefaults.standard.removeObject(forKey: autoConnectKey)
    }
}
