import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - GeneratorMonitor

class GeneratorMonitor: ObservableObject {
    @Published var fuelLevel: Double = 100.0
    @Published var outputPower: Double = 1000.0
    @Published var runtime: TimeInterval = 0
    @Published var needsRefuel: Bool = false
    @Published var maintenanceDue: Bool = false
    @Published var loadPercentage: Double = 50.0

    private var refuelThreshold: Double = 20.0
    private var maintenanceThreshold: TimeInterval = 24 * 60 * 60 // 24 hours

    private var startTime: Date?

    init() {
        startTime = Date()
    }

    func updateFuelLevel(_ level: Double) {
        fuelLevel = level
        needsRefuel = fuelLevel <= refuelThreshold
    }

    func updateOutputPower(_ power: Double) {
        outputPower = power
    }

    func updateLoad(_ load: Double) {
        loadPercentage = load
    }

    func checkMaintenance() {
        if let startTime = startTime {
            let elapsedTime = Date().timeIntervalSince(startTime)
            maintenanceDue = elapsedTime >= maintenanceThreshold
        }
    }
}

// MARK: - GeneratorMonitorView

struct GeneratorMonitorView: View {
    @StateObject private var monitor = GeneratorMonitor()

    var body: some View {
        VStack {
            Text("Generator Status")
                .font(.largeTitle)
                .padding()

            HStack {
                VStack {
                    Text("Fuel Level")
                        .font(.headline)
                    Text("\(Int(monitor.fuelLevel))%")
                        .font(.title)
                }
                VStack {
                    Text("Output Power")
                        .font(.headline)
                    Text("\(Int(monitor.outputPower)) W")
                        .font(.title)
                }
            }
            .padding()

            HStack {
                VStack {
                    Text("Runtime")
                        .font(.headline)
                    Text(Formatter.time.string(from: monitor.runtime))
                        .font(.title)
                }
                VStack {
                    Text("Load")
                        .font(.headline)
                    Text("\(Int(monitor.loadPercentage))%")
                        .font(.title)
                }
            }
            .padding()

            HStack {
                Text("Refuel Needed: \(monitor.needsRefuel ? "Yes" : "No")")
                    .font(.headline)
                Text("Maintenance Due: \(monitor.maintenanceDue ? "Yes" : "No")")
                    .font(.headline)
            }
            .padding()

            Button(action: {
                monitor.updateFuelLevel(100.0)
                monitor.updateOutputPower(1000.0)
                monitor.updateLoad(50.0)
                monitor.startTime = Date()
            }) {
                Text("Reset")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .onAppear {
            monitor.checkMaintenance()
        }
    }
}

// MARK: - Formatter

private extension Formatter {
    static let time: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter
    }()
}