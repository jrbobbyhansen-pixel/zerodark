// AppLockGate.swift — SwiftUI gate that shows a lock screen until the app is unlocked.
// Wraps any content view; displays nothing of the real app until auth passes.

import SwiftUI

struct AppLockGate<Content: View>: View {
    @ObservedObject private var lock = AppLockManager.shared
    @State private var pinDigits: String = ""
    @State private var errorFlash: Bool = false
    @State private var lockoutTick: Int = 0   // forces view re-render every second during lockout
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    private var isLockedOut: Bool { lock.lockoutSecondsRemaining > 0 }

    var body: some View {
        ZStack {
            if lock.isUnlocked {
                content()
            } else {
                lockScreen
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
        .task {
            // Auto-try biometrics on first appearance if enrolled.
            if lock.canUseBiometrics {
                await lock.attemptBiometricUnlock()
            }
        }
        .task(id: lockoutTick) {
            // While locked out, tick once per second so the countdown updates.
            guard isLockedOut else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            lockoutTick &+= 1
        }
    }

    // MARK: - Lock screen

    private var lockScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(ZDDesign.cyanAccent)
                    .accessibilityHidden(true)
                Text("ZeroDark").font(.largeTitle.bold()).foregroundColor(.white)
                Text("Locked").font(.headline).foregroundColor(.secondary)
                    .accessibilityAddTraits(.isHeader)

                if lock.canUseBiometrics && !isLockedOut {
                    Button {
                        Task { await lock.attemptBiometricUnlock() }
                    } label: {
                        Label("Use Face ID / Touch ID", systemImage: "faceid")
                            .font(.callout.bold())
                            .padding(.vertical, 10)
                            .padding(.horizontal, 18)
                            .background(ZDDesign.cyanAccent.opacity(0.15))
                            .foregroundColor(ZDDesign.cyanAccent)
                            .clipShape(Capsule())
                    }
                }

                if isLockedOut {
                    lockoutBanner
                } else if lock.hasPin || lock.hasDuressPin {
                    pinEntry
                } else {
                    noPinFallback
                }

                if lock.consecutiveFailures > 0 && !isLockedOut {
                    Text("Failed attempts: \(lock.consecutiveFailures)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let err = lock.lastError {
                    Text(err).font(.caption).foregroundColor(ZDDesign.signalRed).padding(.horizontal, 32)
                }

                if lock.isWiping {
                    ProgressView("Wiping…").tint(ZDDesign.signalRed)
                }

                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }

    private var pinEntry: some View {
        VStack(spacing: 14) {
            Text("Enter PIN").font(.subheadline).foregroundColor(.secondary)
            SecureField("", text: $pinDigits)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .padding()
                .frame(width: 220)
                .background(errorFlash ? ZDDesign.signalRed.opacity(0.2) : Color.white.opacity(0.08))
                .cornerRadius(12)
                .onChange(of: pinDigits) { _, new in
                    // Auto-submit once the operator enters a valid-length PIN.
                    // Minimum bumped to 6 digits in PR-B4.
                    if new.count >= AppLockManager.minPinLength && new.count <= AppLockManager.maxPinLength {
                        Task { await submit() }
                    }
                }
                .accessibilityLabel("PIN entry")
                .accessibilityHint("Minimum \(AppLockManager.minPinLength) digits")
            Text("Enter your \(AppLockManager.minPinLength)–\(AppLockManager.maxPinLength)-digit PIN to unlock")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var lockoutBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.system(size: 40))
                .foregroundColor(ZDDesign.signalRed)
                .accessibilityHidden(true)
            Text("Too many failed attempts")
                .font(.headline)
                .foregroundColor(.white)
            Text("Try again in \(formatLockout(lock.lockoutSecondsRemaining))")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(ZDDesign.signalRed)
                .accessibilityLabel("Try again in \(formatLockout(lock.lockoutSecondsRemaining))")
            Text("Biometric unlock is also disabled during lockout.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func formatLockout(_ seconds: Int) -> String {
        if seconds >= 60 {
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%d:%02d", m, s)
        }
        return "\(seconds)s"
    }

    private var noPinFallback: some View {
        VStack(spacing: 10) {
            Text("No PIN enrolled").font(.caption).foregroundColor(.secondary)
            Button {
                // First-run allowance: proceed without PIN. Post-onboarding flow
                // should prompt to enroll one.
                AppLockManager.shared.attemptBypassForFirstRun()
            } label: {
                Text("Continue without PIN")
                    .font(.caption.bold())
                    .foregroundColor(ZDDesign.cyanAccent)
            }
        }
    }

    private func submit() async {
        let entered = pinDigits
        let result = await lock.submitPin(entered)
        switch result {
        case .ok:
            pinDigits = ""
        case .duress:
            pinDigits = ""
            // Duress: we've wiped and unlocked. Nothing more for the UI to do.
        case .mismatch:
            errorFlash = true
            pinDigits = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { errorFlash = false }
        }
    }
}

