import Foundation
import SwiftUI

// MARK: - GasDetector

class GasDetector: ObservableObject {
    @Published var oxygenLevel: Double = 0.0
    @Published var carbonMonoxideLevel: Double = 0.0
    @Published var hydrogenSulfideLevel: Double = 0.0
    @Published var lowerExplosiveLimit: Double = 0.0
    @Published var isAlarmActive: Bool = false
    @Published var calibrationDate: Date = Date()
    
    private let sensorManager: SensorManager
    
    init(sensorManager: SensorManager) {
        self.sensorManager = sensorManager
        self.sensorManager.delegate = self
    }
    
    func startMonitoring() {
        sensorManager.startMonitoring()
    }
    
    func stopMonitoring() {
        sensorManager.stopMonitoring()
    }
    
    func calibrate() {
        sensorManager.calibrate()
        calibrationDate = Date()
    }
}

// MARK: - SensorManager

class SensorManager: NSObject {
    weak var delegate: SensorManagerDelegate?
    
    func startMonitoring() {
        // Start monitoring logic here
    }
    
    func stopMonitoring() {
        // Stop monitoring logic here
    }
    
    func calibrate() {
        // Calibration logic here
    }
}

// MARK: - SensorManagerDelegate

protocol SensorManagerDelegate: AnyObject {
    func sensorManager(_ manager: SensorManager, didUpdateOxygenLevel level: Double)
    func sensorManager(_ manager: SensorManager, didUpdateCarbonMonoxideLevel level: Double)
    func sensorManager(_ manager: SensorManager, didUpdateHydrogenSulfideLevel level: Double)
    func sensorManager(_ manager: SensorManager, didUpdateLowerExplosiveLimit level: Double)
    func sensorManager(_ manager: SensorManager, didTriggerAlarm isActive: Bool)
}

// MARK: - SensorManagerDelegate Extension

extension GasDetector: SensorManagerDelegate {
    func sensorManager(_ manager: SensorManager, didUpdateOxygenLevel level: Double) {
        oxygenLevel = level
    }
    
    func sensorManager(_ manager: SensorManager, didUpdateCarbonMonoxideLevel level: Double) {
        carbonMonoxideLevel = level
    }
    
    func sensorManager(_ manager: SensorManager, didUpdateHydrogenSulfideLevel level: Double) {
        hydrogenSulfideLevel = level
    }
    
    func sensorManager(_ manager: SensorManager, didUpdateLowerExplosiveLimit level: Double) {
        lowerExplosiveLimit = level
    }
    
    func sensorManager(_ manager: SensorManager, didTriggerAlarm isActive: Bool) {
        isAlarmActive = isActive
    }
}

// MARK: - GasDetectorView

struct GasDetectorView: View {
    @StateObject private var gasDetector = GasDetector(sensorManager: SensorManager())
    
    var body: some View {
        VStack {
            Text("Gas Detector")
                .font(.largeTitle)
                .padding()
            
            HStack {
                VStack {
                    Text("Oxygen Level")
                        .font(.headline)
                    Text("\(gasDetector.oxygenLevel, specifier: "%.2f") %")
                        .font(.title)
                }
                VStack {
                    Text("CO Level")
                        .font(.headline)
                    Text("\(gasDetector.carbonMonoxideLevel, specifier: "%.2f") ppm")
                        .font(.title)
                }
                VStack {
                    Text("H2S Level")
                        .font(.headline)
                    Text("\(gasDetector.hydrogenSulfideLevel, specifier: "%.2f") ppm")
                        .font(.title)
                }
                VStack {
                    Text("LEL")
                        .font(.headline)
                    Text("\(gasDetector.lowerExplosiveLimit, specifier: "%.2f") %")
                        .font(.title)
                }
            }
            .padding()
            
            Button(action: {
                gasDetector.calibrate()
            }) {
                Text("Calibrate")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
            
            if gasDetector.isAlarmActive {
                Text("ALARM ACTIVE")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .onAppear {
            gasDetector.startMonitoring()
        }
        .onDisappear {
            gasDetector.stopMonitoring()
        }
    }
}

// MARK: - Preview

struct GasDetectorView_Previews: PreviewProvider {
    static var previews: some View {
        GasDetectorView()
    }
}