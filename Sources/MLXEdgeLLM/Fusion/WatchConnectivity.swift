// WatchConnectivity.swift — Apple Watch Companion Integration

import Foundation
import WatchConnectivity
import Combine

// MARK: - Watch Session Manager

final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()
    
    @Published var isReachable = false
    @Published var isWatchPaired = false
    @Published var isWatchAppInstalled = false
    @Published var lastReceivedQuery: String?
    @Published var pendingResponse: String?
    
    private var session: WCSession?
    private var cancellables = Set<AnyCancellable>()
    
    override private init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // MARK: - Send to Watch
    
    func sendResponse(_ response: String) {
        guard let session = session, session.isReachable else {
            pendingResponse = response
            return
        }
        
        let message: [String: Any] = [
            "type": "response",
            "text": response,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("[Watch] Send error: \(error)")
        }
    }
    
    func sendStatus(modelName: String, memoryCount: Int, meshPeers: Int) {
        guard let session = session, session.isReachable else { return }
        
        let message: [String: Any] = [
            "type": "status",
            "model": modelName,
            "memories": memoryCount,
            "meshPeers": meshPeers
        ]
        
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
    
    func sendQuickResponse(_ text: String) {
        // Send a short response optimized for Watch display
        let truncated = String(text.prefix(200))
        sendResponse(truncated)
    }
    
    // MARK: - Complication Data
    
    func updateComplication() {
        guard let session = session else { return }

        Task { @MainActor in
            let data: [String: Any] = [
                "isActive": true,
                "model": "ZeroDark Tactical",
                "lastUpdate": Date().timeIntervalSince1970
            ]

            do {
                try session.updateApplicationContext(data)
            } catch {
                print("[Watch] Complication update error: \(error)")
            }
        }
    }
    
    // MARK: - Handle Watch Request
    
    private func handleWatchQuery(_ query: String, replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            lastReceivedQuery = query

            // Process query (tactical system, LLM removed)
            let response = "Tactical: '\(query)'"

            // Send response
            let reply: [String: Any] = [
                "type": "response",
                "text": response,
                "success": true
            ]
            replyHandler(reply)
        }
    }
}

// MARK: - WCSession Delegate

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        // Handle session becoming inactive
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate session
        session.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let type = message["type"] as? String else {
            replyHandler(["error": "Missing type"])
            return
        }
        
        switch type {
        case "query":
            if let query = message["text"] as? String {
                handleWatchQuery(query, replyHandler: replyHandler)
            }
            
        case "status_request":
            // Send current status with real data
            Task { @MainActor in
                let meshPeerCount = MeshService.shared.peers.count

                let status: [String: Any] = [
                    "type": "status",
                    "model": "ZeroDark Tactical",
                    "isActive": true,
                    "memories": 0,
                    "meshPeers": meshPeerCount
                ]
                replyHandler(status)
            }
            
        case "sos":
            // Handle SOS from Watch
            Task { @MainActor in
                await MeshService.shared.broadcastSOS()
            }
            replyHandler(["success": true])
            
        default:
            replyHandler(["error": "Unknown type"])
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Handle messages that don't need a reply
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "ping":
            // Watch is checking connectivity
            Task { @MainActor in
                let meshPeerCount = MeshService.shared.peers.count
                sendStatus(modelName: "ZeroDark Tactical", memoryCount: 0, meshPeers: meshPeerCount)
            }
            
        case "note":
            // Quick note from Watch (LLM removed - not processing)
            if let note = message["text"] as? String {
                print("[Watch] Note received: \(note)")
            }
            
        default:
            break
        }
    }
}

// MARK: - Watch App Message Types

enum WatchMessageType: String, Codable {
    case query
    case response
    case status
    case statusRequest = "status_request"
    case sos
    case note
    case ping
}

struct WatchMessage: Codable {
    let type: WatchMessageType
    let text: String?
    let timestamp: Date
    let metadata: [String: String]?
}

// MARK: - Watch Complication Data

struct WatchComplicationData: Codable {
    let isActive: Bool
    let modelName: String
    let memoryCount: Int
    let meshPeerCount: Int
    let lastQueryTime: Date?
    
    static var placeholder: WatchComplicationData {
        WatchComplicationData(
            isActive: true,
            modelName: "ZeroDark",
            memoryCount: 0,
            meshPeerCount: 0,
            lastQueryTime: nil
        )
    }
}

// MARK: - Watch Integration View

struct WatchIntegrationView: View {
    @ObservedObject var watchManager = WatchSessionManager.shared
    
    var body: some View {
        List {
            Section("Watch Status") {
                HStack {
                    Text("Paired")
                    Spacer()
                    Image(systemName: watchManager.isWatchPaired ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(watchManager.isWatchPaired ? .green : .secondary)
                }
                
                HStack {
                    Text("App Installed")
                    Spacer()
                    Image(systemName: watchManager.isWatchAppInstalled ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(watchManager.isWatchAppInstalled ? .green : .secondary)
                }
                
                HStack {
                    Text("Reachable")
                    Spacer()
                    Image(systemName: watchManager.isReachable ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(watchManager.isReachable ? .green : .secondary)
                }
            }
            
            if let lastQuery = watchManager.lastReceivedQuery {
                Section("Last Watch Query") {
                    Text(lastQuery)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button("Update Complication") {
                    watchManager.updateComplication()
                }
                
                Button("Send Test Status") {
                    watchManager.sendStatus(
                        modelName: "Qwen3 8B",
                        memoryCount: 47,
                        meshPeers: 2
                    )
                }
            }
        }
        .navigationTitle("Apple Watch")
    }
}

import SwiftUI
