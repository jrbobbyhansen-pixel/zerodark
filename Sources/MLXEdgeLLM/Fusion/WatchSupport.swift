import Foundation

// MARK: - Apple Watch Support

/// Zero Dark on your wrist
/// Voice-first, quick responses, glanceable AI

/*
 Implementation requires a watchOS target.
 Zero Dark uses two approaches:
 
 1. WatchConnectivity - Phone does inference, Watch displays
 2. On-device (Watch Ultra) - Small models run on Watch
 
 Watch Ultra with 64GB storage can run Qwen3 0.6B (~400MB)
*/

#if os(watchOS)
import WatchKit
import WatchConnectivity

// MARK: - Watch Session Manager

public final class WatchSessionManager: NSObject, ObservableObject {
    
    public static let shared = WatchSessionManager()
    
    @Published public var isReachable = false
    @Published public var lastResponse: String?
    @Published public var isProcessing = false
    
    private var session: WCSession?
    
    public override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // MARK: - Send to Phone
    
    public func askPhone(_ prompt: String) {
        guard let session = session, session.isReachable else {
            lastResponse = "iPhone not reachable"
            return
        }
        
        isProcessing = true
        
        session.sendMessage(
            ["action": "ask", "prompt": prompt],
            replyHandler: { [weak self] response in
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    self?.lastResponse = response["response"] as? String
                }
            },
            errorHandler: { [weak self] error in
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    self?.lastResponse = "Error: \(error.localizedDescription)"
                }
            }
        )
    }
    
    // MARK: - Quick Actions
    
    public func quickAction(_ action: String) {
        let prompts: [String: String] = [
            "weather": "What's the weather like?",
            "calendar": "What's on my calendar today?",
            "timer": "Set a 5 minute timer",
            "reminder": "Remind me in 1 hour",
            "translate": "Translate: Hello, how are you?"
        ]
        
        if let prompt = prompts[action] {
            askPhone(prompt)
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
}

// MARK: - Watch UI

import SwiftUI

public struct WatchMainView: View {
    @StateObject private var session = WatchSessionManager.shared
    @State private var inputText = ""
    @State private var isListening = false
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Status
                HStack {
                    Circle()
                        .fill(session.isReachable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(session.isReachable ? "Connected" : "Disconnected")
                        .font(.caption2)
                }
                
                // Voice button
                Button {
                    isListening.toggle()
                    if isListening {
                        // Start dictation
                    }
                } label: {
                    Image(systemName: isListening ? "waveform" : "mic.fill")
                        .font(.title2)
                        .foregroundColor(.cyan)
                }
                .buttonStyle(.bordered)
                
                // Quick actions
                LazyVGrid(columns: [GridItem(), GridItem()], spacing: 8) {
                    QuickActionButton(icon: "sun.max", label: "Weather") {
                        session.quickAction("weather")
                    }
                    QuickActionButton(icon: "calendar", label: "Calendar") {
                        session.quickAction("calendar")
                    }
                    QuickActionButton(icon: "timer", label: "Timer") {
                        session.quickAction("timer")
                    }
                    QuickActionButton(icon: "bell", label: "Remind") {
                        session.quickAction("reminder")
                    }
                }
                
                // Response
                if session.isProcessing {
                    ProgressView()
                } else if let response = session.lastResponse {
                    Text(response)
                        .font(.body)
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Zero Dark")
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
    }
}

#endif

// MARK: - Phone Side Handler

#if os(iOS)
import WatchConnectivity

/// Handles Watch requests on iPhone
public final class WatchRequestHandler: NSObject, WCSessionDelegate {
    
    public static let shared = WatchRequestHandler()
    
    private var session: WCSession?
    
    public override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let action = message["action"] as? String else {
            replyHandler(["error": "Invalid action"])
            return
        }
        
        switch action {
        case "ask":
            guard let prompt = message["prompt"] as? String else {
                replyHandler(["error": "Missing prompt"])
                return
            }
            
            Task {
                let ai = await ZeroDarkAI.shared
                do {
                    let response = try await ai.generate(prompt, stream: false)
                    replyHandler(["response": response])
                } catch {
                    replyHandler(["error": error.localizedDescription])
                }
            }
            
        default:
            replyHandler(["error": "Unknown action"])
        }
    }
}
#endif
