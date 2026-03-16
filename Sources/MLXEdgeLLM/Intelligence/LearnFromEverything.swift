//
//  LearnFromEverything.swift
//  ZeroDark
//
//  Memory doesn't just learn from chat — it learns from your ENTIRE digital life.
//  Passive intelligence gathering from all sources.
//

import SwiftUI
import Foundation
import Photos
import EventKit
import Contacts
import CoreLocation
import HealthKit
import MediaPlayer
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: UNIVERSAL LEARNING ENGINE
// MARK: ═══════════════════════════════════════════════════════════════════

@MainActor
class UniversalLearningEngine: ObservableObject {
    static let shared = UniversalLearningEngine()
    
    // Sub-learners
    let fileLearner = FileLearner()
    let webLearner = WebLearner()
    let calendarLearner = CalendarLearner()
    let contactsLearner = ContactsLearner()
    let photoLearner = PhotoLearner()
    let healthLearner = HealthLearner()
    let locationLearner = LocationLearner()
    let screenLearner = ScreenLearner()
    let clipboardLearner = ClipboardLearner()
    let appUsageLearner = AppUsageLearner()
    let voiceLearner = VoiceLearner()
    let musicLearner = MusicLearner()
    
    // Stats
    @Published var totalSourcesLearned = 0
    @Published var lastLearnTime: Date?
    @Published var isLearning = false
    @Published var learningLog: [LearningEvent] = []
    
    // Memory reference
    private let memory = InfiniteMemorySystem.shared
    
    struct LearningEvent: Identifiable {
        let id = UUID()
        let source: String
        let type: LearningType
        let factsExtracted: Int
        let timestamp: Date
    }
    
    enum LearningType: String {
        case file = "📄"
        case web = "🌐"
        case calendar = "📅"
        case contact = "👤"
        case photo = "📸"
        case health = "❤️"
        case location = "📍"
        case screen = "🖥️"
        case clipboard = "📋"
        case app = "📱"
        case voice = "🎤"
        case music = "🎵"
        case chat = "💬"
    }
    
    /// Learn from all sources
    func learnFromEverything() async {
        isLearning = true
        defer { isLearning = false }
        
        // Run all learners in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fileLearner.learn() }
            group.addTask { await self.webLearner.learn() }
            group.addTask { await self.calendarLearner.learn() }
            group.addTask { await self.contactsLearner.learn() }
            group.addTask { await self.photoLearner.learn() }
            group.addTask { await self.healthLearner.learn() }
            group.addTask { await self.locationLearner.learn() }
            group.addTask { await self.clipboardLearner.learn() }
            group.addTask { await self.appUsageLearner.learn() }
            group.addTask { await self.musicLearner.learn() }
        }
        
        lastLearnTime = Date()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 1. FILE LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from files you create, open, edit
class FileLearner: ObservableObject {
    @Published var filesLearned = 0
    @Published var lastFile: String?
    
    private let memory = InfiniteMemorySystem.shared
    private let supportedTypes: Set<String> = ["swift", "py", "js", "ts", "md", "txt", "json", "yaml", "html", "css"]
    
    /// Watch a directory for changes
    func watchDirectory(_ url: URL) async {
        // Would use DispatchSource.makeFileSystemObjectSource
        // For now, scan directory
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )
        
        for file in contents ?? [] {
            if supportedTypes.contains(file.pathExtension.lowercased()) {
                await learnFromFile(file)
            }
        }
    }
    
    /// Learn from a specific file
    func learnFromFile(_ url: URL) async {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        let facts = await extractFactsFromCode(content, filename: url.lastPathComponent)
        
        for fact in facts {
            await memory.processConversation(messages: [
                (role: "system", content: "Learning from file: \(url.lastPathComponent)"),
                (role: "file", content: fact)
            ])
        }
        
        filesLearned += 1
        lastFile = url.lastPathComponent
    }
    
    /// Learn from opened document (integrate with NSDocument)
    func learnFromOpenedDocument(title: String, content: String, app: String) async {
        await memory.processConversation(messages: [
            (role: "system", content: "User opened '\(title)' in \(app)"),
            (role: "document", content: content.prefix(5000).description)
        ])
    }
    
    private func extractFactsFromCode(_ code: String, filename: String) async -> [String] {
        var facts: [String] = []
        
        // Extract imports/dependencies
        let importPatterns = [
            "import (\\w+)",           // Swift/Python
            "require\\(['\"](.+)['\"]\\)", // Node
            "from ['\"](.+)['\"]"      // ESM
        ]
        
        for pattern in importPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: code, range: NSRange(code.startIndex..., in: code))
                for match in matches.prefix(10) {
                    if let range = Range(match.range(at: 1), in: code) {
                        facts.append("Uses dependency: \(code[range])")
                    }
                }
            }
        }
        
        // Extract function/class names
        let declPatterns = [
            "func (\\w+)",             // Swift
            "class (\\w+)",            // Swift/Python
            "struct (\\w+)",           // Swift
            "def (\\w+)",              // Python
            "function (\\w+)",         // JS
            "const (\\w+) = \\("       // Arrow functions
        ]
        
        for pattern in declPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: code, range: NSRange(code.startIndex..., in: code))
                for match in matches.prefix(20) {
                    if let range = Range(match.range(at: 1), in: code) {
                        facts.append("Defines: \(code[range])")
                    }
                }
            }
        }
        
        // Extract comments/docs
        let commentPatterns = [
            "/// (.+)",                // Swift docs
            "// TODO: (.+)",           // TODOs
            "// MARK: (.+)",           // Sections
            "# (.+)",                  // Python comments
            "\\/\\*\\*([^*]+)\\*\\/"   // Block docs
        ]
        
        for pattern in commentPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: code, range: NSRange(code.startIndex..., in: code))
                for match in matches.prefix(10) {
                    if let range = Range(match.range(at: 1), in: code) {
                        facts.append("Note: \(code[range].trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        
        return facts
    }
    
    func learn() async {
        // Learn from common directories
        let home = FileManager.default.homeDirectoryForCurrentUser
        await watchDirectory(home.appendingPathComponent("Documents"))
        await watchDirectory(home.appendingPathComponent("Developer"))
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 2. WEB LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from websites you visit, articles you read
class WebLearner: ObservableObject {
    @Published var pagesLearned = 0
    @Published var lastURL: String?
    
    private let memory = InfiniteMemorySystem.shared
    
    /// Learn from a visited URL
    func learnFromURL(_ url: URL, title: String, content: String) async {
        // Summarize the content
        let summary = await summarize(content)
        
        // Extract key facts
        let topics = await extractTopics(content)
        
        await memory.processConversation(messages: [
            (role: "system", content: "User visited: \(title) (\(url.host ?? ""))"),
            (role: "webpage", content: "Summary: \(summary)\nTopics: \(topics.joined(separator: ", "))")
        ])
        
        pagesLearned += 1
        lastURL = url.absoluteString
    }
    
    /// Learn from Safari history (requires permission)
    func learnFromBrowserHistory() async {
        // Would integrate with Safari/Chrome history APIs
        // For now, placeholder
    }
    
    /// Learn from bookmarks
    func learnFromBookmarks(_ bookmarks: [(title: String, url: URL)]) async {
        for bookmark in bookmarks {
            await memory.processConversation(messages: [
                (role: "system", content: "User bookmarked: \(bookmark.title)"),
                (role: "bookmark", content: "URL: \(bookmark.url.absoluteString)")
            ])
        }
    }
    
    private func summarize(_ text: String) async -> String {
        // Would call model
        return String(text.prefix(200))
    }
    
    private func extractTopics(_ text: String) async -> [String] {
        // Would use NLP
        return ["topic1", "topic2"]
    }
    
    func learn() async {
        await learnFromBrowserHistory()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 3. CALENDAR LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from calendar events, meetings, schedules
class CalendarLearner: ObservableObject {
    @Published var eventsLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    private let eventStore = EKEventStore()
    
    /// Learn from upcoming events
    func learnFromCalendar() async {
        // Request access
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else { return }
        } catch { return }
        
        // Get events for next 30 days
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 30, to: start)!
        
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        for event in events {
            await learnFromEvent(event)
        }
    }
    
    private func learnFromEvent(_ event: EKEvent) async {
        var facts: [String] = []
        
        facts.append("Event: \(event.title ?? "Untitled") on \(formatDate(event.startDate))")
        
        if let location = event.location, !location.isEmpty {
            facts.append("Location: \(location)")
        }
        
        if let notes = event.notes, !notes.isEmpty {
            facts.append("Notes: \(notes.prefix(200))")
        }
        
        if let attendees = event.attendees {
            let names = attendees.compactMap { $0.name }.prefix(5)
            if !names.isEmpty {
                facts.append("Attendees: \(names.joined(separator: ", "))")
            }
        }
        
        // Learn patterns
        if event.isAllDay {
            facts.append("Pattern: All-day event")
        }
        
        if let recurrence = event.recurrenceRules?.first {
            facts.append("Pattern: Recurring \(recurrence.frequency.rawValue)")
        }
        
        await memory.processConversation(messages: [
            (role: "system", content: "Calendar event"),
            (role: "calendar", content: facts.joined(separator: "\n"))
        ])
        
        eventsLearned += 1
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func learn() async {
        await learnFromCalendar()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 4. CONTACTS LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from contacts — who you know, relationships
class ContactsLearner: ObservableObject {
    @Published var contactsLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    private let store = CNContactStore()
    
    /// Learn from contacts
    func learnFromContacts() async {
        // Request access
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else { return }
        } catch { return }
        
        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactJobTitleKey,
            CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey,
            CNContactNoteKey,
            CNContactRelationsKey
        ] as [CNKeyDescriptor]
        
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                Task { await self.learnFromContact(contact) }
            }
        } catch {}
    }
    
    private func learnFromContact(_ contact: CNContact) async {
        var facts: [String] = []
        
        let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        facts.append("Contact: \(name)")
        
        if !contact.organizationName.isEmpty {
            facts.append("Works at: \(contact.organizationName)")
        }
        
        if !contact.jobTitle.isEmpty {
            facts.append("Role: \(contact.jobTitle)")
        }
        
        if let note = contact.note as String?, !note.isEmpty {
            facts.append("Notes: \(note.prefix(200))")
        }
        
        for relation in contact.contactRelations {
            facts.append("Relationship: \(relation.label ?? "related") - \(relation.value.name)")
        }
        
        await memory.processConversation(messages: [
            (role: "system", content: "Contact information"),
            (role: "contact", content: facts.joined(separator: "\n"))
        ])
        
        contactsLearned += 1
    }
    
    func learn() async {
        await learnFromContacts()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 5. PHOTO LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from photos — places, people, objects, events
class PhotoLearner: ObservableObject {
    @Published var photosLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    
    /// Learn from recent photos
    func learnFromPhotos() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else { return }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 100
        
        let results = PHAsset.fetchAssets(with: .image, options: options)
        
        results.enumerateObjects { asset, _, _ in
            Task { await self.learnFromPhoto(asset) }
        }
    }
    
    private func learnFromPhoto(_ asset: PHAsset) async {
        var facts: [String] = []
        
        // Date
        if let date = asset.creationDate {
            facts.append("Photo taken: \(formatDate(date))")
        }
        
        // Location
        if let location = asset.location {
            let geocoder = CLGeocoder()
            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                let place = [placemark.locality, placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                facts.append("Location: \(place)")
            }
        }
        
        // Would use Vision for:
        // - Face detection/recognition
        // - Object detection
        // - Scene classification
        // - Text in image (OCR)
        
        if !facts.isEmpty {
            await memory.processConversation(messages: [
                (role: "system", content: "Photo metadata"),
                (role: "photo", content: facts.joined(separator: "\n"))
            ])
            
            photosLearned += 1
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    func learn() async {
        await learnFromPhotos()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 6. HEALTH LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from health data — patterns, energy, sleep
class HealthLearner: ObservableObject {
    @Published var patternsLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    private let healthStore = HKHealthStore()
    
    /// Learn from health patterns
    func learnFromHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        // Request read access for key types
        let types: Set<HKSampleType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned)
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: types)
        } catch { return }
        
        // Analyze patterns
        await learnSleepPatterns()
        await learnActivityPatterns()
        await learnEnergyPatterns()
    }
    
    private func learnSleepPatterns() async {
        // Would query sleep data and extract patterns
        // e.g., "User typically sleeps 11pm-7am"
        // "Sleep quality drops on Sunday nights"
    }
    
    private func learnActivityPatterns() async {
        // Would query step/activity data
        // e.g., "Most active on Tuesdays"
        // "Takes walk around 2pm daily"
    }
    
    private func learnEnergyPatterns() async {
        // Would correlate active energy with time of day
        // e.g., "Peak energy 9-11am"
    }
    
    func learn() async {
        await learnFromHealth()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 7. LOCATION LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from locations — home, work, frequent places
class LocationLearner: ObservableObject {
    @Published var placesLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    private let locationManager = CLLocationManager()
    
    /// Learn significant locations
    func learnFromLocations() async {
        // Would use CLLocationManager.significantLocationChangeMonitoring
        // And analyze patterns over time
        
        // Learn:
        // - Home location (most time spent overnight)
        // - Work location (most time spent 9-5)
        // - Frequent places (gym, coffee shop, etc.)
        // - Travel patterns (commute route, travel destinations)
    }
    
    /// Learn from a visit
    func learnFromVisit(place: String, duration: TimeInterval, time: Date) async {
        let facts = [
            "Visited: \(place)",
            "Duration: \(Int(duration / 60)) minutes",
            "Time: \(formatTime(time))"
        ]
        
        await memory.processConversation(messages: [
            (role: "system", content: "Location visit"),
            (role: "location", content: facts.joined(separator: "\n"))
        ])
        
        placesLearned += 1
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func learn() async {
        await learnFromLocations()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 8. SCREEN LEARNER (macOS)
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from screen activity — workflows, habits
class ScreenLearner: ObservableObject {
    @Published var screensLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    
    /// Learn from screen recording/OCR
    func learnFromScreen() async {
        // Requires Screen Recording permission
        // Would use CGWindowListCopyWindowInfo + Vision OCR
        
        // Learn:
        // - App switching patterns
        // - Frequent workflows
        // - Content being worked on
    }
    
    /// Learn from active window changes
    func learnFromActiveWindow(app: String, title: String) async {
        await memory.processConversation(messages: [
            (role: "system", content: "Active window change"),
            (role: "screen", content: "App: \(app)\nWindow: \(title)")
        ])
    }
    
    func learn() async {
        await learnFromScreen()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 9. CLIPBOARD LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from clipboard — what you copy
class ClipboardLearner: ObservableObject {
    @Published var clipsLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    private var lastClipboard: String?
    
    #if os(macOS)
    /// Watch clipboard for changes
    func watchClipboard() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let pasteboard = NSPasteboard.general
            guard let content = pasteboard.string(forType: .string),
                  content != self.lastClipboard else { return }
            
            self.lastClipboard = content
            Task { await self.learnFromClip(content) }
        }
    }
    #endif
    
    private func learnFromClip(_ content: String) async {
        // Don't learn passwords or sensitive data
        if looksLikeSensitive(content) { return }
        
        await memory.processConversation(messages: [
            (role: "system", content: "User copied text"),
            (role: "clipboard", content: String(content.prefix(500)))
        ])
        
        clipsLearned += 1
    }
    
    private func looksLikeSensitive(_ text: String) -> Bool {
        // Check for password-like patterns, API keys, etc.
        let sensitivePatterns = [
            "password",
            "secret",
            "api_key",
            "apikey",
            "token",
            "bearer",
            "\\b[A-Za-z0-9]{32,}\\b"  // Long random strings
        ]
        
        for pattern in sensitivePatterns {
            if text.lowercased().contains(pattern) {
                return true
            }
        }
        return false
    }
    
    func learn() async {
        #if os(macOS)
        watchClipboard()
        #endif
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 10. APP USAGE LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from app usage patterns
class AppUsageLearner: ObservableObject {
    @Published var appsLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    
    /// Learn from Screen Time data (iOS)
    func learnFromScreenTime() async {
        // Would use DeviceActivity framework
        // Learn:
        // - Most used apps
        // - Usage patterns by time of day
        // - Categories of app usage
    }
    
    /// Learn from app launch
    func learnFromAppLaunch(app: String, time: Date) async {
        await memory.processConversation(messages: [
            (role: "system", content: "App launched"),
            (role: "app", content: "App: \(app) at \(formatTime(time))")
        ])
        appsLearned += 1
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func learn() async {
        await learnFromScreenTime()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 11. VOICE LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from voice notes, transcriptions
class VoiceLearner: ObservableObject {
    @Published var notesLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    
    /// Learn from voice note transcription
    func learnFromVoiceNote(transcription: String, duration: TimeInterval) async {
        await memory.processConversation(messages: [
            (role: "system", content: "Voice note (\(Int(duration))s)"),
            (role: "voice", content: transcription)
        ])
        notesLearned += 1
    }
    
    /// Learn from Siri interaction
    func learnFromSiriQuery(query: String, response: String) async {
        await memory.processConversation(messages: [
            (role: "user", content: "Siri: \(query)"),
            (role: "siri", content: response)
        ])
    }
    
    func learn() async {
        // Would integrate with Voice Memos app
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: 12. MUSIC LEARNER
// MARK: ═══════════════════════════════════════════════════════════════════

/// Learns from music — mood, preferences
class MusicLearner: ObservableObject {
    @Published var songsLearned = 0
    
    private let memory = InfiniteMemorySystem.shared
    
    /// Learn from now playing
    func learnFromNowPlaying() async {
        // Would use MediaPlayer.MPMusicPlayerController
        // Or MusicKit for Apple Music
        
        // Learn:
        // - Favorite artists/genres
        // - Music preferences by time of day
        // - Mood indicators (upbeat vs calm)
    }
    
    /// Learn from a played song
    func learnFromSong(title: String, artist: String, genre: String?) async {
        var facts = ["Played: \(title) by \(artist)"]
        if let genre = genre {
            facts.append("Genre: \(genre)")
        }
        
        await memory.processConversation(messages: [
            (role: "system", content: "Music played"),
            (role: "music", content: facts.joined(separator: "\n"))
        ])
        songsLearned += 1
    }
    
    func learn() async {
        await learnFromNowPlaying()
    }
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: UNIFIED DASHBOARD
// MARK: ═══════════════════════════════════════════════════════════════════

struct LearnFromEverythingView: View {
    @StateObject private var engine = UniversalLearningEngine.shared
    
    var body: some View {
        List {
            Section("Learning Sources") {
                SourceRow(icon: "📄", name: "Files", count: engine.fileLearner.filesLearned)
                SourceRow(icon: "🌐", name: "Web", count: engine.webLearner.pagesLearned)
                SourceRow(icon: "📅", name: "Calendar", count: engine.calendarLearner.eventsLearned)
                SourceRow(icon: "👤", name: "Contacts", count: engine.contactsLearner.contactsLearned)
                SourceRow(icon: "📸", name: "Photos", count: engine.photoLearner.photosLearned)
                SourceRow(icon: "❤️", name: "Health", count: engine.healthLearner.patternsLearned)
                SourceRow(icon: "📍", name: "Location", count: engine.locationLearner.placesLearned)
                SourceRow(icon: "🖥️", name: "Screen", count: engine.screenLearner.screensLearned)
                SourceRow(icon: "📋", name: "Clipboard", count: engine.clipboardLearner.clipsLearned)
                SourceRow(icon: "📱", name: "Apps", count: engine.appUsageLearner.appsLearned)
                SourceRow(icon: "🎤", name: "Voice", count: engine.voiceLearner.notesLearned)
                SourceRow(icon: "🎵", name: "Music", count: engine.musicLearner.songsLearned)
            }
            
            Section("Actions") {
                Button {
                    Task { await engine.learnFromEverything() }
                } label: {
                    HStack {
                        if engine.isLearning {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "brain.head.profile")
                        }
                        Text(engine.isLearning ? "Learning..." : "Learn From Everything")
                    }
                }
                .disabled(engine.isLearning)
            }
            
            if let lastTime = engine.lastLearnTime {
                Section("Status") {
                    HStack {
                        Text("Last learned")
                        Spacer()
                        Text(lastTime, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Universal Learning")
    }
}

struct SourceRow: View {
    let icon: String
    let name: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(icon)
            Text(name)
            Spacer()
            Text("\(count)")
                .foregroundColor(.cyan)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    NavigationStack {
        LearnFromEverythingView()
    }
}
