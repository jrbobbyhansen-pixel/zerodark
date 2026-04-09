import Foundation
import SwiftUI

// MARK: - Announcement Model

struct Announcement: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let priority: Priority
    let scheduledTime: Date
    var isAcknowledged: Bool = false
}

enum Priority: String, Comparable {
    case low
    case medium
    case high
    
    static func < (lhs: Priority, rhs: Priority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - AnnouncementService

class AnnouncementService: ObservableObject {
    @Published private(set) var announcements: [Announcement] = []
    
    func addAnnouncement(_ announcement: Announcement) {
        announcements.append(announcement)
        announcements.sort { $0.priority > $1.priority }
    }
    
    func acknowledgeAnnouncement(_ announcement: Announcement) {
        if let index = announcements.firstIndex(where: { $0.id == announcement.id }) {
            announcements[index].isAcknowledged = true
        }
    }
    
    func removeAcknowledgedAnnouncements() {
        announcements.removeAll { $0.isAcknowledged }
    }
}

// MARK: - AnnouncementView

struct AnnouncementView: View {
    @StateObject private var viewModel = AnnouncementViewModel()
    
    var body: some View {
        VStack {
            List(viewModel.announcements) { announcement in
                AnnouncementRow(announcement: announcement)
                    .onTapGesture {
                        viewModel.acknowledgeAnnouncement(announcement)
                    }
            }
            .listStyle(PlainListStyle())
            
            Button("Remove Acknowledged") {
                viewModel.removeAcknowledgedAnnouncements()
            }
            .padding()
        }
        .navigationTitle("Announcements")
    }
}

// MARK: - AnnouncementRow

struct AnnouncementRow: View {
    let announcement: Announcement
    
    var body: some View {
        HStack {
            Text(announcement.title)
                .font(.headline)
            Spacer()
            Text(announcement.priority.rawValue)
                .font(.subheadline)
                .foregroundColor(announcement.priority.color)
        }
        .padding()
        .background(announcement.isAcknowledged ? Color.gray.opacity(0.2) : Color.clear)
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .low:
            return Color.green
        case .medium:
            return Color.orange
        case .high:
            return Color.red
        }
    }
}

// MARK: - AnnouncementViewModel

class AnnouncementViewModel: ObservableObject {
    @ObservedObject private var announcementService = AnnouncementService()
    
    var announcements: [Announcement] {
        announcementService.announcements
    }
    
    func acknowledgeAnnouncement(_ announcement: Announcement) {
        announcementService.acknowledgeAnnouncement(announcement)
    }
    
    func removeAcknowledgedAnnouncements() {
        announcementService.removeAcknowledgedAnnouncements()
    }
}

// MARK: - Preview

struct AnnouncementView_Previews: PreviewProvider {
    static var previews: some View {
        AnnouncementView()
    }
}