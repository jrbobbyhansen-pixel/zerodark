import Foundation
import SwiftUI

// MARK: - DeviceSecurity

class DeviceSecurity: ObservableObject {
    @Published var isJailbroken: Bool = false
    @Published var isTampered: Bool = false
    @Published var securityScore: Int = 0
    @Published var recommendations: [String] = []

    private let jailbreakDetection = JailbreakDetection()
    private let tamperDetection = TamperDetection()

    init() {
        checkSecurityStatus()
    }

    func checkSecurityStatus() {
        isJailbroken = jailbreakDetection.isDeviceJailbroken()
        isTampered = tamperDetection.isDeviceTampered()
        securityScore = calculateSecurityScore()
        recommendations = generateRecommendations()
    }

    private func calculateSecurityScore() -> Int {
        var score = 100
        if isJailbroken {
            score -= 30
        }
        if isTampered {
            score -= 20
        }
        return score
    }

    private func generateRecommendations() -> [String] {
        var recs: [String] = []
        if isJailbroken {
            recs.append("Device is jailbroken. This can compromise security.")
        }
        if isTampered {
            recs.append("Device has been tampered with. This can lead to security risks.")
        }
        return recs
    }
}

// MARK: - JailbreakDetection

class JailbreakDetection {
    func isDeviceJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let fileManager = FileManager.default
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt"
        ]
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }
        return false
        #endif
    }
}

// MARK: - TamperDetection

class TamperDetection {
    func isDeviceTampered() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let fileManager = FileManager.default
        let paths = [
            "/etc/apt",
            "/private/var/lib/apt",
            "/private/var/lib/cydia"
        ]
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }
        return false
        #endif
    }
}

// MARK: - DeviceSecurityView

struct DeviceSecurityView: View {
    @StateObject private var deviceSecurity = DeviceSecurity()

    var body: some View {
        VStack {
            Text("Device Security Status")
                .font(.largeTitle)
                .padding()

            HStack {
                Text("Jailbroken: \(deviceSecurity.isJailbroken ? "Yes" : "No")")
                    .font(.headline)
                Spacer()
                Text("Tampered: \(deviceSecurity.isTampered ? "Yes" : "No")")
                    .font(.headline)
            }
            .padding()

            Text("Security Score: \(deviceSecurity.securityScore)")
                .font(.title2)
                .padding()

            if !deviceSecurity.recommendations.isEmpty {
                Text("Recommendations:")
                    .font(.headline)
                    .padding(.top)

                ForEach(deviceSecurity.recommendations, id: \.self) { recommendation in
                    Text("- \(recommendation)")
                        .font(.body)
                }
                .padding(.bottom)
            }

            Button(action: {
                deviceSecurity.checkSecurityStatus()
            }) {
                Text("Check Security Status")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct DeviceSecurityView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceSecurityView()
    }
}