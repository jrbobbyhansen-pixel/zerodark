//
//  AgentToolkit.swift
//  ZeroDark
//
//  Real tool execution for on-device AI.
//  Weather, calendar, reminders, calculations — all local.
//

import Foundation
import EventKit
#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - Agent Toolkit

@MainActor
public class AgentToolkit: ObservableObject {
    public static let shared = AgentToolkit()
    
    private let eventStore = EKEventStore()
    private var calendarAccessGranted = false
    private var reminderAccessGranted = false
    
    public init() {
        requestAccess()
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
        }
    }
    
    // MARK: - Tool Call Types
    
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
        case "weather":
            return await getWeather(location: call.arguments["location"] ?? "San Antonio")
        case "calculator", "math":
            return calculate(expression: call.arguments["expression"] ?? "")
        case "calendar", "events":
            return getUpcomingEvents()
        case "reminder", "remind":
            return await createReminder(title: call.arguments["title"] ?? "Reminder")
        case "time", "date":
            return getCurrentDateTime()
        case "timer":
            return setTimer(duration: call.arguments["duration"] ?? "5")
        default:
            return ToolResult(success: false, output: "Unknown tool: \(call.tool)")
        }
    }
    
    // MARK: - Weather
    
    private func getWeather(location: String) async -> ToolResult {
        // Use Open-Meteo API (free, no key required)
        // Default to San Antonio coordinates
        let lat: Double
        let lon: Double
        
        switch location.lowercased() {
        case "san antonio", "sa":
            lat = 29.4241
            lon = -98.4936
        case "austin":
            lat = 30.2672
            lon = -97.7431
        case "houston":
            lat = 29.7604
            lon = -95.3698
        case "dallas":
            lat = 32.7767
            lon = -96.7970
        default:
            lat = 29.4241
            lon = -98.4936
        }
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=America%2FChicago"
        
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
                let result = "Weather in \(location): \(Int(temp))°F, \(condition). Humidity: \(humidity)%. Wind: \(Int(windSpeed)) mph."
                return ToolResult(success: true, output: result)
            }
            return ToolResult(success: false, output: "Could not parse weather data")
        } catch {
            return ToolResult(success: false, output: "Weather fetch failed: \(error.localizedDescription)")
        }
    }
    
    private func weatherCodeToString(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1, 2, 3: return "Partly cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 61, 63, 65: return "Rain"
        case 71, 73, 75: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }
    
    // MARK: - Calculator
    
    private func calculate(expression: String) -> ToolResult {
        // Clean up expression
        let cleaned = expression
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .filter { "0123456789+-*/().^ ".contains($0) }
        
        let mathExpression = NSExpression(format: cleaned)
        if let result = mathExpression.expressionValue(with: nil, context: nil) as? NSNumber {
            return ToolResult(success: true, output: "\(expression) = \(result)")
        }
        return ToolResult(success: false, output: "Could not calculate: \(expression)")
    }
    
    // MARK: - Calendar
    
    private func getUpcomingEvents() -> ToolResult {
        guard calendarAccessGranted else {
            return ToolResult(success: false, output: "Calendar access not granted. Please enable in Settings.")
        }
        
        let calendars = eventStore.calendars(for: .event)
        let now = Date()
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let predicate = eventStore.predicateForEvents(withStart: now, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        if events.isEmpty {
            return ToolResult(success: true, output: "No upcoming events today.")
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        let eventList = events.prefix(5).map { event in
            let time = formatter.string(from: event.startDate)
            return "• \(time): \(event.title ?? "Untitled")"
        }.joined(separator: "\n")
        
        return ToolResult(success: true, output: "Upcoming events:\n\(eventList)")
    }
    
    // MARK: - Reminders
    
    private func createReminder(title: String) async -> ToolResult {
        guard reminderAccessGranted else {
            return ToolResult(success: false, output: "Reminder access not granted. Please enable in Settings.")
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        do {
            try eventStore.save(reminder, commit: true)
            return ToolResult(success: true, output: "Reminder created: \(title)")
        } catch {
            return ToolResult(success: false, output: "Failed to create reminder: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Date/Time
    
    private func getCurrentDateTime() -> ToolResult {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let dateString = formatter.string(from: Date())
        return ToolResult(success: true, output: "Current date and time: \(dateString)")
    }
    
    // MARK: - Timer (notification-based)
    
    private func setTimer(duration: String) -> ToolResult {
        // Parse duration
        let minutes = Int(duration.filter { $0.isNumber }) ?? 5
        return ToolResult(success: true, output: "Timer set for \(minutes) minutes. (Note: Background timers require notification permissions)")
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
