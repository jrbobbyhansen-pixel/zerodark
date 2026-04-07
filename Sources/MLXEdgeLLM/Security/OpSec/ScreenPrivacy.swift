import SwiftUI
import UIKit
import AVFoundation

// MARK: - ScreenPrivacyManager

class ScreenPrivacyManager: ObservableObject {
    @Published private(set) var isPrivacyModeActive: Bool = false
    private var screenBlurEffect: UIVisualEffectView?
    private var privacyReminderLabel: UILabel?
    private var screenshotObserver: NSObjectProtocol?

    init() {
        setupScreenshotObserver()
    }

    deinit {
        removeScreenshotObserver()
    }

    func togglePrivacyMode() {
        isPrivacyModeActive.toggle()
        if isPrivacyModeActive {
            activatePrivacyMode()
        } else {
            deactivatePrivacyMode()
        }
    }

    private func activatePrivacyMode() {
        applyBlurEffect()
        showPrivacyReminder()
    }

    private func deactivatePrivacyMode() {
        removeBlurEffect()
        hidePrivacyReminder()
    }

    private func applyBlurEffect() {
        guard let window = UIApplication.shared.windows.first else { return }
        let blurEffect = UIBlurEffect(style: .dark)
        screenBlurEffect = UIVisualEffectView(effect: blurEffect)
        screenBlurEffect?.frame = window.frame
        window.addSubview(screenBlurEffect!)
    }

    private func removeBlurEffect() {
        screenBlurEffect?.removeFromSuperview()
        screenBlurEffect = nil
    }

    private func showPrivacyReminder() {
        guard let window = UIApplication.shared.windows.first else { return }
        privacyReminderLabel = UILabel()
        privacyReminderLabel?.text = "Privacy Mode Active"
        privacyReminderLabel?.textColor = .white
        privacyReminderLabel?.textAlignment = .center
        privacyReminderLabel?.frame = CGRect(x: 0, y: window.frame.height / 2, width: window.frame.width, height: 50)
        window.addSubview(privacyReminderLabel!)
    }

    private func hidePrivacyReminder() {
        privacyReminderLabel?.removeFromSuperview()
        privacyReminderLabel = nil
    }

    private func setupScreenshotObserver() {
        screenshotObserver = NotificationCenter.default.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenshot()
        }
    }

    private func removeScreenshotObserver() {
        if let observer = screenshotObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleScreenshot() {
        if isPrivacyModeActive {
            // Optionally, log or notify the user
        }
    }
}

// MARK: - ScreenPrivacyView

struct ScreenPrivacyView: View {
    @StateObject private var viewModel = ScreenPrivacyManager()

    var body: some View {
        VStack {
            Button(action: {
                viewModel.togglePrivacyMode()
            }) {
                Text(viewModel.isPrivacyModeActive ? "Deactivate Privacy Mode" : "Activate Privacy Mode")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Preview

struct ScreenPrivacyView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenPrivacyView()
    }
}