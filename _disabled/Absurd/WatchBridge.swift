// WatchBridge.swift
// AI on your wrist
// ABSURD MODE

import Foundation
import SwiftUI

// MARK: - Watch Quick Action (Available everywhere)

public struct WatchQuickAction: Identifiable, Sendable {
    public let id = UUID()
    public let icon: String
    public let label: String
    public let command: String
    
    public init(icon: String, label: String, command: String) {
        self.icon = icon
        self.label = label
        self.command = command
    }
    
    public static let defaults: [WatchQuickAction] = [
        WatchQuickAction(icon: "sun.horizon", label: "Morning", command: "morning routine"),
        WatchQuickAction(icon: "calendar", label: "Calendar", command: "what's on my calendar today"),
        WatchQuickAction(icon: "sparkles", label: "Suggest", command: "suggest"),
        WatchQuickAction(icon: "message", label: "Summarize", command: "summarize my unread emails"),
        WatchQuickAction(icon: "heart", label: "Health", command: "how active was I today"),
        WatchQuickAction(icon: "moon", label: "Evening", command: "evening routine")
    ]
}

// MARK: - Complication Data

public struct ComplicationData: Sendable {
    public let agentEmoji: String
    public let pendingSuggestions: Int
    public let shortStatus: String
    
    public init(agentEmoji: String, pendingSuggestions: Int, shortStatus: String) {
        self.agentEmoji = agentEmoji
        self.pendingSuggestions = pendingSuggestions
        self.shortStatus = shortStatus
    }
}

// MARK: - Watch Connectivity

#if os(watchOS) || os(iOS)
import WatchConnectivity

public actor WatchBridge: NSObject {
    
    public static let shared = WatchBridge()
    
    private var session: WCSession?
    private var pendingCommands: [(String, (String) -> Void)] = []
    
    private override init() {
        super.init()
    }
    
    /// Initialize watch connectivity
    public func activate() {
        guard WCSession.isSupported() else { return }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    /// Send a command to the phone (from watch)
    public func sendCommand(_ command: String) async throws -> String {
        guard let session = session, session.isReachable else {
            throw WatchError.notReachable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(["command": command], replyHandler: { reply in
                if let response = reply["response"] as? String {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: WatchError.invalidResponse)
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
    
    /// Send data to watch (from phone)
    public func sendToWatch(_ data: [String: Any]) async throws {
        guard let session = session, session.isReachable else {
            throw WatchError.notReachable
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.sendMessage(data, replyHandler: { _ in
                continuation.resume()
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
    
    /// Update complications
    public func updateComplications(data: ComplicationData) async {
        guard let session = session else { return }
        
        let context: [String: Any] = [
            "agentEmoji": data.agentEmoji,
            "pendingSuggestions": data.pendingSuggestions,
            "lastUpdate": Date()
        ]
        
        do {
            try session.updateApplicationContext(context)
        } catch {
            print("Failed to update complications: \(error)")
        }
    }
    
    public enum WatchError: Error {
        case notReachable
        case invalidResponse
        case sessionNotActive
    }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("Watch session activated: \(activationState.rawValue)")
    }
    
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task {
            if let command = message["command"] as? String {
                let response = await handleCommand(command)
                replyHandler(["response": response])
            }
        }
    }
    
    private func handleCommand(_ command: String) async -> String {
        // Process commands from watch
        let lower = command.lowercased()
        
        // Quick commands
        if lower == "status" {
            let identity = await AgentIdentity.shared.getIdentity()
            return "\(identity.name) is ready!"
        }
        
        if lower.contains("morning") {
            do {
                let result = try await RoutineEngine.shared.runRoutineByPhrase("morning") { _, _, _ in }
                return result.success ? "Morning routine complete!" : "Routine had issues"
            } catch {
                return "Couldn't run routine"
            }
        }
        
        if lower.contains("suggest") {
            let suggestions = await ProactiveIntelligence.shared.generateSuggestions()
            if let first = suggestions.first {
                return first.title
            }
            return "No suggestions right now"
        }
        
        // Default: send to AI
        let ai = await ZeroDarkAI.shared
        do {
            let response = try await ai.process(prompt: command, onToken: { _ in })
            // Truncate for watch
            return String(response.prefix(200))
        } catch {
            return "Error processing request"
        }
    }
}

#else

// macOS stub for WatchBridge
public actor WatchBridge {
    public static let shared = WatchBridge()
    private init() {}
    
    public func activate() {}
    public func sendCommand(_ command: String) async throws -> String { return "" }
    public func updateComplications(data: ComplicationData) async {}
    
    public enum WatchError: Error {
        case notReachable
        case invalidResponse
        case sessionNotActive
    }
}

#endif

// MARK: - Watch UI Views

public struct WatchHomeView: View {
    @State private var isProcessing = false
    @State private var response = ""
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Agent header
                HStack {
                    Text("🤖")
                        .font(.title)
                    Text("Zero Dark")
                        .font(.headline)
                }
                
                // Quick actions
                LazyVGrid(columns: [GridItem(), GridItem()], spacing: 8) {
                    ForEach(WatchQuickAction.defaults) { action in
                        WatchActionButton(action: action) {
                            executeAction(action)
                        }
                    }
                }
                
                // Response area
                if isProcessing {
                    ProgressView()
                        .padding()
                }
                
                if !response.isEmpty {
                    Text(response)
                        .font(.caption)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    private func executeAction(_ action: WatchQuickAction) {
        isProcessing = true
        response = "Processing \(action.label)..."
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            response = "\(action.label) completed!"
            isProcessing = false
        }
    }
}

struct WatchActionButton: View {
    let action: WatchQuickAction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.title3)
                Text(action.label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.cyan.opacity(0.2))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

public struct WatchVoiceView: View {
    @State private var isListening = false
    @State private var transcript = ""
    @State private var response = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Mic button
            Button {
                isListening.toggle()
            } label: {
                Image(systemName: isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(isListening ? .red : .cyan)
            }
            .buttonStyle(.plain)
            
            if !transcript.isEmpty {
                Text(transcript)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            if !response.isEmpty {
                Text(response)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

#Preview {
    WatchHomeView()
}
