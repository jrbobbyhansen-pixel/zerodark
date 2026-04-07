import Foundation
import SwiftUI

class SessionManager: ObservableObject {
    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var lastActivityDate: Date = Date()
    private var sessionTimer: Timer?
    private let sessionTimeout: TimeInterval = 1800 // 30 minutes

    init() {
        startSessionTimer()
    }

    deinit {
        stopSessionTimer()
    }

    func login() {
        isLoggedIn = true
        lastActivityDate = Date()
        startSessionTimer()
    }

    func logout() {
        isLoggedIn = false
        stopSessionTimer()
    }

    func updateActivity() {
        lastActivityDate = Date()
    }

    func terminateRemoteSession() {
        // Implementation for remote session termination
        // This could involve network calls to a server
    }

    private func startSessionTimer() {
        stopSessionTimer()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeout, repeats: false) { [weak self] _ in
            self?.logout()
        }
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }
}

struct SessionManager_Previews: PreviewProvider {
    static var previews: some View {
        Text("Session Manager Preview")
            .environmentObject(SessionManager())
    }
}