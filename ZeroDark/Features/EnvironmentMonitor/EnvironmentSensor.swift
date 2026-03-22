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
    var currentAccel: Double = 0          // g
    var currentHeading: Double = 0        // degrees
    var recentEvents: [EnvironmentEvent] = []

    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let vault = VaultManager.shared
    private var sessionStart: Date?
    private var allEvents: [EnvironmentEvent] = []

    // Thresholds
    private let vibrationThreshold = 0.15          // g RMS
    private let pressureAnomaly = 2.0              // hPa delta in window
    private let orientationThreshold = 2.0         // rad/s
    private let magneticAnomalyThreshold = 100.0   // µT delta

    // State tracking for anomaly detection
    private var accelWindow: [Double] = []
    private var lastPressure: Double? = nil
    private var pressureTimestamp: Date? = nil
    private var baseMagneticField: Double? = nil
    private var gyroSustainedStart: Date? = nil

    func startMonitoring() {
        guard !isMonitoring else { return }
        sessionStart = Date()
        allEvents = []
        recentEvents = []

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
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let pressure = data.pressure.doubleValue * 10.0  // kPa → hPa

            DispatchQueue.main.async {
                self.currentPressure = pressure
                self.currentAltitude = data.relativeAltitude.doubleValue

                // Check pressure anomaly: >2 hPa in 10 seconds
                if let last = self.lastPressure, let ts = self.pressureTimestamp {
                    let elapsed = Date().timeIntervalSince(ts)
                    if elapsed >= 10.0 {
                        let delta = abs(pressure - last)
                        if delta > self.pressureAnomaly {
                            self.addEvent(EnvironmentEvent(type: .pressureDrop, value: delta, unit: "hPa"))
                        }
                        self.lastPressure = pressure
                        self.pressureTimestamp = Date()
                    }
                } else {
                    self.lastPressure = pressure
                    self.pressureTimestamp = Date()
                }
            }
        }
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1  // 10 Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            // Acceleration magnitude (total g, includes gravity removed)
            let accel = motion.userAcceleration
            let mag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            accelWindow.append(mag)
            if accelWindow.count > 5 { accelWindow.removeFirst() }  // 0.5s window at 10Hz

            let rms = sqrt(accelWindow.map { $0 * $0 }.reduce(0, +) / Double(accelWindow.count))
            currentAccel = rms

            if rms > vibrationThreshold && accelWindow.count == 5 {
                addEvent(EnvironmentEvent(type: .vibrationSpike, value: rms, unit: "g RMS"))
            }

            // Gyroscope — sustained rotation
            let gyro = motion.rotationRate
            let gyroMag = sqrt(gyro.x * gyro.x + gyro.y * gyro.y + gyro.z * gyro.z)
            if gyroMag > orientationThreshold {
                if let start = gyroSustainedStart {
                    if Date().timeIntervalSince(start) >= 0.2 {
                        addEvent(EnvironmentEvent(type: .orientationChange, value: gyroMag, unit: "rad/s"))
                        gyroSustainedStart = nil
                    }
                } else {
                    gyroSustainedStart = Date()
                }
            } else {
                gyroSustainedStart = nil
            }

            // Magnetometer
            let field = motion.magneticField.field
            let fieldMag = sqrt(field.x * field.x + field.y * field.y + field.z * field.z)
            if let base = baseMagneticField {
                if abs(fieldMag - base) > magneticAnomalyThreshold {
                    addEvent(EnvironmentEvent(type: .magneticAnomaly, value: abs(fieldMag - base), unit: "µT"))
                    baseMagneticField = fieldMag  // re-baseline after detection
                }
            } else {
                baseMagneticField = fieldMag
            }

            // Heading from attitude
            let attitude = motion.attitude
            currentHeading = attitude.yaw * (180 / .pi)
        }
    }

    private func addEvent(_ event: EnvironmentEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            recentEvents.insert(event, at: 0)
            if recentEvents.count > 100 { recentEvents.removeLast() }
            allEvents.append(event)
        }
    }

    private func saveLog() {
        guard !allEvents.isEmpty, let start = sessionStart else { return }
        let formatter = ISO8601DateFormatter()
        let filename = "environment_\(formatter.string(from: start)).json"
        try? vault.saveJSON(allEvents, filename: filename)
    }
}
