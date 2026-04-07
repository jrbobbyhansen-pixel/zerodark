import Foundation
import SwiftUI
import LocalAuthentication

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isBiometricAvailable = false
    @Published var isBiometricEnabled = false
    @Published var lockoutEnabled = true
    @Published var lockoutAttempts = 0
    @Published var lockoutDuration: TimeInterval = 600 // 10 minutes
    @Published var lockoutEndDate: Date?

    private let maxFailedAttempts = 5
    private let keychainService = "ZeroDarkAuthService"
    private let keychainAccount = "UserCredentials"

    init() {
        checkBiometricAvailability()
        loadCredentials()
    }

    func authenticate(pin: String) async {
        if let storedPIN = loadPIN(), storedPIN == pin {
            isAuthenticated = true
            resetLockout()
        } else {
            incrementFailedAttempts()
            if lockoutEnabled && lockoutAttempts >= maxFailedAttempts {
                enableLockout()
            }
        }
    }

    func authenticateBiometric() async {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to access ZeroDark")
                isAuthenticated = true
                resetLockout()
            } catch {
                incrementFailedAttempts()
                if lockoutEnabled && lockoutAttempts >= maxFailedAttempts {
                    enableLockout()
                }
            }
        }
    }

    func setPIN(_ pin: String) {
        savePIN(pin)
        isAuthenticated = true
    }

    func toggleBiometricAuthentication(_ isEnabled: Bool) {
        isBiometricEnabled = isEnabled
    }

    func resetLockout() {
        lockoutAttempts = 0
        lockoutEndDate = nil
    }

    private func checkBiometricAvailability() {
        let context = LAContext()
        isBiometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private func loadCredentials() {
        if let data = Keychain.load(service: keychainService, account: keychainAccount) {
            isAuthenticated = true
        }
    }

    private func savePIN(_ pin: String) {
        Keychain.save(pin, service: keychainService, account: keychainAccount)
    }

    private func loadPIN() -> String? {
        return Keychain.load(service: keychainService, account: keychainAccount)
    }

    private func incrementFailedAttempts() {
        lockoutAttempts += 1
    }

    private func enableLockout() {
        lockoutEndDate = Date().addingTimeInterval(lockoutDuration)
    }
}

class Keychain {
    static func save(_ value: String, service: String, account: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            if let data = item as? Data, let value = String(data: data, encoding: .utf8) {
                return value
            }
        }

        return nil
    }
}