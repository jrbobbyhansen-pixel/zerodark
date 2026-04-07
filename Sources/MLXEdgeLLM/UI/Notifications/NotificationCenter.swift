import SwiftUI
import Foundation

// MARK: - Notification Model

struct Notification: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let priority: NotificationPriority
    let timestamp: Date
    let actions: [NotificationAction]
}

enum NotificationPriority: Int, Comparable {
    case low
    case medium
    case high
    
    static func < (lhs: NotificationPriority, rhs: NotificationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct NotificationAction {
    let title: String
    let handler: () -> Void
}

// MARK: - Notification Center Service

class NotificationCenterService: ObservableObject {
    @Published private(set) var notifications: [Notification] = []
    @Published var doNotDisturb: Bool = false
    
    func addNotification(_ notification: Notification) {
        guard !doNotDisturb else { return }
        notifications.append(notification)
        notifications.sort { $0.priority > $1.priority }
    }
    
    func clearNotifications() {
        notifications = []
    }
    
    func toggleDoNotDisturb() {
        doNotDisturb.toggle()
    }
}

// MARK: - Notification View

struct NotificationView: View {
    @StateObject private var viewModel = NotificationViewModel()
    
    var body: some View {
        VStack {
            Toggle("Do Not Disturb", isOn: $viewModel.doNotDisturb)
                .onChange(of: viewModel.doNotDisturb) { newValue in
                    viewModel.toggleDoNotDisturb()
                }
            
            List(viewModel.notifications) { notification in
                NotificationItemView(notification: notification)
            }
            .onDelete { indexSet in
                viewModel.notifications.remove(atOffsets: indexSet)
            }
        }
        .padding()
    }
}

// MARK: - Notification Item View

struct NotificationItemView: View {
    let notification: Notification
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(notification.title)
                .font(.headline)
            Text(notification.message)
                .font(.subheadline)
            HStack {
                ForEach(notification.actions) { action in
                    Button(action.title) {
                        action.handler()
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Notification View Model

class NotificationViewModel: ObservableObject {
    @Published var notifications: [Notification] = []
    @Published var doNotDisturb: Bool = false
    
    private let service: NotificationCenterService
    
    init(service: NotificationCenterService = NotificationCenterService()) {
        self.service = service
        self.notifications = service.notifications
        self.doNotDisturb = service.doNotDisturb
    }
    
    func addNotification(_ notification: Notification) {
        service.addNotification(notification)
        notifications = service.notifications
    }
    
    func clearNotifications() {
        service.clearNotifications()
        notifications = service.notifications
    }
    
    func toggleDoNotDisturb() {
        service.toggleDoNotDisturb()
        doNotDisturb = service.doNotDisturb
    }
}