import Foundation
import SwiftUI

// MARK: - Context Compression

struct ContextCompression {
    enum Mode {
        case lossy
        case lossless
    }
    
    func compress(_ conversation: [Message], mode: Mode) -> String {
        switch mode {
        case .lossy:
            return compressLossy(conversation)
        case .lossless:
            return compressLossless(conversation)
        }
    }
    
    private func compressLossy(_ conversation: [Message]) -> String {
        // Implement lossy compression logic
        // Example: Extract key points and summarize
        var summary = ""
        for message in conversation {
            if message.isCritical {
                summary += "\(message.sender): \(message.text)\n"
            }
        }
        return summary
    }
    
    private func compressLossless(_ conversation: [Message]) -> String {
        // Implement lossless compression logic
        // Example: Concatenate all messages
        return conversation.map { "\(message.sender): \(message.text)" }.joined(separator: "\n")
    }
}

// MARK: - Message Model

struct Message {
    let sender: String
    let text: String
    let isCritical: Bool
}

// MARK: - SwiftUI View

struct ContextCompressorView: View {
    @StateObject private var viewModel = ContextCompressorViewModel()
    
    var body: some View {
        VStack {
            Text("Conversation History")
                .font(.headline)
            
            ScrollView {
                ForEach(viewModel.conversation, id: \.self) { message in
                    Text("\(message.sender): \(message.text)")
                        .padding()
                        .background(message.isCritical ? Color.yellow : Color.white)
                        .cornerRadius(8)
                }
            }
            
            Button("Compress Context") {
                viewModel.compressContext()
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
    }
}

// MARK: - View Model

class ContextCompressorViewModel: ObservableObject {
    @Published var conversation: [Message] = [
        Message(sender: "Alice", text: "Hey, what's up?", isCritical: false),
        Message(sender: "Bob", text: "Not much, just working on the project.", isCritical: false),
        Message(sender: "Alice", text: "Great! Let's sync up later.", isCritical: true)
    ]
    
    func compressContext() {
        let compressor = ContextCompression()
        let compressedText = compressor.compress(conversation, mode: .lossy)
        print("Compressed Context:\n\(compressedText)")
    }
}