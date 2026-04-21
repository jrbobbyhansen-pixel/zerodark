// WeatherService.swift — Offline-Capable Weather & Conditions
// Uses wttr.in for network weather, caches for offline, calculates sun times

import Foundation
import CoreLocation

struct WeatherConditions {
    let temperature: Int           // Fahrenheit
    let description: String        // "Partly Cloudy"
    let windSpeed: Int             // mph
    let windDirection: String      // "NW"
    let humidity: Int              // percent
    let sunrise: Date
    let sunset: Date
    let moonPhase: String
    let lastUpdated: Date
}

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published var currentConditions: WeatherConditions?
    @Published var isLoading = false
    @Published var lastError: String?

    private let cacheKey = "cached_weather"
    private var lastFetchLocation: CLLocationCoordinate2D?

    private init() {
        loadCachedConditions()
    }

    func fetchConditions(for location: CLLocationCoordinate2D? = nil) {
        let loc = location ?? LocationManager.shared.currentLocation
        guard let coordinate = loc else {
            lastError = "Location unavailable"
            return
        }

        isLoading = true
        lastFetchLocation = coordinate

        Task {
            do {
                let conditions = try await fetchFromWttr(coordinate: coordinate)
                await MainActor.run {
                    self.currentConditions = conditions
                    self.isLoading = false
                    self.cacheConditions(conditions)
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isLoading = false
                    // Use cached data if available
                    if self.currentConditions == nil {
                        self.loadCachedConditions()
                    }
                }
            }
        }
    }

    private func fetchFromWttr(coordinate: CLLocationCoordinate2D) async throws -> WeatherConditions {
        // wttr.in format: ?format=j1 returns JSON
        let urlString = "https://wttr.in/\(coordinate.latitude),\(coordinate.longitude)?format=j1"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await PinnedURLSession.shared.session.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let current = (json?["current_condition"] as? [[String: Any]])?.first,
              let weather = (json?["weather"] as? [[String: Any]])?.first,
              let astronomy = (weather["astronomy"] as? [[String: Any]])?.first else {
            throw URLError(.cannotParseResponse)
        }

        // Parse temperature (comes in C, convert to F)
        let tempC = Int(current["temp_F"] as? String ?? "70") ?? 70

        // Parse wind
        let windMph = Int(current["windspeedMiles"] as? String ?? "0") ?? 0
        let windDir = current["winddir16Point"] as? String ?? "N"

        // Parse description
        let desc = (current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String ?? "Unknown"

        // Parse humidity
        let humidity = Int(current["humidity"] as? String ?? "50") ?? 50

        // Parse sun times
        let sunriseStr = astronomy["sunrise"] as? String ?? "06:00 AM"
        let sunsetStr = astronomy["sunset"] as? String ?? "07:00 PM"
        let moonPhase = astronomy["moon_phase"] as? String ?? "Unknown"

        let sunrise = parseTime(sunriseStr) ?? Date()
        let sunset = parseTime(sunsetStr) ?? Date()

        return WeatherConditions(
            temperature: tempC,
            description: desc,
            windSpeed: windMph,
            windDirection: windDir,
            humidity: humidity,
            sunrise: sunrise,
            sunset: sunset,
            moonPhase: moonPhase,
            lastUpdated: Date()
        )
    }

    private func parseTime(_ timeStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        if let time = formatter.date(from: timeStr) {
            // Combine with today's date
            let calendar = Calendar.current
            let now = Date()
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            return calendar.date(from: components)
        }
        return nil
    }

    private func cacheConditions(_ conditions: WeatherConditions) {
        // Simple cache to UserDefaults
        let dict: [String: Any] = [
            "temperature": conditions.temperature,
            "description": conditions.description,
            "windSpeed": conditions.windSpeed,
            "windDirection": conditions.windDirection,
            "humidity": conditions.humidity,
            "sunrise": conditions.sunrise.timeIntervalSince1970,
            "sunset": conditions.sunset.timeIntervalSince1970,
            "moonPhase": conditions.moonPhase,
            "lastUpdated": conditions.lastUpdated.timeIntervalSince1970
        ]
        UserDefaults.standard.set(dict, forKey: cacheKey)
    }

    private func loadCachedConditions() {
        guard let dict = UserDefaults.standard.dictionary(forKey: cacheKey) else { return }

        currentConditions = WeatherConditions(
            temperature: dict["temperature"] as? Int ?? 70,
            description: dict["description"] as? String ?? "Unknown",
            windSpeed: dict["windSpeed"] as? Int ?? 0,
            windDirection: dict["windDirection"] as? String ?? "N",
            humidity: dict["humidity"] as? Int ?? 50,
            sunrise: Date(timeIntervalSince1970: dict["sunrise"] as? TimeInterval ?? 0),
            sunset: Date(timeIntervalSince1970: dict["sunset"] as? TimeInterval ?? 0),
            moonPhase: dict["moonPhase"] as? String ?? "Unknown",
            lastUpdated: Date(timeIntervalSince1970: dict["lastUpdated"] as? TimeInterval ?? 0)
        )
    }
}
