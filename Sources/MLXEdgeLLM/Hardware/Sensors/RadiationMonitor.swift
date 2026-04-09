import Foundation
import SwiftUI

// MARK: - RadiationMonitor

class RadiationMonitor: ObservableObject {
    @Published var doseRate: Double = 0.0
    @Published var accumulatedDose: Double = 0.0
    @Published var isAlarmActive: Bool = false
    @Published var lastCalibrationDate: Date?

    private var sensor: RadiationSensor?

    init() {
        setupSensor()
    }

    func setupSensor() {
        // Initialize the radiation sensor
        sensor = RadiationSensor()
        sensor?.delegate = self
    }

    func calibrateBackground() {
        // Perform background calibration
        sensor?.calibrate()
        lastCalibrationDate = Date()
    }

    func logExposure() {
        // Log the current exposure
        let exposureRecord = ExposureRecord(doseRate: doseRate, accumulatedDose: accumulatedDose, timestamp: Date())
        // Save or process the exposure record
        print("Exposure logged: \(exposureRecord)")
    }
}

// MARK: - RadiationSensor

class RadiationSensor {
    weak var delegate: RadiationSensorDelegate?

    func calibrate() {
        // Perform calibration logic
        print("Calibrating radiation sensor...")
    }

    func detectRadiation() {
        // Simulate radiation detection
        let doseRate = Double.random(in: 0.0...10.0)
        delegate?.radiationSensor(self, didDetectDoseRate: doseRate)
    }
}

// MARK: - RadiationSensorDelegate

protocol RadiationSensorDelegate: AnyObject {
    func radiationSensor(_ sensor: RadiationSensor, didDetectDoseRate doseRate: Double)
}

// MARK: - ExposureRecord

struct ExposureRecord: Codable {
    let doseRate: Double
    let accumulatedDose: Double
    let timestamp: Date
}

// MARK: - RadiationMonitorView

struct RadiationMonitorView: View {
    @StateObject private var monitor = RadiationMonitor()

    var body: some View {
        VStack {
            Text("Dose Rate: \(monitor.doseRate, specifier: "%.2f") mSv/h")
                .font(.headline)
            Text("Accumulated Dose: \(monitor.accumulatedDose, specifier: "%.2f") mSv")
                .font(.subheadline)
            Button("Calibrate Background") {
                monitor.calibrateBackground()
            }
            Button("Log Exposure") {
                monitor.logExposure()
            }
            .disabled(monitor.doseRate == 0.0)
        }
        .padding()
        .onAppear {
            // Simulate radiation detection
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                monitor.sensor?.detectRadiation()
            }
        }
    }
}

// MARK: - RadiationSensorDelegate Implementation

extension RadiationMonitor: RadiationSensorDelegate {
    func radiationSensor(_ sensor: RadiationSensor, didDetectDoseRate doseRate: Double) {
        self.doseRate = doseRate
        accumulatedDose += doseRate
        isAlarmActive = doseRate > 5.0 // Example threshold
    }
}