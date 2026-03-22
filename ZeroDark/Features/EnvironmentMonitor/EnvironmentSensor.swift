import Foundation
import CoreMotion
import Observation

enum EventType: String, Codable, CaseIterable {
    case pressureDrop = "Pressure Drop"
    case vibrationSpike = "Vibration Spike"
    case orientationChange = "Orientation Change"
    case magneticAnomaly = "Magnetic Anomaly"

    var icon: String {
        switch self {
        case .pressureDrop: return "barometer"
        case .vibrationSpike: return "waveform.path.ecg"
        case .orientationChange: return "gyroscope"
        case .magneticAnomaly: return "compass.drawing"
        }
    }
}

struct EnvironmentEvent: Codable, Identifiable {
    let id: UUID
    let type: EventType
    let timestamp: Date
    let value: Double
    let unit: String

    init(type: EventType, value: Double, unit: String, timestamp: Date = .now) {
        self.id = UUID()
        self.type = type
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
    }
}

@Observable
final class EnvironmentSensor {
    var isMonitoring = false
    var currentPressure: Double = 0       // hPa
    var currentAltitude: Double = 0       // meters (relative)
    var currentAccel: Double = 0          // g RMS
    var currentHeading: Double = 0        // degrees
    var events: [EnvironmentEvent] = []   // single source of truth — use for both log and vault save

    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let vault = VaultManager.shared
    private var sessionStart: Date?

    // Thresholds
    private let vibrationThreshold = 0.15          // g RMS
    private let pressureAnomalyThreshold = 2.0     // hPa delta in 10s window
    private let orientationThreshold = 2.0         // rad/s
    private let magneticAnomalyThreshold = 100.0   // µT delta

    // State tracking
    private var accelWindow: [Double] = []
    private var lastPressure: Double?
    private var pressureTimestamp: Date?
    private var baseMagneticField: Double?
    private var gyroSustainedStart: Date?

    // Cooldown: prevent event floods (2s minimum between same event type)
    private var lastEventTime: [EventType: Date] = [:]
    private let eventCooldown: TimeInterval = 2.0

    func startMonitoring() {
        guard !isMonitoring else { return }
        sessionStart = Date()
        events = []
        lastEventTime = [:]
        startAltimeter()
        startMotion()
        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        isMonitoring = false
        saveLog()
    }

    // MARK: - Private

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        // Deliver on main — no inner DispatchQueue.main.async needed
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let pressure = data.pressure.doubleValue * 10.0  // kPa → hPa
            currentPressure = pressure
            currentAltitude = data.relativeAltitude.doubleValue

            if let last = lastPressure, let ts = pressureTimestamp {
                if Date().timeIntervalSince(ts) >= 10.0 {
                    let delta = abs(pressure - last)
                    if delta > pressureAnomalyThreshold {
                        addEvent(EnvironmentEvent(type: .pressureDrop, value: delta, unit: "hPa"))
                    }
                    lastPressure = pressure
                    pressureTimestamp = Date()
                }
            } else {
                lastPressure = pressure
                pressureTimestamp = Date()
            }
        }
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1  // 10 Hz
        // Deliver on main — no inner DispatchQueue.main.async needed
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            // Vibration: RMS over 0.5s window (5 samples at 10Hz)
            let accel = motion.userAcceleration
            let mag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            accelWindow.append(mag)
            if accelWindow.count > 5 { accelWindow.removeFirst() }

            let rms = sqrt(accelWindow.map { $0 * $0 }.reduce(0, +) / Double(accelWindow.count))
            currentAccel = rms

            if rms > vibrationThreshold && accelWindow.count == 5 {
                addEvent(EnvironmentEvent(type: .vibrationSpike, value: rms, unit: "g RMS"))
            }

            // Orientation: gyro sustained > 200ms
            let gyro = motion.rotationRate
            let gyroMag = sqrt(gyro.x * gyro.x + gyro.y * gyro.y + gyro.z * gyro.z)
            if gyroMag > orientationThreshold {
                if let start = gyroSustainedStart, Date().timeIntervalSince(start) >= 0.2 {
                    addEvent(EnvironmentEvent(type: .orientationChange, value: gyroMag, unit: "rad/s"))
                    gyroSustainedStart = nil
                } else if gyroSustainedStart == nil {
                    gyroSustainedStart = Date()
                }
            } else {
                gyroSustainedStart = nil
            }

            // Magnetic anomaly
            let field = motion.magneticField.field
            let fieldMag = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
            if let base = baseMagneticField {
                if abs(fieldMag - base) > magneticAnomalyThreshold {
                    addEvent(EnvironmentEvent(type: .magneticAnomaly, value: abs(fieldMag - base), unit: "µT"))
                    baseMagneticField = fieldMag
                }
            } else {
                baseMagneticField = fieldMag
            }

            currentHeading = motion.attitude.yaw * (180 / .pi)
        }
    }

    private func addEvent(_ event: EnvironmentEvent) {
        // Cooldown check — max one event per type per 2 seconds
        let now = Date()
        if let last = lastEventTime[event.type], now.timeIntervalSince(last) < eventCooldown {
            return
        }
        lastEventTime[event.type] = now
        events.insert(event, at: 0)
    }

    private func saveLog() {
        guard !events.isEmpty, let start = sessionStart else { return }
        let formatter = ISO8601DateFormatter()
        try? vault.saveJSON(events, filename: "environment_\(formatter.string(from: start)).json")
    }
}
