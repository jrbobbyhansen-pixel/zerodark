import SwiftUI
import Foundation

// MARK: - TeamChat

struct TeamChat: View {
    @StateObject private var viewModel = TeamChatViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.channels, id: \.id) { channel in
                NavigationLink(destination: ChannelView(channel: channel)) {
                    Text(channel.name)
                }
            }
            .navigationTitle("Team Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: viewModel.createChannel) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .environmentObject(viewModel)
    }
}

// MARK: - ChannelView

struct ChannelView: View {
    let channel: Channel
    @StateObject private var viewModel = ChannelViewModel(channel: channel)
    
    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.messages, id: \.id) { message in
                    MessageView(message: message)
                }
            }
            .padding()
            
            HStack {
                TextField("Type a message", text: $viewModel.messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                Button(action: viewModel.sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .padding()
            }
        }
        .navigationTitle(channel.name)
        .onAppear {
            viewModel.fetchMessages()
        }
    }
}

// MARK: - MessageView

struct MessageView: View {
    let message: Message
    
    var body: some View {
        HStack {
            Text(message.sender)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(message.text)
                .padding()
                .background(message.isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                .cornerRadius(10)
                .padding(.trailing, message.isFromCurrentUser ? 0 : 10)
                .padding(.leading, message.isFromCurrentUser ? 10 : 0)
        }
        .frame(maxWidth: .infinity, alignment: message.isFromCurrentUser ? .trailing : .leading)
    }
}

// MARK: - Models

struct Channel: Identifiable {
    let id: UUID
    let name: String
}

struct Message: Identifiable {
    let id: UUID
    let sender: String
    let text: String
    let isFromCurrentUser: Bool
}

// MARK: - View Models

class TeamChatViewModel: ObservableObject {
    @Published var channels: [Channel] = []
    
    func createChannel() {
        let newChannel = Channel(id: UUID(), name: "New Channel")
        channels.append(newChannel)
    }
}

class ChannelViewModel: ObservableObject {
    let channel: Channel
    @Published var messages: [Message] = []
    @Published var messageText: String = ""
    
    init(channel: Channel) {
        self.channel = channel
    }
    
    func fetchMessages() {
        // Simulate fetching messages
        messages = [
            Message(id: UUID(), sender: "Alice", text: "Hello!", isFromCurrentUser: false),
            Message(id: UUID(), sender: "Bob", text: "Hi Alice!", isFromCurrentUser: true)
        ]
    }
    
    func sendMessage() {
        guard !messageText.isEmpty else { return }
        let newMessage = Message(id: UUID(), sender: "CurrentUser", text: messageText, isFromCurrentUser: true)
        messages.append(newMessage)
        messageText = ""
    }
}