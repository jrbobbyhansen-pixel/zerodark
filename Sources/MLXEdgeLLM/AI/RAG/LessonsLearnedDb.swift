import Foundation
import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
    static let lessonAdded = Notification.Name("ai.zerodark.lessonAdded")
    static let lessonDeleted = Notification.Name("ai.zerodark.lessonDeleted")
}

// MARK: - Lesson Model

struct Lesson: Identifiable, Codable {
    let id: UUID
    let scenario: String
    let topic: String
    let outcome: String
    let details: String
    let tags: [String]
    let timestamp: Date
}

// MARK: - LessonsLearnedDb

class LessonsLearnedDb: ObservableObject {
    @Published private(set) var lessons: [Lesson] = []
    private let fileManager = FileManager.default
    private let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let fileName = "lessonsLearned.json"

    init() {
        loadLessons()
    }

    // MARK: - CRUD Operations

    func addLesson(scenario: String, topic: String, outcome: String, details: String, tags: [String]) {
        let newLesson = Lesson(id: UUID(), scenario: scenario, topic: topic, outcome: outcome, details: details, tags: tags, timestamp: Date())
        lessons.append(newLesson)
        saveLessons()
        NotificationCenter.default.post(name: .lessonAdded, object: newLesson)
    }

    func updateLesson(_ lesson: Lesson, scenario: String, topic: String, outcome: String, details: String, tags: [String]) {
        if let index = lessons.firstIndex(where: { $0.id == lesson.id }) {
            lessons[index] = Lesson(id: lesson.id, scenario: scenario, topic: topic, outcome: outcome, details: details, tags: tags, timestamp: Date())
            saveLessons()
        }
    }

    func deleteLesson(_ lesson: Lesson) {
        lessons.removeAll { $0.id == lesson.id }
        saveLessons()
    }

    // MARK: - Persistence

    private func saveLessons() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(lessons)
            let url = directory.appendingPathComponent(fileName)
            try data.write(to: url)
        } catch {
            print("Failed to save lessons: \(error)")
        }
    }

    private func loadLessons() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = directory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                lessons = try decoder.decode([Lesson].self, from: data)
            } catch {
                print("Failed to load lessons: \(error)")
            }
        }
    }
}

// MARK: - LessonsLearnedView

struct LessonsLearnedView: View {
    @StateObject private var db = LessonsLearnedDb()

    var body: some View {
        NavigationView {
            List(db.lessons) { lesson in
                VStack(alignment: .leading) {
                    Text(lesson.scenario)
                        .font(.headline)
                    Text(lesson.topic)
                        .font(.subheadline)
                    Text(lesson.outcome)
                        .font(.caption)
                }
                .contextMenu {
                    Button(action: {
                        // Edit lesson
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(action: {
                        db.deleteLesson(lesson)
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Lessons Learned")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new lesson
                    }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct LessonsLearnedView_Previews: PreviewProvider {
    static var previews: some View {
        LessonsLearnedView()
    }
}