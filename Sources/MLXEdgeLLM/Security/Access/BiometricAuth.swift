import Foundation
import SwiftUI
import LocalAuthentication

// MARK: - BiometricAuth

class BiometricAuth: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isBiometricAvailable = false
    @Published var biometricType: BiometricType = .none
    @Published var error: Error?

    private let context = LAContext()

    enum BiometricType {
        case none
        case touchID
        case faceID
    }

    init() {
        checkBiometricAvailability()
    }

    func authenticate() {
        guard isBiometricAvailable else {
            error = AuthenticationError.biometricNotAvailable
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to access ZeroDark") { [weak self] success, authenticationError in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthenticated = true
                } else {
                    self?.error = authenticationError ?? AuthenticationError.unknown
                }
            }
        }
    }

    func checkBiometricAvailability() {
        var error: NSError?
        let availableBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if availableBiometrics {
            if context.biometryType == .touchID {
                biometricType = .touchID
            } else if context.biometryType == .faceID {
                biometricType = .faceID
            }
            isBiometricAvailable = true
        } else {
            error = error ?? AuthenticationError.biometricNotAvailable
            isBiometricAvailable = false
        }
    }

    func resetAuthentication() {
        isAuthenticated = false
    }
}

// MARK: - Errors

enum AuthenticationError: Error, LocalizedError {
    case biometricNotAvailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .unknown:
            return "An unknown error occurred during authentication."
        }
    }
}

// MARK: - SwiftUI View

struct BiometricAuthView: View {
    @StateObject private var auth = BiometricAuth()

    var body: some View {
        VStack {
            Text("Biometric Authentication")
                .font(.largeTitle)
                .padding()

            if auth.isBiometricAvailable {
                Button(action: auth.authenticate) {
                    Text("Authenticate with \(auth.biometricType == .touchID ? "Touch ID" : "Face ID")")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            } else {
                Text("Biometric authentication is not available.")
                    .foregroundColor(.red)
            }

            if let error = auth.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear {
            auth.checkBiometricAvailability()
        }
    }
}

// MARK: - Preview

struct BiometricAuthView_Previews: PreviewProvider {
    static var previews: some View {
        BiometricAuthView()
    }
}