import Foundation
import SwiftUI
import Network

class TakClient: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var messages: [String] = []
    
    private var networkMonitor: NWPathMonitor
    private var connection: NWConnection?
    private var messageQueue: [String] = []
    
    init() {
        networkMonitor = NWPathMonitor()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.connectToTAKServer()
            } else {
                self?.disconnectFromTAKServer()
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
    }
    
    deinit {
        networkMonitor.cancel()
        disconnectFromTAKServer()
    }
    
    private func connectToTAKServer() {
        guard !isConnected else { return }
        
        let host = "takserver.example.com"
        let port = 8080
        let endpoint = NWEndpoint.hostPort(host: host, port: .init(integerLiteral: port))
        connection = NWConnection(to: endpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.sendQueuedMessages()
            case .failed, .cancelled:
                self?.isConnected = false
                self?.connection?.cancel()
                self?.connection = nil
            default:
                break
            }
        }
        
        connection?.start(queue: DispatchQueue.global())
    }
    
    private func disconnectFromTAKServer() {
        isConnected = false
        connection?.cancel()
        connection = nil
    }
    
    func sendMessage(_ message: String) {
        if isConnected {
            connection?.send(content: message.data(using: .utf8), completion: .contentProcessed { error in
                if let error = error {
                    print("Failed to send message: \(error)")
                }
            })
        } else {
            messageQueue.append(message)
        }
    }
    
    private func sendQueuedMessages() {
        for message in messageQueue {
            sendMessage(message)
        }
        messageQueue.removeAll()
    }
    
    func receiveMessage(_ message: String) {
        messages.append(message)
    }
}