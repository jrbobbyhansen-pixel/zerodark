import Foundation
import SwiftUI
import Combine

// MARK: - TAK Chat Message

struct TakChatMessage: Identifiable, Codable {
    let id: UUID
    let sender: String
    let content: String
    let timestamp: Date
    let isGroupMessage: Bool
}

// MARK: - TAK Chat Service

class TakChatService: ObservableObject {
    @Published private(set) var messages: [TakChatMessage] = []
    private var cancellables = Set<AnyCancellable>()
    private let offlineQueue = PassthroughSubject<TakChatMessage, Never>()
    
    init() {
        offlineQueue.sink { [weak self] message in
            self?.enqueueMessage(message)
        }.store(in: &cancellables)
    }
    
    func sendMessage(_ message: TakChatMessage) {
        if isConnectedToTAKServer() {
            // Simulate sending message to TAK server
            messages.append(message)
        } else {
            // Queue message for offline sending
            offlineQueue.send(message)
        }
    }
    
    func receiveMessage(_ message: TakChatMessage) {
        messages.append(message)
    }
    
    private func enqueueMessage(_ message: TakChatMessage) {
        // Implement offline queueing logic
        // For example, save to Core Data or UserDefaults
    }
    
    private func isConnectedToTAKServer() -> Bool {
        // Implement connectivity check
        return true
    }
}

// MARK: - TAK Chat View Model

class TakChatViewModel: ObservableObject {
    @Published var chatService: TakChatService
    @Published var newMessageContent: String = ""
    
    init(chatService: TakChatService) {
        self.chatService = chatService
    }
    
    func sendMessage() {
        guard !newMessageContent.isEmpty else { return }
        let message = TakChatMessage(id: UUID(), sender: "User", content: newMessageContent, timestamp: Date(), isGroupMessage: false)
        chatService.sendMessage(message)
        newMessageContent = ""
    }
}

// MARK: - TAK Chat View

struct TakChatView: View {
    @StateObject private var viewModel: TakChatViewModel
    
    init(chatService: TakChatService) {
        _viewModel = StateObject(wrappedValue: TakChatViewModel(chatService: chatService))
    }
    
    var body: some View {
        VStack {
            List(viewModel.chatService.messages) { message in
                HStack {
                    Text(message.sender)
                        .font(.headline)
                    Spacer()
                    Text(message.content)
                        .font(.body)
                }
                .padding()
            }
            
            HStack {
                TextField("Type a message...", text: $viewModel.newMessageContent)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                Button(action: viewModel.sendMessage) {
                    Text("Send")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .navigationTitle("TAK Chat")
    }
}

// MARK: - Preview

struct TakChatView_Previews: PreviewProvider {
    static var previews: some View {
        TakChatView(chatService: TakChatService())
    }
}