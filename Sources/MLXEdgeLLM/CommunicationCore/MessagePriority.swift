import Foundation

// MARK: - MessagePriority

enum MessagePriority: Int, Comparable {
    case low
    case normal
    case high
    case emergency
    
    static func < (lhs: MessagePriority, rhs: MessagePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Message

struct Message {
    let id: UUID
    let content: String
    let priority: MessagePriority
    let timestamp: Date
    
    init(content: String, priority: MessagePriority) {
        self.id = UUID()
        self.content = content
        self.priority = priority
        self.timestamp = Date()
    }
}

// MARK: - MessagePriorityQueue

class MessagePriorityQueue: ObservableObject {
    @Published private(set) var messages: [Message] = []
    
    func enqueue(_ message: Message) {
        messages.append(message)
        messages.sort { $0.priority > $1.priority || ($0.priority == $1.priority && $0.timestamp < $1.timestamp) }
    }
    
    func dequeue() -> Message? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }
    
    func peek() -> Message? {
        return messages.first
    }
    
    func clear() {
        messages.removeAll()
    }
}

// MARK: - Example Usage

// @main
// struct MessagePriorityQueueExample: App {
//     @StateObject private var queue = MessagePriorityQueue()
//     
//     var body: some Scene {
//         WindowGroup {
//             VStack {
//                 Button("Enqueue Normal Message") {
//                     queue.enqueue(Message(content: "Normal message", priority: .normal))
//                 }
//                 Button("Enqueue High Priority Message") {
//                     queue.enqueue(Message(content: "High priority message", priority: .high))
//                 }
//                 Button("Enqueue Emergency Message") {
//                     queue.enqueue(Message(content: "Emergency message", priority: .emergency))
//                 }
//                 Button("Dequeue Message") {
//                     if let message = queue.dequeue() {
//                         print("Dequeued: \(message.content)")
//                     }
//                 }
//                 Button("Clear Queue") {
//                     queue.clear()
//                 }
//             }
//         }
//     }
// }