import Foundation
import Combine

class WebSocketClient: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var messages: [String] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var url: URL
    private var cancellables = Set<AnyCancellable>()
    
    init(url: URL) {
        self.url = url
        connect()
    }
    
    func connect() {
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.delegate = self
        webSocketTask?.resume()
        isConnected = true
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
    }
    
    func send(message: String) {
        webSocketTask?.send(.string(message)) { error in
            if let error = error {
                print("Error sending message: \(error)")
            }
        }
    }
    
    func send(data: Data) {
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("Error sending data: \(error)")
            }
        }
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket did open with protocol: \(String(describing: protocol))")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket did close with code: \(closeCode) and reason: \(String(data: reason ?? Data(), encoding: .utf8) ?? "")")
        isConnected = false
        // Reconnect after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.connect()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didReceive message: URLSessionWebSocketMessage, completionHandler: @escaping (Error?) -> Void) {
        switch message {
        case .string(let text):
            messages.append(text)
        case .data(let data):
            if let string = String(data: data, encoding: .utf8) {
                messages.append(string)
            }
        @unknown default:
            break
        }
        completionHandler(nil)
    }
}