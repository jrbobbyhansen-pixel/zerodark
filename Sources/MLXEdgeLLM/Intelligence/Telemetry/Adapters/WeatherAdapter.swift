// WeatherAdapter.swift — Weather telemetry adapter (reads from WeatherService)

import Foundation

class WeatherTelemetryAdapter: BaseTelemetryAdapter {
    private var timer: Timer?

    override init(objectType: TelemetryObjectType) {
        super.init(objectType: objectType)
    }

    override func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            if let conditions = WeatherService.shared.currentConditions {
                // Emit weather as JSON
                let data: [String: Any] = [
                    "temperature": conditions.temperature,
                    "humidity": conditions.humidity,
                    "wind_speed": conditions.windSpeed,
                    "conditions": conditions.description
                ]

                if let jsonData = try? JSONSerialization.data(withJSONObject: data),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    self?.emit(.string(jsonString))
                }
            }
        }
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }
}
