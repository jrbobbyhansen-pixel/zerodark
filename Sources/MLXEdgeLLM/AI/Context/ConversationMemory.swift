import Foundation
import SwiftUI

// MARK: - ConversationMemory

class ConversationMemory: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    private let userDefaultsKey = "ConversationMemory"

    init() {
        loadConversations()
    }

    func addMessage(to conversationID: UUID, message: Message) {
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[index].messages.append(message)
            saveConversations()
        }
    }

    func createNewConversation() -> Conversation {
        let newConversation = Conversation(id: UUID(), messages: [])
        conversations.append(newConversation)
        saveConversations()
        return newConversation
    }

    func searchMessages(query: String) -> [Message] {
        return conversations.flatMap { $0.messages.filter { $0.content.lowercased().contains(query.lowercased()) } }
    }

    func summarizeConversation(_ conversation: Conversation) -> String {
        // Placeholder for summarization logic
        return "Summary of conversation \(conversation.id)"
    }

    private func saveConversations() {
        if let encoded = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    private func loadConversations() {
        if let encoded = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: encoded) {
            conversations = decoded
        }
    }
}

// MARK: - Conversation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var messages: [Message]
}

// MARK: - Message

struct Message: Codable {
    let sender: String
    let content: String
    let timestamp: Date = Date()
}

// MARK: - ConversationMemoryView

struct ConversationMemoryView: View {
    @StateObject private var conversationMemory = ConversationMemory()

    var body: some View {
        NavigationView {
            List(conversationMemory.conversations) { conversation in
                NavigationLink(destination: ConversationDetailView(conversation: conversation)) {
                    Text(conversation.messages.last?.content ?? "New Conversation")
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        conversationMemory.createNewConversation()
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - ConversationDetailView

struct ConversationDetailView: View {
    let conversation: Conversation

    var body: some View {
        VStack {
            ForEach(conversation.messages) { message in
                HStack {
                    Text(message.sender)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(message.content)
                }
                .padding()
                .background(message.sender == "User" ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                .cornerRadius(10)
            }
        }
        .navigationTitle("Conversation")
    }
}