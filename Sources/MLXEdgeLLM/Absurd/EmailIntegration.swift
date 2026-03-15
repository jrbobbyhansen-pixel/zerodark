// EmailIntegration.swift
// Read, summarize, and draft emails with AI
// ABSURD MODE

import Foundation

#if canImport(MessageUI)
import MessageUI
#endif

// MARK: - Email Integration

public actor EmailAssistant {
    
    public static let shared = EmailAssistant()
    
    // MARK: - Types
    
    public struct Email: Identifiable, Sendable {
        public let id: String
        public let from: String
        public let to: [String]
        public let subject: String
        public let body: String
        public let date: Date
        public let isRead: Bool
        public let hasAttachments: Bool
        public let threadId: String?
        public let importance: Importance
        
        public enum Importance: String, Sendable {
            case low = "Low"
            case normal = "Normal"
            case high = "High"
            case urgent = "Urgent"
        }
    }
    
    public struct EmailSummary: Sendable {
        public let totalUnread: Int
        public let importantCount: Int
        public let categories: [CategorySummary]
        public let topPriority: [Email]
        public let needsResponse: [Email]
        public let aiSummary: String
        
        public struct CategorySummary: Sendable {
            public let name: String
            public let count: Int
            public let icon: String
        }
    }
    
    public struct DraftEmail: Sendable {
        public let to: [String]
        public let subject: String
        public let body: String
        public let replyToId: String?
    }
    
    // MARK: - Simulated Inbox
    
    private let simulatedEmails: [Email] = [
        Email(
            id: "1",
            from: "boss@company.com",
            to: ["me@company.com"],
            subject: "Q1 Report Review - Action Required",
            body: "Please review the attached Q1 report and provide your feedback by EOD tomorrow. The board meeting is scheduled for Friday.",
            date: Date().addingTimeInterval(-3600),
            isRead: false,
            hasAttachments: true,
            threadId: "thread-1",
            importance: .high
        ),
        Email(
            id: "2",
            from: "client@acme.com",
            to: ["me@company.com"],
            subject: "Re: Project Timeline",
            body: "Thanks for the update. Can we schedule a call this week to discuss the new timeline? I'm available Tuesday or Wednesday afternoon.",
            date: Date().addingTimeInterval(-7200),
            isRead: false,
            hasAttachments: false,
            threadId: "thread-2",
            importance: .normal
        ),
        Email(
            id: "3",
            from: "newsletter@tech.com",
            to: ["me@company.com"],
            subject: "This Week in Tech: AI Breakthroughs",
            body: "Read about the latest AI developments...",
            date: Date().addingTimeInterval(-14400),
            isRead: true,
            hasAttachments: false,
            threadId: nil,
            importance: .low
        ),
        Email(
            id: "4",
            from: "hr@company.com",
            to: ["all@company.com"],
            subject: "Benefits Enrollment Deadline - URGENT",
            body: "Reminder: Open enrollment ends this Friday. Please complete your selections.",
            date: Date().addingTimeInterval(-28800),
            isRead: false,
            hasAttachments: true,
            threadId: nil,
            importance: .urgent
        ),
        Email(
            id: "5",
            from: "team@project.com",
            to: ["me@company.com"],
            subject: "Sprint Planning - Tomorrow 10am",
            body: "Don't forget about sprint planning tomorrow. Please come prepared with your updates.",
            date: Date().addingTimeInterval(-43200),
            isRead: true,
            hasAttachments: false,
            threadId: "thread-3",
            importance: .normal
        )
    ]
    
    private init() {}
    
    // MARK: - Read Emails
    
    public func getUnreadEmails(limit: Int = 10) -> [Email] {
        return Array(simulatedEmails.filter { !$0.isRead }.prefix(limit))
    }
    
    public func getAllEmails(limit: Int = 50) -> [Email] {
        return Array(simulatedEmails.prefix(limit))
    }
    
    public func getEmail(id: String) -> Email? {
        return simulatedEmails.first { $0.id == id }
    }
    
    public func searchEmails(query: String) -> [Email] {
        let queryLower = query.lowercased()
        return simulatedEmails.filter { email in
            email.subject.lowercased().contains(queryLower) ||
            email.body.lowercased().contains(queryLower) ||
            email.from.lowercased().contains(queryLower)
        }
    }
    
    // MARK: - Summarize
    
    public func getSummary() async -> EmailSummary {
        let unread = simulatedEmails.filter { !$0.isRead }
        let important = simulatedEmails.filter { $0.importance == .high || $0.importance == .urgent }
        
        // Generate AI summary
        let aiSummary = await generateAISummary(emails: unread)
        
        // Detect emails needing response
        let needsResponse = simulatedEmails.filter { email in
            email.body.lowercased().contains("please") ||
            email.body.lowercased().contains("can you") ||
            email.body.lowercased().contains("action required")
        }
        
        return EmailSummary(
            totalUnread: unread.count,
            importantCount: important.count,
            categories: [
                EmailSummary.CategorySummary(name: "Work", count: 3, icon: "briefcase"),
                EmailSummary.CategorySummary(name: "Newsletter", count: 1, icon: "newspaper"),
                EmailSummary.CategorySummary(name: "HR", count: 1, icon: "person.2")
            ],
            topPriority: Array(important.prefix(3)),
            needsResponse: Array(needsResponse.prefix(5)),
            aiSummary: aiSummary
        )
    }
    
    private func generateAISummary(emails: [Email]) async -> String {
        if emails.isEmpty {
            return "Your inbox is clear! No unread emails."
        }
        
        let ai = await ZeroDarkAI.shared
        let emailDescriptions = emails.map { "- From \($0.from): \($0.subject)" }.joined(separator: "\n")
        
        let prompt = """
        Summarize these unread emails in 2-3 sentences:
        
        \(emailDescriptions)
        
        Focus on what needs attention and any urgent items.
        """
        
        do {
            return try await ai.process(prompt: prompt, onToken: { _ in })
        } catch {
            return "You have \(emails.count) unread emails."
        }
    }
    
    public func summarizeEmail(_ email: Email) async -> String {
        let ai = await ZeroDarkAI.shared
        
        let prompt = """
        Summarize this email in 1-2 sentences:
        
        From: \(email.from)
        Subject: \(email.subject)
        Body: \(email.body)
        
        What's the main point and any action required?
        """
        
        do {
            return try await ai.process(prompt: prompt, onToken: { _ in })
        } catch {
            return "Unable to summarize."
        }
    }
    
    // MARK: - Draft Emails
    
    public func draftReply(to email: Email, instructions: String = "") async -> DraftEmail {
        let ai = await ZeroDarkAI.shared
        
        let prompt = """
        Draft a professional reply to this email:
        
        From: \(email.from)
        Subject: \(email.subject)
        Body: \(email.body)
        
        \(instructions.isEmpty ? "Write a helpful, professional response." : "Instructions: \(instructions)")
        
        Provide only the email body, no greeting or signature (those will be added).
        """
        
        do {
            let body = try await ai.process(prompt: prompt, onToken: { _ in })
            return DraftEmail(
                to: [email.from],
                subject: email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)",
                body: body,
                replyToId: email.id
            )
        } catch {
            return DraftEmail(
                to: [email.from],
                subject: "Re: \(email.subject)",
                body: "Thank you for your email. I'll get back to you shortly.",
                replyToId: email.id
            )
        }
    }
    
    public func draftNewEmail(to: [String], about: String) async -> DraftEmail {
        let ai = await ZeroDarkAI.shared
        
        let prompt = """
        Draft a professional email:
        
        To: \(to.joined(separator: ", "))
        Topic: \(about)
        
        Write a clear, professional email. Include:
        1. Subject line (on first line, prefixed with "Subject: ")
        2. Email body
        
        Keep it concise and professional.
        """
        
        do {
            let response = try await ai.process(prompt: prompt, onToken: { _ in })
            
            // Parse subject from response
            let lines = response.components(separatedBy: "\n")
            var subject = "Regarding: \(about)"
            var body = response
            
            if let subjectLine = lines.first, subjectLine.lowercased().hasPrefix("subject:") {
                subject = subjectLine.replacingOccurrences(of: "Subject: ", with: "", options: .caseInsensitive)
                body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            return DraftEmail(to: to, subject: subject, body: body, replyToId: nil)
        } catch {
            return DraftEmail(
                to: to,
                subject: "Regarding: \(about)",
                body: "[Draft your email here]",
                replyToId: nil
            )
        }
    }
    
    // MARK: - Smart Actions
    
    public func suggestActions(for email: Email) async -> [String] {
        var actions: [String] = []
        
        let bodyLower = email.body.lowercased()
        
        // Schedule-related
        if bodyLower.contains("schedule") || bodyLower.contains("meeting") || bodyLower.contains("call") {
            actions.append("📅 Add to calendar")
            actions.append("📧 Suggest meeting times")
        }
        
        // Task-related
        if bodyLower.contains("please") || bodyLower.contains("action required") || bodyLower.contains("can you") {
            actions.append("✅ Create reminder")
            actions.append("📝 Add to tasks")
        }
        
        // Response needed
        if !email.isRead {
            actions.append("✍️ Draft reply")
            actions.append("⭐ Mark important")
        }
        
        // Default actions
        actions.append("📋 Summarize")
        actions.append("🗂️ Archive")
        
        return actions
    }
    
    // MARK: - Batch Operations
    
    public func summarizeAllUnread() async -> String {
        let unread = getUnreadEmails()
        if unread.isEmpty {
            return "No unread emails! 🎉"
        }
        
        var summary = "📬 You have \(unread.count) unread emails:\n\n"
        
        let urgent = unread.filter { $0.importance == .urgent || $0.importance == .high }
        if !urgent.isEmpty {
            summary += "🔴 URGENT:\n"
            for email in urgent {
                summary += "• \(email.from): \(email.subject)\n"
            }
            summary += "\n"
        }
        
        let normal = unread.filter { $0.importance == .normal }
        if !normal.isEmpty {
            summary += "📩 Regular:\n"
            for email in normal {
                summary += "• \(email.from): \(email.subject)\n"
            }
        }
        
        return summary
    }
}
