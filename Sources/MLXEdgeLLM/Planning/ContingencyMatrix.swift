import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ContingencyMatrix

class ContingencyMatrix: ObservableObject {
    @Published var contingencies: [Contingency] = []
    
    func addContingency(_ contingency: Contingency) {
        contingencies.append(contingency)
    }
    
    func removeContingency(at index: Int) {
        contingencies.remove(at: index)
    }
}

// MARK: - Contingency

struct Contingency: Identifiable {
    let id = UUID()
    var triggerCondition: TriggerCondition
    var actions: [Action]
    var responsibleParties: [String]
}

// MARK: - TriggerCondition

enum TriggerCondition {
    case location(CLLocationCoordinate2D)
    case time(Date)
    case sensorData(SensorData)
    case userAction(String)
}

// MARK: - Action

struct Action {
    let type: ActionType
    let details: String
}

// MARK: - ActionType

enum ActionType {
    case alert(String)
    case executeScript(String)
    case callFunction(String)
    case sendNotification(String)
}

// MARK: - SensorData

struct SensorData {
    let type: SensorType
    let value: Double
}

// MARK: - SensorType

enum SensorType {
    case accelerometer
    case gyroscope
    case proximity
    case light
}

// MARK: - ContingencyMatrixView

struct ContingencyMatrixView: View {
    @StateObject private var matrix = ContingencyMatrix()
    
    var body: some View {
        NavigationView {
            List(matrix.contingencies) { contingency in
                ContingencyRow(contingency: contingency)
            }
            .navigationTitle("Contingency Matrix")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new contingency logic here
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - ContingencyRow

struct ContingencyRow: View {
    let contingency: Contingency
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Trigger: \(contingencyTriggerDescription(contingency.triggerCondition))")
                .font(.headline)
            Text("Actions: \(contingency.actions.map { $0.details }.joined(separator: ", "))")
                .font(.subheadline)
            Text("Responsible Parties: \(contingency.responsibleParties.joined(separator: ", "))")
                .font(.subheadline)
        }
    }
    
    func contingencyTriggerDescription(_ trigger: TriggerCondition) -> String {
        switch trigger {
        case .location(let coordinate):
            return "Location: \(coordinate.latitude), \(coordinate.longitude)"
        case .time(let date):
            return "Time: \(date, formatter: DateFormatter())"
        case .sensorData(let data):
            return "Sensor: \(data.type.rawValue), Value: \(data.value)"
        case .userAction(let action):
            return "User Action: \(action)"
        }
    }
}

// MARK: - DateFormatter

extension DateFormatter {
    init() {
        self.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }
}