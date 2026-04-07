// HotZoneClassifier.swift — MLX-based zone classification from sensor telemetry
// Uses LocalInferenceEngine for classification, falls back to rule-based logic

import Foundation
import CoreLocation
import Combine

// MARK: - Sensor Reading

struct HazmatSensorReading {
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D
    let gasConcentrationPPM: Double?     // Gas detector reading
    let radiationUSvH: Double?           // Radiation dosimeter (µSv/h)
    let temperatureCelsius: Double?      // Thermal reading
    let oxygenPercent: Double?           // O2 level
}

// MARK: - Zone Classification

struct ZoneClassification: Identifiable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
    let type: HazmatZoneType
    let confidence: Double
    let reason: String
    let timestamp: Date
}

enum HazmatZoneType: String, CaseIterable {
    case hot    // Immediate danger, PPE required
    case warm   // Decontamination corridor
    case cold   // Safe staging area

    var color: (r: Double, g: Double, b: Double, a: Double) {
        switch self {
        case .hot:  return (1.0, 0.0, 0.0, 0.3)
        case .warm: return (1.0, 0.6, 0.0, 0.25)
        case .cold: return (0.0, 0.8, 0.0, 0.2)
        }
    }
}

// MARK: - HotZone Classifier

@MainActor
final class HotZoneClassifier: ObservableObject {
    static let shared = HotZoneClassifier()

    @Published var classifications: [ZoneClassification] = []
    @Published var isClassifying = false

    // Thresholds for rule-based fallback
    private let gasHotThreshold: Double = 100.0      // PPM
    private let gasWarmThreshold: Double = 25.0
    private let radiationHotThreshold: Double = 20.0  // µSv/h
    private let radiationWarmThreshold: Double = 1.0
    private let tempHotThreshold: Double = 60.0       // °C
    private let oxygenDangerThreshold: Double = 19.5  // %

    private init() {}

    // MARK: - Classify Reading

    func classify(_ reading: HazmatSensorReading) async -> ZoneClassification {
        isClassifying = true
        defer { isClassifying = false }

        // Try MLX classification first
        if let mlxResult = await classifyWithMLX(reading) {
            let classification = ZoneClassification(
                center: reading.coordinate,
                radiusMeters: 50,
                type: mlxResult.type,
                confidence: mlxResult.confidence,
                reason: mlxResult.reason,
                timestamp: reading.timestamp
            )
            classifications.append(classification)
            return classification
        }

        // Fallback to rule-based
        let result = classifyRuleBased(reading)
        classifications.append(result)
        return result
    }

    // MARK: - MLX Classification

    private struct MLXClassResult {
        let type: HazmatZoneType
        let confidence: Double
        let reason: String
    }

    private func classifyWithMLX(_ reading: HazmatSensorReading) async -> MLXClassResult? {
        let engine = LocalInferenceEngine.shared
        guard engine.modelState == .ready else { return nil }

        // Build prompt for LLM classification
        var prompt = "Classify this hazmat sensor reading into HOT, WARM, or COLD zone. Reply with only the zone type and confidence (0-1).\n"
        if let gas = reading.gasConcentrationPPM { prompt += "Gas: \(gas) PPM\n" }
        if let rad = reading.radiationUSvH { prompt += "Radiation: \(rad) µSv/h\n" }
        if let temp = reading.temperatureCelsius { prompt += "Temperature: \(temp)°C\n" }
        if let o2 = reading.oxygenPercent { prompt += "Oxygen: \(o2)%\n" }

        // Use streaming API and collect tokens
        var response = ""
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.generate(prompt: prompt, maxTokens: 64, onToken: { token in
                response += token
            }, onComplete: {
                continuation.resume()
            })
        }

        guard !response.isEmpty else { return nil }

        // Parse response
        let upper = response.uppercased()
        let type: HazmatZoneType
        if upper.contains("HOT") { type = .hot }
        else if upper.contains("WARM") { type = .warm }
        else { type = .cold }

        // Extract confidence if present (look for 0.XX pattern)
        let confidence: Double
        if let range = response.range(of: #"0\.\d+"#, options: .regularExpression) {
            confidence = Double(response[range]) ?? 0.8
        } else {
            confidence = 0.8
        }

        return MLXClassResult(type: type, confidence: confidence, reason: "MLX classification: \(response.prefix(50))")
    }

    // MARK: - Rule-Based Fallback

    private func classifyRuleBased(_ reading: HazmatSensorReading) -> ZoneClassification {
        var type: HazmatZoneType = .cold
        var reason = "No hazardous readings detected"

        // Gas concentration
        if let gas = reading.gasConcentrationPPM {
            if gas >= gasHotThreshold {
                type = .hot
                reason = "Gas concentration \(Int(gas)) PPM exceeds hot threshold"
            } else if gas >= gasWarmThreshold {
                type = max(type, .warm)
                reason = "Gas concentration \(Int(gas)) PPM in warm range"
            }
        }

        // Radiation
        if let rad = reading.radiationUSvH {
            if rad >= radiationHotThreshold {
                type = .hot
                reason = "Radiation \(String(format: "%.1f", rad)) µSv/h exceeds hot threshold"
            } else if rad >= radiationWarmThreshold {
                type = max(type, .warm)
                reason = "Radiation \(String(format: "%.1f", rad)) µSv/h in warm range"
            }
        }

        // Temperature
        if let temp = reading.temperatureCelsius, temp >= tempHotThreshold {
            type = .hot
            reason = "Temperature \(Int(temp))°C exceeds hot threshold"
        }

        // Oxygen depletion
        if let o2 = reading.oxygenPercent, o2 < oxygenDangerThreshold {
            type = .hot
            reason = "Oxygen \(String(format: "%.1f", o2))% below safety threshold"
        }

        return ZoneClassification(
            center: reading.coordinate,
            radiusMeters: 50,
            type: type,
            confidence: 0.9,
            reason: reason,
            timestamp: reading.timestamp
        )
    }
}

// MARK: - Comparable for HazmatZoneType

extension HazmatZoneType: Comparable {
    static func < (lhs: HazmatZoneType, rhs: HazmatZoneType) -> Bool {
        let order: [HazmatZoneType] = [.cold, .warm, .hot]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

private func max(_ a: HazmatZoneType, _ b: HazmatZoneType) -> HazmatZoneType {
    a > b ? a : b
}
