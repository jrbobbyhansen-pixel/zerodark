import Foundation
import EventKit
import Contacts
import CoreLocation
import MapKit
import StoreKit
import UserNotifications

// MARK: - Extended Agent Tools

/// Additional high-value tools for full Siri replacement
extension AgentToolkit {
    
    // MARK: - Calendar Tool
    
    public func executeCalendar(_ args: [String: String]) async -> ToolResult {
        let store = EKEventStore()
        let action = args["action"] ?? "list"
        
        // Request access
        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                return ToolResult(success: false, output: "Calendar access denied", data: nil)
            }
        } catch {
            return ToolResult(success: false, output: "Failed to access calendar: \(error.localizedDescription)", data: nil)
        }
        
        switch action {
        case "list":
            return listEvents(store: store, args: args)
            
        case "create":
            return await createEvent(store: store, args: args)
            
        case "today":
            return listTodayEvents(store: store)
            
        case "upcoming":
            return listUpcomingEvents(store: store, days: Int(args["days"] ?? "7") ?? 7)
            
        default:
            return ToolResult(success: false, output: "Unknown calendar action: \(action)", data: nil)
        }
    }
    
    private func listTodayEvents(store: EKEventStore) -> ToolResult {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
        
        if events.isEmpty {
            return ToolResult(success: true, output: "No events today", data: nil)
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        var output = "Today's events:\n"
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            let time = event.isAllDay ? "All day" : formatter.string(from: event.startDate)
            output += "• \(time): \(event.title ?? "Untitled")\n"
        }
        
        return ToolResult(success: true, output: output, data: ["count": events.count])
    }
    
    private func listUpcomingEvents(store: EKEventStore, days: Int) -> ToolResult {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now)!
        
        let predicate = store.predicateForEvents(withStart: now, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)
        
        if events.isEmpty {
            return ToolResult(success: true, output: "No events in the next \(days) days", data: nil)
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        var output = "Upcoming events (\(days) days):\n"
        for event in events.sorted(by: { $0.startDate < $1.startDate }).prefix(10) {
            let time = event.isAllDay ? "All day" : formatter.string(from: event.startDate)
            output += "• \(time): \(event.title ?? "Untitled")\n"
        }
        
        if events.count > 10 {
            output += "... and \(events.count - 10) more"
        }
        
        return ToolResult(success: true, output: output, data: ["count": events.count])
    }
    
    private func listEvents(store: EKEventStore, args: [String: String]) -> ToolResult {
        // Default to today
        return listTodayEvents(store: store)
    }
    
    private func createEvent(store: EKEventStore, args: [String: String]) async -> ToolResult {
        guard let title = args["title"] else {
            return ToolResult(success: false, output: "Missing event title", data: nil)
        }
        
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = store.defaultCalendarForNewEvents
        
        // Parse date/time
        if let dateStr = args["date"] {
            // Simple parsing - in production would use NLP
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let date = formatter.date(from: dateStr) {
                event.startDate = date
                event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date)
            }
        } else {
            // Default to now + 1 hour
            event.startDate = Date()
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        }
        
        if let notes = args["notes"] {
            event.notes = notes
        }
        
        if let location = args["location"] {
            event.location = location
        }
        
        event.isAllDay = args["allDay"]?.lowercased() == "true"
        
        do {
            try store.save(event, span: .thisEvent)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return ToolResult(
                success: true, 
                output: "Created event: \(title) on \(formatter.string(from: event.startDate))", 
                data: ["eventId": event.eventIdentifier ?? ""]
            )
        } catch {
            return ToolResult(success: false, output: "Failed to create event: \(error.localizedDescription)", data: nil)
        }
    }
    
    // MARK: - Contacts Tool
    
    public func executeContacts(_ args: [String: String]) async -> ToolResult {
        let store = CNContactStore()
        
        do {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            if status != .authorized {
                try await store.requestAccess(for: .contacts)
            }
        } catch {
            return ToolResult(success: false, output: "Contacts access denied", data: nil)
        }
        
        let action = args["action"] ?? "search"
        
        switch action {
        case "search":
            guard let query = args["query"] else {
                return ToolResult(success: false, output: "Missing search query", data: nil)
            }
            return searchContacts(store: store, query: query)
            
        case "get":
            guard let name = args["name"] else {
                return ToolResult(success: false, output: "Missing contact name", data: nil)
            }
            return getContactDetails(store: store, name: name)
            
        default:
            return ToolResult(success: false, output: "Unknown contacts action", data: nil)
        }
    }
    
    private func searchContacts(store: CNContactStore, query: String) -> ToolResult {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        
        let predicate = CNContact.predicateForContacts(matchingName: query)
        
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            
            if contacts.isEmpty {
                return ToolResult(success: true, output: "No contacts found for '\(query)'", data: nil)
            }
            
            var output = "Found \(contacts.count) contact(s):\n"
            for contact in contacts.prefix(5) {
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                output += "• \(name)"
                
                if let phone = contact.phoneNumbers.first?.value.stringValue {
                    output += " - \(phone)"
                }
                output += "\n"
            }
            
            return ToolResult(success: true, output: output, data: ["count": contacts.count])
        } catch {
            return ToolResult(success: false, output: "Search failed: \(error.localizedDescription)", data: nil)
        }
    }
    
    private func getContactDetails(store: CNContactStore, name: String) -> ToolResult {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor
        ]
        
        let predicate = CNContact.predicateForContacts(matchingName: name)
        
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            
            guard let contact = contacts.first else {
                return ToolResult(success: true, output: "No contact found for '\(name)'", data: nil)
            }
            
            var output = "\(contact.givenName) \(contact.familyName)\n"
            
            if !contact.organizationName.isEmpty {
                output += "Company: \(contact.organizationName)\n"
            }
            if !contact.jobTitle.isEmpty {
                output += "Title: \(contact.jobTitle)\n"
            }
            
            for phone in contact.phoneNumbers {
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? "")
                output += "📱 \(label): \(phone.value.stringValue)\n"
            }
            
            for email in contact.emailAddresses {
                output += "✉️ \(email.value as String)\n"
            }
            
            if let birthday = contact.birthday {
                let formatter = DateFormatter()
                formatter.dateStyle = .long
                if let date = birthday.date {
                    output += "🎂 \(formatter.string(from: date))\n"
                }
            }
            
            return ToolResult(success: true, output: output, data: nil)
        } catch {
            return ToolResult(success: false, output: "Failed to get contact: \(error.localizedDescription)", data: nil)
        }
    }
    
    // MARK: - Location Tool
    
    public func executeLocation(_ args: [String: String]) async -> ToolResult {
        let action = args["action"] ?? "search"
        
        switch action {
        case "search":
            guard let query = args["query"] else {
                return ToolResult(success: false, output: "Missing search query", data: nil)
            }
            return await searchLocation(query: query)
            
        case "directions":
            guard let destination = args["to"] else {
                return ToolResult(success: false, output: "Missing destination", data: nil)
            }
            return await getDirections(to: destination, from: args["from"])
            
        default:
            return ToolResult(success: false, output: "Unknown location action", data: nil)
        }
    }
    
    private func searchLocation(query: String) async -> ToolResult {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            
            if response.mapItems.isEmpty {
                return ToolResult(success: true, output: "No locations found for '\(query)'", data: nil)
            }
            
            var output = "Found \(response.mapItems.count) location(s):\n"
            
            for item in response.mapItems.prefix(5) {
                output += "📍 \(item.name ?? "Unknown")\n"
                if let address = item.placemark.title {
                    output += "   \(address)\n"
                }
                if let phone = item.phoneNumber {
                    output += "   📱 \(phone)\n"
                }
            }
            
            return ToolResult(success: true, output: output, data: ["count": response.mapItems.count])
        } catch {
            return ToolResult(success: false, output: "Search failed: \(error.localizedDescription)", data: nil)
        }
    }
    
    private func getDirections(to destination: String, from origin: String?) async -> ToolResult {
        // Search for destination
        let destRequest = MKLocalSearch.Request()
        destRequest.naturalLanguageQuery = destination
        let destSearch = MKLocalSearch(request: destRequest)
        
        do {
            let destResponse = try await destSearch.start()
            guard let destItem = destResponse.mapItems.first else {
                return ToolResult(success: false, output: "Could not find destination: \(destination)", data: nil)
            }
            
            // Get directions
            let directionsRequest = MKDirections.Request()
            directionsRequest.destination = destItem
            
            if let origin = origin {
                let originRequest = MKLocalSearch.Request()
                originRequest.naturalLanguageQuery = origin
                let originSearch = MKLocalSearch(request: originRequest)
                let originResponse = try await originSearch.start()
                if let originItem = originResponse.mapItems.first {
                    directionsRequest.source = originItem
                }
            } else {
                directionsRequest.source = MKMapItem.forCurrentLocation()
            }
            
            directionsRequest.transportType = .automobile
            
            let directions = MKDirections(request: directionsRequest)
            let response = try await directions.calculate()
            
            guard let route = response.routes.first else {
                return ToolResult(success: false, output: "No route found", data: nil)
            }
            
            let distanceKm = route.distance / 1000
            let timeMin = route.expectedTravelTime / 60
            
            var output = "📍 Directions to \(destItem.name ?? destination):\n"
            output += "🚗 Distance: \(String(format: "%.1f", distanceKm)) km\n"
            output += "⏱️ Time: \(Int(timeMin)) minutes\n\n"
            
            output += "Steps:\n"
            for (index, step) in route.steps.enumerated() where !step.instructions.isEmpty {
                output += "\(index + 1). \(step.instructions)\n"
            }
            
            return ToolResult(success: true, output: output, data: [
                "distance": route.distance,
                "time": route.expectedTravelTime
            ])
        } catch {
            return ToolResult(success: false, output: "Failed to get directions: \(error.localizedDescription)", data: nil)
        }
    }
    
    // MARK: - Notification Tool
    
    public func executeNotification(_ args: [String: String]) async -> ToolResult {
        let center = UNUserNotificationCenter.current()
        
        // Request permission
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                return ToolResult(success: false, output: "Notification permission denied", data: nil)
            }
        } catch {
            return ToolResult(success: false, output: "Failed to request notification permission", data: nil)
        }
        
        guard let title = args["title"] else {
            return ToolResult(success: false, output: "Missing notification title", data: nil)
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = args["body"] ?? ""
        content.sound = .default
        
        // Parse delay
        let delay = Double(args["delay"] ?? "0") ?? 0
        
        let trigger: UNNotificationTrigger?
        if delay > 0 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        } else {
            trigger = nil
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        do {
            try await center.add(request)
            if delay > 0 {
                return ToolResult(success: true, output: "Notification scheduled in \(Int(delay)) seconds", data: nil)
            } else {
                return ToolResult(success: true, output: "Notification sent", data: nil)
            }
        } catch {
            return ToolResult(success: false, output: "Failed to send notification: \(error.localizedDescription)", data: nil)
        }
    }
    
    // MARK: - Web Search Tool
    
    public func executeWebSearch(_ args: [String: String]) async -> ToolResult {
        guard let query = args["query"] else {
            return ToolResult(success: false, output: "Missing search query", data: nil)
        }
        
        // Construct search URL (DuckDuckGo API for privacy)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1"
        
        guard let url = URL(string: urlString) else {
            return ToolResult(success: false, output: "Invalid search query", data: nil)
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var output = "Search results for '\(query)':\n\n"
                
                // Abstract (instant answer)
                if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
                    output += "📝 \(abstract)\n\n"
                }
                
                // Related topics
                if let relatedTopics = json["RelatedTopics"] as? [[String: Any]] {
                    for topic in relatedTopics.prefix(5) {
                        if let text = topic["Text"] as? String {
                            output += "• \(text)\n"
                        }
                    }
                }
                
                if output == "Search results for '\(query)':\n\n" {
                    output += "No instant answer available. Try a more specific query."
                }
                
                return ToolResult(success: true, output: output, data: nil)
            }
            
            return ToolResult(success: false, output: "Could not parse search results", data: nil)
        } catch {
            return ToolResult(success: false, output: "Search failed: \(error.localizedDescription)", data: nil)
        }
    }
    
    // MARK: - App Launcher Tool
    
    #if os(iOS)
    public func executeLaunchApp(_ args: [String: String]) async -> ToolResult {
        guard let appName = args["app"]?.lowercased() else {
            return ToolResult(success: false, output: "Missing app name", data: nil)
        }
        
        // Common app URL schemes
        let appSchemes: [String: String] = [
            "settings": "App-prefs:",
            "messages": "sms:",
            "mail": "mailto:",
            "phone": "tel:",
            "facetime": "facetime:",
            "maps": "maps:",
            "music": "music:",
            "photos": "photos-redirect:",
            "safari": "https://",
            "calendar": "calshow:",
            "notes": "mobilenotes:",
            "reminders": "x-apple-reminderkit:",
            "weather": "weather:",
            "clock": "clock-worldclock:",
            "camera": "camera:",
            "app store": "itms-apps:",
            "podcasts": "podcasts:",
            "news": "applenews:",
            "health": "x-apple-health:",
            "wallet": "shoebox:",
            "files": "shareddocuments:",
            "shortcuts": "shortcuts:",
        ]
        
        // Find matching scheme
        var scheme: String?
        for (name, urlScheme) in appSchemes {
            if appName.contains(name) {
                scheme = urlScheme
                break
            }
        }
        
        guard let urlScheme = scheme, let url = URL(string: urlScheme) else {
            return ToolResult(success: false, output: "Cannot open app: \(appName)", data: nil)
        }
        
        await MainActor.run {
            UIApplication.shared.open(url)
        }
        
        return ToolResult(success: true, output: "Opening \(appName)...", data: nil)
    }
    #endif
    
    // MARK: - System Control Tool
    
    #if os(iOS)
    public func executeSystemControl(_ args: [String: String]) async -> ToolResult {
        let action = args["action"] ?? ""
        
        switch action {
        case "flashlight":
            return toggleFlashlight(on: args["state"]?.lowercased() == "on")
            
        case "haptic":
            let style = args["style"] ?? "medium"
            return triggerHaptic(style: style)
            
        default:
            return ToolResult(success: false, output: "Unknown system action: \(action)", data: nil)
        }
    }
    
    private func toggleFlashlight(on: Bool) -> ToolResult {
        import AVFoundation
        
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return ToolResult(success: false, output: "Flashlight not available", data: nil)
        }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            return ToolResult(success: true, output: "Flashlight \(on ? "on" : "off")", data: nil)
        } catch {
            return ToolResult(success: false, output: "Failed to control flashlight", data: nil)
        }
    }
    
    private func triggerHaptic(style: String) -> ToolResult {
        let generator: UIImpactFeedbackGenerator
        
        switch style {
        case "light":
            generator = UIImpactFeedbackGenerator(style: .light)
        case "heavy":
            generator = UIImpactFeedbackGenerator(style: .heavy)
        case "rigid":
            generator = UIImpactFeedbackGenerator(style: .rigid)
        case "soft":
            generator = UIImpactFeedbackGenerator(style: .soft)
        default:
            generator = UIImpactFeedbackGenerator(style: .medium)
        }
        
        generator.impactOccurred()
        return ToolResult(success: true, output: "Haptic triggered", data: nil)
    }
    #endif
}

// MARK: - Extended Tool Definitions

extension AgentToolkit {
    
    var calendarTool: Tool {
        Tool(
            name: "calendar",
            description: "View and create calendar events.",
            parameters: [
                .init(name: "action", type: "string", description: "Action to perform", required: true, enumValues: ["list", "create", "today", "upcoming"]),
                .init(name: "title", type: "string", description: "Event title (for create)", required: false, enumValues: nil),
                .init(name: "date", type: "string", description: "Date/time (YYYY-MM-DD HH:mm)", required: false, enumValues: nil),
                .init(name: "location", type: "string", description: "Event location", required: false, enumValues: nil),
                .init(name: "days", type: "number", description: "Days to look ahead (for upcoming)", required: false, enumValues: nil)
            ],
            handler: "calendar"
        )
    }
    
    var contactsTool: Tool {
        Tool(
            name: "contacts",
            description: "Search and view contact information.",
            parameters: [
                .init(name: "action", type: "string", description: "Action to perform", required: true, enumValues: ["search", "get"]),
                .init(name: "query", type: "string", description: "Search query", required: false, enumValues: nil),
                .init(name: "name", type: "string", description: "Contact name (for get)", required: false, enumValues: nil)
            ],
            handler: "contacts"
        )
    }
    
    var locationTool: Tool {
        Tool(
            name: "location",
            description: "Search for places and get directions.",
            parameters: [
                .init(name: "action", type: "string", description: "Action to perform", required: true, enumValues: ["search", "directions"]),
                .init(name: "query", type: "string", description: "Place to search for", required: false, enumValues: nil),
                .init(name: "to", type: "string", description: "Destination (for directions)", required: false, enumValues: nil),
                .init(name: "from", type: "string", description: "Starting point (optional)", required: false, enumValues: nil)
            ],
            handler: "location"
        )
    }
    
    var notificationTool: Tool {
        Tool(
            name: "notification",
            description: "Send local notifications.",
            parameters: [
                .init(name: "title", type: "string", description: "Notification title", required: true, enumValues: nil),
                .init(name: "body", type: "string", description: "Notification body", required: false, enumValues: nil),
                .init(name: "delay", type: "number", description: "Delay in seconds", required: false, enumValues: nil)
            ],
            handler: "notification"
        )
    }
    
    var webSearchTool: Tool {
        Tool(
            name: "web_search",
            description: "Search the web for information.",
            parameters: [
                .init(name: "query", type: "string", description: "Search query", required: true, enumValues: nil)
            ],
            handler: "web_search"
        )
    }
    
    #if os(iOS)
    var launchAppTool: Tool {
        Tool(
            name: "launch_app",
            description: "Open an app on the device.",
            parameters: [
                .init(name: "app", type: "string", description: "App name (e.g., 'settings', 'messages', 'safari')", required: true, enumValues: nil)
            ],
            handler: "launch_app"
        )
    }
    
    var systemControlTool: Tool {
        Tool(
            name: "system_control",
            description: "Control system features like flashlight.",
            parameters: [
                .init(name: "action", type: "string", description: "Action to perform", required: true, enumValues: ["flashlight", "haptic"]),
                .init(name: "state", type: "string", description: "State (on/off for flashlight)", required: false, enumValues: ["on", "off"]),
                .init(name: "style", type: "string", description: "Haptic style", required: false, enumValues: ["light", "medium", "heavy", "rigid", "soft"])
            ],
            handler: "system_control"
        )
    }
    #endif
    
    /// Extended tools list
    public var extendedTools: [Tool] {
        var extended = tools
        extended.append(contentsOf: [
            calendarTool,
            contactsTool,
            locationTool,
            notificationTool,
            webSearchTool
        ])
        #if os(iOS)
        extended.append(contentsOf: [
            launchAppTool,
            systemControlTool
        ])
        #endif
        return extended
    }
}
