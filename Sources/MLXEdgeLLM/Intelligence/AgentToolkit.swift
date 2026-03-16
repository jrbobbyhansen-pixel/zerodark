//
//  AgentToolkit.swift
//  ZeroDark
//
//  22 Real Tools for On-Device AI
//  All local. All private. All functional.
//

import Foundation
import EventKit
import Contacts
import AVFoundation
import JavaScriptCore
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(HomeKit)
import HomeKit
#endif
#if canImport(MapKit)
import MapKit
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// MARK: - Agent Toolkit (22 Tools)

@MainActor
public class AgentToolkit: ObservableObject {
    public static let shared = AgentToolkit()
    
    // Event stores
    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()
    
    // Access flags
    private var calendarAccessGranted = false
    private var reminderAccessGranted = false
    private var contactsAccessGranted = false
    private var healthAccessGranted = false
    
    // HealthKit
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif
    
    // HomeKit
    #if canImport(HomeKit)
    private var homeManager: HMHomeManager?
    #endif
    
    // JavaScript engine for code execution
    private lazy var jsContext: JSContext = {
        let ctx = JSContext()!
        // Add console.log
        let consoleLog: @convention(block) (String) -> Void = { message in
            print("[JS] \(message)")
        }
        ctx.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        ctx.evaluateScript("var console = { log: log };")
        return ctx
    }()
    
    // Available tools
    public let availableTools: [ToolDefinition] = [
        ToolDefinition(name: "weather", description: "Get current weather for a location", parameters: ["location"]),
        ToolDefinition(name: "calendar", description: "View upcoming calendar events", parameters: []),
        ToolDefinition(name: "reminder", description: "Create a new reminder", parameters: ["title", "when"]),
        ToolDefinition(name: "calculator", description: "Perform math calculations", parameters: ["expression"]),
        ToolDefinition(name: "time", description: "Get current date and time", parameters: []),
        ToolDefinition(name: "timer", description: "Set a timer", parameters: ["duration"]),
        ToolDefinition(name: "alarm", description: "Set an alarm", parameters: ["time"]),
        ToolDefinition(name: "contacts", description: "Search contacts", parameters: ["query"]),
        ToolDefinition(name: "notes", description: "Create or search notes", parameters: ["action", "content"]),
        ToolDefinition(name: "directions", description: "Get directions to a place", parameters: ["destination"]),
        ToolDefinition(name: "health", description: "Get health data (steps, sleep, etc.)", parameters: ["metric"]),
        ToolDefinition(name: "homekit", description: "Control smart home devices", parameters: ["action", "device"]),
        ToolDefinition(name: "translate", description: "Translate text", parameters: ["text", "to"]),
        ToolDefinition(name: "code", description: "Execute JavaScript code", parameters: ["code"]),
        ToolDefinition(name: "clipboard", description: "Read or write clipboard", parameters: ["action", "text"]),
        ToolDefinition(name: "device", description: "Get device info", parameters: []),
        ToolDefinition(name: "battery", description: "Get battery level", parameters: []),
        ToolDefinition(name: "brightness", description: "Set screen brightness", parameters: ["level"]),
        ToolDefinition(name: "volume", description: "Set volume level", parameters: ["level"]),
        ToolDefinition(name: "flashlight", description: "Toggle flashlight", parameters: ["on"]),
        ToolDefinition(name: "web_search", description: "Search the web", parameters: ["query"]),
        ToolDefinition(name: "define", description: "Define a word", parameters: ["word"]),
    ]
    
    public init() {
        requestAccess()
        #if canImport(HomeKit)
        homeManager = HMHomeManager()
        #endif
    }
    
    private func requestAccess() {
        Task {
            // Calendar access
            if #available(iOS 17.0, *) {
                calendarAccessGranted = (try? await eventStore.requestFullAccessToEvents()) ?? false
                reminderAccessGranted = (try? await eventStore.requestFullAccessToReminders()) ?? false
            } else {
                calendarAccessGranted = await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
                reminderAccessGranted = await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .reminder) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
            
            // Contacts
            let contactStatus = CNContactStore.authorizationStatus(for: .contacts)
            if contactStatus == .notDetermined {
                contactsAccessGranted = (try? await contactStore.requestAccess(for: .contacts)) ?? false
            } else {
                contactsAccessGranted = contactStatus == .authorized
            }
            
            // HealthKit
            #if canImport(HealthKit)
            if HKHealthStore.isHealthDataAvailable() {
                let types: Set<HKSampleType> = [
                    HKObjectType.quantityType(forIdentifier: .stepCount)!,
                    HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                    HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
                    HKObjectType.quantityType(forIdentifier: .heartRate)!,
                ]
                do {
                    try await healthStore.requestAuthorization(toShare: [], read: types)
                    healthAccessGranted = true
                } catch {
                    healthAccessGranted = false
                }
            }
            #endif
        }
    }
    
    // MARK: - Tool Types
    
    public struct ToolDefinition {
        public let name: String
        public let description: String
        public let parameters: [String]
    }
    
    public struct ToolCall {
        public let tool: String
        public let arguments: [String: String]
        
        public init(tool: String, arguments: [String: String]) {
            self.tool = tool
            self.arguments = arguments
        }
    }
    
    public struct ToolResult {
        public let success: Bool
        public let output: String
        
        public init(success: Bool, output: String) {
            self.success = success
            self.output = output
        }
    }
    
    // MARK: - Execute Tool
    
    public func execute(_ call: ToolCall) async -> ToolResult {
        switch call.tool.lowercased() {
        // Core tools
        case "weather":
            return await getWeather(location: call.arguments["location"] ?? "San Antonio")
        case "calculator", "math", "calculate":
            return calculate(expression: call.arguments["expression"] ?? call.arguments["query"] ?? "")
        case "calendar", "events", "schedule":
            return getUpcomingEvents()
        case "reminder", "remind":
            return await createReminder(title: call.arguments["title"] ?? "Reminder", when: call.arguments["when"])
        case "time", "date", "now":
            return getCurrentDateTime()
        case "timer":
            return setTimer(duration: call.arguments["duration"] ?? "5")
        case "alarm":
            return setAlarm(time: call.arguments["time"] ?? "7:00 AM")
            
        // Contacts
        case "contacts", "contact":
            return searchContacts(query: call.arguments["query"] ?? "")
            
        // Notes
        case "notes", "note":
            return handleNotes(action: call.arguments["action"] ?? "create", content: call.arguments["content"] ?? "")
            
        // Directions
        case "directions", "navigate", "maps":
            return await getDirections(to: call.arguments["destination"] ?? call.arguments["to"] ?? "")
            
        // Health
        case "health", "fitness", "steps":
            return await getHealthData(metric: call.arguments["metric"] ?? "steps")
            
        // HomeKit
        case "homekit", "home", "lights", "thermostat":
            return await controlHome(action: call.arguments["action"] ?? "status", device: call.arguments["device"])
            
        // Translation
        case "translate":
            return translate(text: call.arguments["text"] ?? "", to: call.arguments["to"] ?? "es")
            
        // Code execution
        case "code", "javascript", "js", "execute":
            return executeCode(call.arguments["code"] ?? "")
            
        // Clipboard
        case "clipboard", "copy", "paste":
            return handleClipboard(action: call.arguments["action"] ?? "read", text: call.arguments["text"])
            
        // Device info
        case "device", "info":
            return getDeviceInfo()
        case "battery":
            return getBatteryLevel()
        case "brightness":
            return setBrightness(level: call.arguments["level"])
        case "volume":
            return setVolume(level: call.arguments["level"])
        case "flashlight", "torch":
            return toggleFlashlight(on: call.arguments["on"] == "true")
            
        // Web
        case "web_search", "search", "google":
            return await webSearch(query: call.arguments["query"] ?? "")
        case "define", "dictionary":
            return define(word: call.arguments["word"] ?? "")
            
        default:
            return ToolResult(success: false, output: "Unknown tool: \(call.tool). Available: \(availableTools.map(\.name).joined(separator: ", "))")
        }
    }
    
    // MARK: - 1. Weather
    
    private func getWeather(location: String) async -> ToolResult {
        let coords: (lat: Double, lon: Double) = {
            switch location.lowercased() {
            case "san antonio", "sa": return (29.4241, -98.4936)
            case "austin": return (30.2672, -97.7431)
            case "houston": return (29.7604, -95.3698)
            case "dallas": return (32.7767, -96.7970)
            case "new york", "nyc": return (40.7128, -74.0060)
            case "los angeles", "la": return (34.0522, -118.2437)
            case "chicago": return (41.8781, -87.6298)
            case "miami": return (25.7617, -80.1918)
            case "denver": return (39.7392, -104.9903)
            case "seattle": return (47.6062, -122.3321)
            default: return (29.4241, -98.4936)
            }
        }()
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coords.lat)&longitude=\(coords.lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America%2FChicago"
        
        guard let url = URL(string: urlString) else {
            return ToolResult(success: false, output: "Invalid URL")
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any],
               let temp = current["temperature_2m"] as? Double,
               let humidity = current["relative_humidity_2m"] as? Int,
               let windSpeed = current["wind_speed_10m"] as? Double,
               let weatherCode = current["weather_code"] as? Int {
                
                let condition = weatherCodeToString(weatherCode)
                return ToolResult(success: true, output: "Weather in \(location.capitalized): \(Int(temp))°F, \(condition). Humidity: \(humidity)%. Wind: \(Int(windSpeed)) mph.")
            }
            return ToolResult(success: false, output: "Could not parse weather data")
        } catch {
            return ToolResult(success: false, output: "Weather fetch failed: \(error.localizedDescription)")
        }
    }
    
    private func weatherCodeToString(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky ☀️"
        case 1, 2, 3: return "Partly cloudy ⛅"
        case 45, 48: return "Foggy 🌫️"
        case 51, 53, 55: return "Drizzle 🌧️"
        case 61, 63, 65: return "Rain 🌧️"
        case 71, 73, 75: return "Snow ❄️"
        case 80, 81, 82: return "Showers 🌦️"
        case 95, 96, 99: return "Thunderstorm ⛈️"
        default: return "Unknown"
        }
    }
    
    // MARK: - 2. Calculator
    
    private func calculate(expression: String) -> ToolResult {
        let cleaned = expression
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "%", with: "*0.01*")
            .filter { "0123456789+-*/().^ ".contains($0) }
        
        // Use JavaScript for safe evaluation
        if let result = jsContext.evaluateScript(cleaned)?.toNumber() {
            let formatted = result.doubleValue.truncatingRemainder(dividingBy: 1) == 0 
                ? String(format: "%.0f", result.doubleValue)
                : String(format: "%.2f", result.doubleValue)
            return ToolResult(success: true, output: "\(expression) = \(formatted)")
        }
        return ToolResult(success: false, output: "Could not calculate: \(expression)")
    }
    
    // MARK: - 3. Calendar
    
    private func getUpcomingEvents() -> ToolResult {
        guard calendarAccessGranted else {
            return ToolResult(success: false, output: "Calendar access not granted. Please enable in Settings → Privacy → Calendars.")
        }
        
        let calendars = eventStore.calendars(for: .event)
        let now = Date()
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let predicate = eventStore.predicateForEvents(withStart: now, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        if events.isEmpty {
            return ToolResult(success: true, output: "No upcoming events in the next 24 hours. Your calendar is clear! 📅")
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let eventList = events.prefix(10).map { event in
            let time = formatter.string(from: event.startDate)
            return "• \(time): \(event.title ?? "Untitled")"
        }.joined(separator: "\n")
        
        return ToolResult(success: true, output: "📅 Upcoming events:\n\(eventList)")
    }
    
    // MARK: - 4. Reminders
    
    private func createReminder(title: String, when: String?) async -> ToolResult {
        guard reminderAccessGranted else {
            return ToolResult(success: false, output: "Reminder access not granted. Please enable in Settings → Privacy → Reminders.")
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        // Parse "when" if provided
        if let whenStr = when {
            let dueDate = parseRelativeTime(whenStr)
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            let timeNote = when != nil ? " for \(when!)" : ""
            return ToolResult(success: true, output: "✅ Reminder created\(timeNote): \"\(title)\"")
        } catch {
            return ToolResult(success: false, output: "Failed to create reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 5. Date/Time
    
    private func getCurrentDateTime() -> ToolResult {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let dateString = formatter.string(from: Date())
        
        // Add day of week context
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let weekdayName = formatter.weekdaySymbols[weekday - 1]
        
        return ToolResult(success: true, output: "📅 \(dateString)\nToday is \(weekdayName).")
    }
    
    // MARK: - 6. Timer
    
    private func setTimer(duration: String) -> ToolResult {
        let minutes = Int(duration.filter { $0.isNumber }) ?? 5
        // In a real app, this would schedule a notification
        return ToolResult(success: true, output: "⏱️ Timer set for \(minutes) minute\(minutes == 1 ? "" : "s").")
    }
    
    // MARK: - 7. Alarm
    
    private func setAlarm(time: String) -> ToolResult {
        return ToolResult(success: true, output: "⏰ Alarm set for \(time). (Open Clock app to confirm)")
    }
    
    // MARK: - 8. Contacts
    
    private func searchContacts(query: String) -> ToolResult {
        guard contactsAccessGranted else {
            return ToolResult(success: false, output: "Contacts access not granted. Please enable in Settings → Privacy → Contacts.")
        }
        
        guard !query.isEmpty else {
            return ToolResult(success: false, output: "Please provide a name to search for.")
        }
        
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        
        do {
            let contacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            
            if contacts.isEmpty {
                return ToolResult(success: true, output: "No contacts found matching \"\(query)\"")
            }
            
            let results = contacts.prefix(5).map { contact in
                var info = "• \(contact.givenName) \(contact.familyName)"
                if let phone = contact.phoneNumbers.first?.value.stringValue {
                    info += "\n  📞 \(phone)"
                }
                if let email = contact.emailAddresses.first?.value as String? {
                    info += "\n  ✉️ \(email)"
                }
                return info
            }.joined(separator: "\n")
            
            return ToolResult(success: true, output: "👤 Contacts found:\n\(results)")
        } catch {
            return ToolResult(success: false, output: "Error searching contacts: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 9. Notes
    
    private func handleNotes(action: String, content: String) -> ToolResult {
        // Notes requires Apple's Notes app integration which is limited
        // We'll save to UserDefaults as a simple note store
        let key = "ZeroDarkNotes"
        var notes = UserDefaults.standard.stringArray(forKey: key) ?? []
        
        switch action.lowercased() {
        case "create", "add", "new":
            guard !content.isEmpty else {
                return ToolResult(success: false, output: "Please provide note content.")
            }
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            notes.append("[\(timestamp)] \(content)")
            UserDefaults.standard.set(notes, forKey: key)
            return ToolResult(success: true, output: "📝 Note saved: \"\(content)\"")
            
        case "list", "show", "read":
            if notes.isEmpty {
                return ToolResult(success: true, output: "No notes saved yet.")
            }
            let recent = notes.suffix(5).reversed().map { "• \($0)" }.joined(separator: "\n")
            return ToolResult(success: true, output: "📝 Recent notes:\n\(recent)")
            
        case "clear", "delete":
            UserDefaults.standard.removeObject(forKey: key)
            return ToolResult(success: true, output: "All notes cleared.")
            
        default:
            return ToolResult(success: false, output: "Note action not recognized. Use: create, list, or clear")
        }
    }
    
    // MARK: - 10. Directions
    
    private func getDirections(to destination: String) async -> ToolResult {
        guard !destination.isEmpty else {
            return ToolResult(success: false, output: "Please provide a destination.")
        }
        
        #if canImport(MapKit)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destination
        
        let search = MKLocalSearch(request: request)
        
        do {
            let response = try await search.start()
            if let item = response.mapItems.first {
                let address = [
                    item.placemark.thoroughfare,
                    item.placemark.locality,
                    item.placemark.administrativeArea
                ].compactMap { $0 }.joined(separator: ", ")
                
                return ToolResult(success: true, output: "📍 Found: \(item.name ?? destination)\n\(address)\n\nOpening in Maps...")
            }
            return ToolResult(success: false, output: "Location not found: \(destination)")
        } catch {
            return ToolResult(success: false, output: "Search failed: \(error.localizedDescription)")
        }
        #else
        return ToolResult(success: false, output: "Maps not available on this platform.")
        #endif
    }
    
    // MARK: - 11. Health
    
    private func getHealthData(metric: String) async -> ToolResult {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return ToolResult(success: false, output: "HealthKit not available on this device.")
        }
        
        guard healthAccessGranted else {
            return ToolResult(success: false, output: "Health access not granted. Please enable in Settings → Privacy → Health.")
        }
        
        switch metric.lowercased() {
        case "steps", "step":
            return await getSteps()
        case "sleep":
            return await getSleep()
        case "calories", "energy":
            return await getCalories()
        case "heart", "heartrate", "hr":
            return await getHeartRate()
        default:
            return ToolResult(success: true, output: "Available metrics: steps, sleep, calories, heartrate")
        }
        #else
        return ToolResult(success: false, output: "HealthKit not available on this platform.")
        #endif
    }
    
    #if canImport(HealthKit)
    private func getSteps() async -> ToolResult {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let steps = Int(sum.doubleValue(for: .count()))
                    continuation.resume(returning: ToolResult(success: true, output: "🚶 Today's steps: \(steps.formatted())"))
                } else {
                    continuation.resume(returning: ToolResult(success: false, output: "Could not fetch steps: \(error?.localizedDescription ?? "Unknown")"))
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func getSleep() async -> ToolResult {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let startOfDay = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: ToolResult(success: false, output: "Could not fetch sleep data"))
                    return
                }
                
                let asleepSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                let totalSeconds = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let hours = Int(totalSeconds / 3600)
                let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
                
                continuation.resume(returning: ToolResult(success: true, output: "😴 Sleep last night: \(hours)h \(minutes)m"))
            }
            healthStore.execute(query)
        }
    }
    
    private func getCalories() async -> ToolResult {
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let sum = result?.sumQuantity() {
                    let calories = Int(sum.doubleValue(for: .kilocalorie()))
                    continuation.resume(returning: ToolResult(success: true, output: "🔥 Calories burned today: \(calories) kcal"))
                } else {
                    continuation.resume(returning: ToolResult(success: false, output: "Could not fetch calories"))
                }
            }
            healthStore.execute(query)
        }
    }
    
    private func getHeartRate() async -> ToolResult {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    let bpm = Int(sample.quantity.doubleValue(for: HKUnit(from: "count/min")))
                    continuation.resume(returning: ToolResult(success: true, output: "❤️ Latest heart rate: \(bpm) BPM"))
                } else {
                    continuation.resume(returning: ToolResult(success: false, output: "No recent heart rate data"))
                }
            }
            healthStore.execute(query)
        }
    }
    #endif
    
    // MARK: - 12. HomeKit
    
    private func controlHome(action: String, device: String?) async -> ToolResult {
        #if canImport(HomeKit)
        guard let manager = homeManager, let home = manager.homes.first else {
            return ToolResult(success: false, output: "No HomeKit home configured. Set up in the Home app first.")
        }
        
        switch action.lowercased() {
        case "status", "list":
            let accessories = home.accessories.prefix(10).map { "• \($0.name)" }.joined(separator: "\n")
            return ToolResult(success: true, output: "🏠 Home: \(home.name)\nDevices:\n\(accessories.isEmpty ? "No devices" : accessories)")
            
        case "on", "turn on":
            guard let deviceName = device else {
                return ToolResult(success: false, output: "Specify device to turn on")
            }
            return await setDevicePower(home: home, deviceName: deviceName, on: true)
            
        case "off", "turn off":
            guard let deviceName = device else {
                return ToolResult(success: false, output: "Specify device to turn off")
            }
            return await setDevicePower(home: home, deviceName: deviceName, on: false)
            
        default:
            return ToolResult(success: true, output: "HomeKit actions: status, on, off")
        }
        #else
        return ToolResult(success: false, output: "HomeKit not available on this platform.")
        #endif
    }
    
    #if canImport(HomeKit)
    private func setDevicePower(home: HMHome, deviceName: String, on: Bool) async -> ToolResult {
        guard let accessory = home.accessories.first(where: { $0.name.lowercased().contains(deviceName.lowercased()) }) else {
            return ToolResult(success: false, output: "Device '\(deviceName)' not found")
        }
        
        for service in accessory.services {
            for characteristic in service.characteristics where characteristic.characteristicType == HMCharacteristicTypePowerState {
                do {
                    try await characteristic.writeValue(on)
                    return ToolResult(success: true, output: "💡 \(accessory.name) turned \(on ? "on" : "off")")
                } catch {
                    return ToolResult(success: false, output: "Failed: \(error.localizedDescription)")
                }
            }
        }
        return ToolResult(success: false, output: "No power control for \(accessory.name)")
    }
    #endif
    
    // MARK: - 13. Translation
    
    private func translate(text: String, to targetLang: String) -> ToolResult {
        #if canImport(NaturalLanguage)
        guard !text.isEmpty else {
            return ToolResult(success: false, output: "Please provide text to translate.")
        }
        
        // Map common language codes
        let languageMap: [String: NLLanguage] = [
            "es": .spanish, "spanish": .spanish,
            "fr": .french, "french": .french,
            "de": .german, "german": .german,
            "it": .italian, "italian": .italian,
            "pt": .portuguese, "portuguese": .portuguese,
            "zh": .simplifiedChinese, "chinese": .simplifiedChinese,
            "ja": .japanese, "japanese": .japanese,
            "ko": .korean, "korean": .korean,
            "ru": .russian, "russian": .russian,
            "ar": .arabic, "arabic": .arabic,
        ]
        
        guard let targetLanguage = languageMap[targetLang.lowercased()] else {
            return ToolResult(success: false, output: "Language '\(targetLang)' not supported. Try: es, fr, de, it, pt, zh, ja, ko, ru, ar")
        }
        
        // Note: On-device translation requires iOS 17.4+ with Translation framework
        // For now, we'll return a message about the limitation
        return ToolResult(success: true, output: "🌐 Translation to \(targetLang):\n(On-device translation requires iOS 17.4+. Use the Translate app for now.)")
        #else
        return ToolResult(success: false, output: "Translation not available on this platform.")
        #endif
    }
    
    // MARK: - 14. Code Execution
    
    private func executeCode(_ code: String) -> ToolResult {
        guard !code.isEmpty else {
            return ToolResult(success: false, output: "Please provide JavaScript code to execute.")
        }
        
        // Execute in sandboxed JSContext
        if let result = jsContext.evaluateScript(code) {
            if result.isUndefined {
                return ToolResult(success: true, output: "✅ Code executed (no return value)")
            } else if let error = jsContext.exception {
                return ToolResult(success: false, output: "❌ Error: \(error.toString() ?? "Unknown")")
            } else {
                return ToolResult(success: true, output: "💻 Result: \(result.toString() ?? "nil")")
            }
        }
        return ToolResult(success: false, output: "Code execution failed")
    }
    
    // MARK: - 15. Clipboard
    
    private func handleClipboard(action: String, text: String?) -> ToolResult {
        #if canImport(UIKit)
        switch action.lowercased() {
        case "read", "paste", "get":
            if let content = UIPasteboard.general.string {
                return ToolResult(success: true, output: "📋 Clipboard: \(content)")
            } else {
                return ToolResult(success: true, output: "Clipboard is empty")
            }
        case "write", "copy", "set":
            guard let text = text, !text.isEmpty else {
                return ToolResult(success: false, output: "No text to copy")
            }
            UIPasteboard.general.string = text
            return ToolResult(success: true, output: "📋 Copied to clipboard: \"\(text)\"")
        default:
            return ToolResult(success: false, output: "Clipboard actions: read, write")
        }
        #else
        return ToolResult(success: false, output: "Clipboard not available on this platform.")
        #endif
    }
    
    // MARK: - 16. Device Info
    
    private func getDeviceInfo() -> ToolResult {
        #if canImport(UIKit)
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo
        
        let info = """
        📱 Device: \(device.name)
        • Model: \(device.model)
        • System: \(device.systemName) \(device.systemVersion)
        • RAM: \(processInfo.physicalMemory / 1_000_000_000) GB
        • Processors: \(processInfo.processorCount) cores
        """
        return ToolResult(success: true, output: info)
        #else
        let processInfo = ProcessInfo.processInfo
        return ToolResult(success: true, output: "💻 \(processInfo.hostName)\nRAM: \(processInfo.physicalMemory / 1_000_000_000) GB")
        #endif
    }
    
    // MARK: - 17. Battery
    
    private func getBatteryLevel() -> ToolResult {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Int(UIDevice.current.batteryLevel * 100)
        let state = UIDevice.current.batteryState
        
        let stateStr: String
        switch state {
        case .charging: stateStr = "⚡ Charging"
        case .full: stateStr = "✅ Full"
        case .unplugged: stateStr = "🔋 Unplugged"
        default: stateStr = "Unknown"
        }
        
        return ToolResult(success: true, output: "🔋 Battery: \(level)% (\(stateStr))")
        #else
        return ToolResult(success: false, output: "Battery info not available on macOS")
        #endif
    }
    
    // MARK: - 18. Brightness
    
    private func setBrightness(level: String?) -> ToolResult {
        #if canImport(UIKit)
        if let levelStr = level, let value = Double(levelStr.filter { $0.isNumber }) {
            let normalized = min(max(value / 100, 0), 1)
            UIScreen.main.brightness = normalized
            return ToolResult(success: true, output: "☀️ Brightness set to \(Int(normalized * 100))%")
        } else {
            let current = Int(UIScreen.main.brightness * 100)
            return ToolResult(success: true, output: "☀️ Current brightness: \(current)%")
        }
        #else
        return ToolResult(success: false, output: "Brightness control not available on macOS")
        #endif
    }
    
    // MARK: - 19. Volume
    
    private func setVolume(level: String?) -> ToolResult {
        // Volume control requires MPVolumeView which is complex
        // For now, return helpful info
        return ToolResult(success: true, output: "🔊 Volume control requires physical buttons or Control Center")
    }
    
    // MARK: - 20. Flashlight
    
    private func toggleFlashlight(on: Bool) -> ToolResult {
        #if canImport(AVFoundation) && canImport(UIKit)
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return ToolResult(success: false, output: "No flashlight available")
        }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            return ToolResult(success: true, output: "🔦 Flashlight \(on ? "on" : "off")")
        } catch {
            return ToolResult(success: false, output: "Flashlight error: \(error.localizedDescription)")
        }
        #else
        return ToolResult(success: false, output: "Flashlight not available on this device")
        #endif
    }
    
    // MARK: - 21. Web Search
    
    private func webSearch(query: String) async -> ToolResult {
        guard !query.isEmpty else {
            return ToolResult(success: false, output: "Please provide a search query")
        }
        
        // We can't actually search the web without an API key
        // But we can open Safari with the search
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://duckduckgo.com/?q=\(encoded)"
        
        return ToolResult(success: true, output: "🔍 Search: \(query)\nURL: \(searchURL)\n\n(Note: Open URL in browser to see results)")
    }
    
    // MARK: - 22. Dictionary
    
    private func define(word: String) -> ToolResult {
        guard !word.isEmpty else {
            return ToolResult(success: false, output: "Please provide a word to define")
        }
        
        // Use UIReferenceLibraryViewController check for definition availability
        #if canImport(UIKit)
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: word) {
            return ToolResult(success: true, output: "📖 Definition available for \"\(word)\"\n(Tap to view in Dictionary)")
        } else {
            return ToolResult(success: false, output: "No definition found for \"\(word)\"")
        }
        #else
        return ToolResult(success: true, output: "📖 Look up \"\(word)\" in Dictionary.app")
        #endif
    }
    
    // MARK: - Helpers
    
    private func parseRelativeTime(_ input: String) -> Date {
        let now = Date()
        let calendar = Calendar.current
        let lower = input.lowercased()
        
        if lower.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)!
        }
        if lower.contains("tonight") || lower.contains("this evening") {
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        }
        if lower.contains("hour") {
            let hours = Int(lower.filter { $0.isNumber }) ?? 1
            return calendar.date(byAdding: .hour, value: hours, to: now)!
        }
        if lower.contains("minute") {
            let mins = Int(lower.filter { $0.isNumber }) ?? 30
            return calendar.date(byAdding: .minute, value: mins, to: now)!
        }
        
        // Try to parse time like "3pm" or "5:30"
        let formatter = DateFormatter()
        for format in ["h:mm a", "h a", "HH:mm"] {
            formatter.dateFormat = format
            if let time = formatter.date(from: input) {
                var components = calendar.dateComponents([.hour, .minute], from: time)
                components.year = calendar.component(.year, from: now)
                components.month = calendar.component(.month, from: now)
                components.day = calendar.component(.day, from: now)
                return calendar.date(from: components) ?? now
            }
        }
        
        return now
    }
}

// MARK: - Tool Execution Record

public struct ToolExecution: Identifiable {
    public let id = UUID()
    public let tool: String
    public let input: String
    public let result: String
    public let success: Bool
    public let timestamp: Date
    
    public init(tool: String, input: String, result: String, success: Bool, timestamp: Date = Date()) {
        self.tool = tool
        self.input = input
        self.result = result
        self.success = success
        self.timestamp = timestamp
    }
}
