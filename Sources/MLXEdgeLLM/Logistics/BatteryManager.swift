import Foundation
import SwiftUI

// MARK: - BatteryManager

final class BatteryManager: ObservableObject {
    @Published private(set) var batteryLevels: [Device: BatteryLevel] = [:]
    @Published private(set) var chargingQueue: [Device] = []
    
    private let predictionModel: BatteryDepletionModel
    
    init(predictionModel: BatteryDepletionModel) {
        self.predictionModel = predictionModel
    }
    
    func updateBatteryLevel(for device: Device, level: Double) {
        batteryLevels[device] = BatteryLevel(current: level, predictedDepletion: predictionModel.predictDepletion(for: device, currentLevel: level))
    }
    
    func enqueueForCharging(device: Device) {
        guard !chargingQueue.contains(device) else { return }
        chargingQueue.append(device)
        chargingQueue.sort { predictionModel.predictDepletion(for: $0, currentLevel: batteryLevels[$0]?.current ?? 0) < predictionModel.predictDepletion(for: $1, currentLevel: batteryLevels[$1]?.current ?? 0) }
    }
    
    func dequeueFromCharging(device: Device) {
        chargingQueue.removeAll { $0 == device }
    }
}

// MARK: - BatteryLevel

struct BatteryLevel {
    let current: Double
    let predictedDepletion: TimeInterval
}

// MARK: - Device

enum Device: Identifiable {
    case phone(id: String)
    case tablet(id: String)
    case drone(id: String)
    
    var id: String {
        switch self {
        case .phone(let id), .tablet(let id), .drone(let id):
            return id
        }
    }
}

// MARK: - BatteryDepletionModel

actor BatteryDepletionModel {
    func predictDepletion(for device: Device, currentLevel: Double) -> TimeInterval {
        // Placeholder implementation
        return 3600 // 1 hour
    }
}

// MARK: - BatteryManagerView

struct BatteryManagerView: View {
    @StateObject private var viewModel = BatteryManager(predictionModel: BatteryDepletionModel())
    
    var body: some View {
        VStack {
            List(viewModel.batteryLevels) { device, level in
                HStack {
                    Text(device.id)
                    Spacer()
                    Text("\(level.current, specifier: "%.0f")%")
                    Text("Depletes in: \(Int(level.predictedDepletion / 3600))h")
                }
            }
            
            Button("Enqueue for Charging") {
                viewModel.enqueueForCharging(device: .phone(id: "123"))
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct BatteryManagerView_Previews: PreviewProvider {
    static var previews: some View {
        BatteryManagerView()
    }
}