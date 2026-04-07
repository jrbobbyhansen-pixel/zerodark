import Foundation
import SwiftUI

// MARK: - Message Model

struct Message: Identifiable {
    let id: UUID
    let content: String
    let status: MessageStatus
    let priority: Int
}

enum MessageStatus {
    case pending
    case sent
    case failed
}

// MARK: - MessageQueueManager

class MessageQueueManager: ObservableObject {
    @Published private(set) var messages: [Message] = []
    
    func addMessage(_ content: String, priority: Int) {
        let newMessage = Message(id: UUID(), content: content, status: .pending, priority: priority)
        messages.append(newMessage)
        messages.sort { $0.priority > $1.priority }
    }
    
    func retryFailedMessages() {
        messages = messages.map { message in
            if message.status == .failed {
                return Message(id: message.id, content: message.content, status: .pending, priority: message.priority)
            }
            return message
        }
    }
    
    func clearDeliveredMessages() {
        messages = messages.filter { $0.status != .sent }
    }
}

// MARK: - MessageQueueView

struct MessageQueueView: View {
    @StateObject private var viewModel = MessageQueueManager()
    
    var body: some View {
        VStack {
            List {
                ForEach(viewModel.messages) { message in
                    HStack {
                        Text(message.content)
                        Spacer()
                        Text(message.status.description)
                            .foregroundColor(message.status.color)
                    }
                }
            }
            
            HStack {
                Button("Retry Failed") {
                    viewModel.retryFailedMessages()
                }
                .buttonStyle(.bordered)
                
                Button("Clear Delivered") {
                    viewModel.clearDeliveredMessages()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Message Queue")
    }
}

// MARK: - MessageStatus Extensions

extension MessageStatus: CustomStringConvertible {
    var description: String {
        switch self {
        case .pending: return "Pending"
        case .sent: return "Sent"
        case .failed: return "Failed"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .yellow
        case .sent: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Preview

struct MessageQueueView_Previews: PreviewProvider {
    static var previews: some View {
        MessageQueueView()
    }
}