import Foundation
import SwiftUI

// MARK: - MaintenanceLogger

class MaintenanceLogger: ObservableObject {
    @Published var equipmentList: [Equipment] = []
    @Published var overdueItems: [Equipment] = []
    
    init() {
        loadEquipment()
        checkOverdueItems()
    }
    
    func loadEquipment() {
        // Simulate loading equipment from a persistent store
        equipmentList = [
            Equipment(name: "Rifle", lastMaintenance: Date().addingTimeInterval(-86400 * 30), maintenanceInterval: 86400 * 30),
            Equipment(name: "Helmet", lastMaintenance: Date().addingTimeInterval(-86400 * 15), maintenanceInterval: 86400 * 30)
        ]
    }
    
    func checkOverdueItems() {
        let now = Date()
        overdueItems = equipmentList.filter { $0.nextMaintenanceDate < now }
    }
    
    func logMaintenance(for equipment: Equipment) {
        equipment.lastMaintenance = Date()
        checkOverdueItems()
    }
    
    func exportReport() -> String {
        var report = "Maintenance Report:\n"
        for equipment in equipmentList {
            report += "\(equipment.name): Last Maintained \(equipment.lastMaintenance), Next Due \(equipment.nextMaintenanceDate)\n"
        }
        return report
    }
}

// MARK: - Equipment

struct Equipment: Identifiable, Codable {
    let id = UUID()
    var name: String
    var lastMaintenance: Date
    var maintenanceInterval: TimeInterval
    
    var nextMaintenanceDate: Date {
        return lastMaintenance.addingTimeInterval(maintenanceInterval)
    }
}

// MARK: - MaintenanceLoggerView

struct MaintenanceLoggerView: View {
    @StateObject private var logger = MaintenanceLogger()
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Equipment List")) {
                    ForEach(logger.equipmentList) { equipment in
                        HStack {
                            Text(equipment.name)
                            Spacer()
                            Text("Next Due: \(equipment.nextMaintenanceDate, style: .date)")
                        }
                        .foregroundColor(equipment.nextMaintenanceDate < Date() ? .red : .black)
                    }
                }
                
                Section(header: Text("Overdue Items")) {
                    ForEach(logger.overdueItems) { equipment in
                        HStack {
                            Text(equipment.name)
                            Spacer()
                            Text("Overdue Since: \(equipment.lastMaintenance, style: .date)")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Maintenance Logger")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Simulate exporting report
                        let report = logger.exportReport()
                        print(report)
                    }) {
                        Label("Export Report", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct MaintenanceLoggerView_Previews: PreviewProvider {
    static var previews: some View {
        MaintenanceLoggerView()
    }
}