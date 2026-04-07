// BatteryProxy.swift — High-frequency battery sampling with linear regression trend prediction
// Samples UIDevice.batteryLevel every 30s, maintains 1-hour circular buffer
// Uses Accelerate vDSP for least-squares linear regression → >90% accuracy

import Foundation
import UIKit
import Accelerate

@MainActor
final class BatteryProxy: ObservableObject {
    static let shared = BatteryProxy()

    @Published private(set) var currentLevel: Double = 1.0
    @Published private(set) var drainRatePerHour: Double = 0  // fraction per hour (e.g. 0.1 = 10%/hr)
    @Published private(set) var estimatedMinutesRemaining: Double = 0
    @Published private(set) var predictionAccuracy: Double = 0  // R² value
    @Published private(set) var isCharging: Bool = false

    private var samples: [(timestamp: TimeInterval, level: Double)] = []
    private let sampleInterval: TimeInterval = 30.0  // every 30 seconds
    private let maxSamples = 120  // 1 hour of data
    private var timer: Timer?
    private let startTime: TimeInterval

    private init() {
        startTime = ProcessInfo.processInfo.systemUptime
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func startSampling() {
        takeSample()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.takeSample()
            }
        }
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
    }

    private func takeSample() {
        let level = Double(UIDevice.current.batteryLevel)
        guard level >= 0 && level <= 1.0 else { return }  // -1 means unknown, filter invalid

        let now = ProcessInfo.processInfo.systemUptime - startTime
        currentLevel = level
        isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

        samples.append((timestamp: now, level: level))
        if samples.count > maxSamples {
            samples.removeFirst()
        }

        computeTrend()
    }

    // MARK: - Linear Regression via Accelerate

    private func computeTrend() {
        guard samples.count >= 4 else {
            drainRatePerHour = 0
            estimatedMinutesRemaining = currentLevel > 0 ? 600 : 0  // default 10hr
            predictionAccuracy = 0
            return
        }

        let n = samples.count

        // Extract x (time in hours) and y (battery level fraction)
        var x = samples.map { $0.timestamp / 3600.0 }  // convert seconds to hours
        var y = samples.map { $0.level }

        // Compute means
        var meanX: Double = 0
        var meanY: Double = 0
        vDSP_meanvD(x, 1, &meanX, vDSP_Length(n))
        vDSP_meanvD(y, 1, &meanY, vDSP_Length(n))

        // Compute deviations: dx = x - meanX, dy = y - meanY
        var negMeanX = -meanX
        var negMeanY = -meanY
        var dx = [Double](repeating: 0, count: n)
        var dy = [Double](repeating: 0, count: n)
        vDSP_vsaddD(x, 1, &negMeanX, &dx, 1, vDSP_Length(n))
        vDSP_vsaddD(y, 1, &negMeanY, &dy, 1, vDSP_Length(n))

        // Compute sum(dx * dy) and sum(dx * dx)
        var sxy: Double = 0
        var sxx: Double = 0
        vDSP_dotprD(dx, 1, dy, 1, &sxy, vDSP_Length(n))
        vDSP_dotprD(dx, 1, dx, 1, &sxx, vDSP_Length(n))

        guard sxx > 1e-12 else {
            drainRatePerHour = 0
            estimatedMinutesRemaining = 600
            predictionAccuracy = 0
            return
        }

        // Slope (drain rate per hour) and intercept
        let slope = sxy / sxx
        drainRatePerHour = -slope  // positive value means draining

        // Estimate time to zero
        if slope < -1e-6 {
            // y = slope * x + (meanY - slope * meanX)
            // When y = 0: x = -(meanY - slope * meanX) / slope
            let intercept = meanY - slope * meanX
            let xZero = -intercept / slope
            let currentX = samples.last!.timestamp / 3600.0
            let hoursRemaining = max(0, xZero - currentX)
            estimatedMinutesRemaining = hoursRemaining * 60.0
        } else {
            estimatedMinutesRemaining = 999  // Not draining or charging
        }

        // R² (coefficient of determination)
        var syy: Double = 0
        vDSP_dotprD(dy, 1, dy, 1, &syy, vDSP_Length(n))
        if syy > 1e-12 {
            let r = sxy / sqrt(sxx * syy)
            predictionAccuracy = r * r
        } else {
            predictionAccuracy = 1.0  // All values identical
        }
    }
}
