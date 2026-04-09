// ZDKeychain.swift — Secure Keychain wrapper for ZeroDark credentials
// Uses iOS Data Protection: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
// All TAK credentials, session tokens, and API keys go through here.

import Foundation
import Security

enum ZDKeychain {
    private static let service = "com.bobbyhansen.zerodark"

    // MARK: - CRUD

    @discardableResult
    static func save(_ value: String, key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Named Keys (TAK Credentials)

    enum Keys {
        static let takHost    = "tak.host"
        static let takPort    = "tak.port"
        static let takTLSPort = "tak.tls_port"
        static let callsign   = "identity.callsign"
        static let sessionKey = "session.key"
    }
}
