// AppLockGate.swift — SwiftUI gate that shows a lock screen until the app is unlocked.
// Wraps any content view; displays nothing of the real app until auth passes.

import SwiftUI

struct AppLockGate<Content: View>: View {
    @ObservedObject private var lock = AppLockManager.shared
    @State private var pinDigits: String = ""
    @State private var errorFlash: Bool = false
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

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

                if lock.canUseBiometrics {
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

                if lock.hasPin || lock.hasDuressPin {
                    pinEntry
                } else {
                    noPinFallback
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
                    if new.count >= 4 && new.count <= 8 {
                        Task { await submit() }
                    }
                }
            Text("Enter your PIN to unlock").font(.caption2).foregroundColor(.secondary)
        }
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

