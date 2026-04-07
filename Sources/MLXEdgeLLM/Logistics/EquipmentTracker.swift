import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - EquipmentTracker

class EquipmentTracker: ObservableObject {
    @Published var equipmentList: [Equipment] = []
    @Published var sensitiveItemsChecked: Bool = false
    @Published var handReceipts: [HandReceipt] = []
    
    func addEquipment(serialNumber: String, custodian: String) {
        let newEquipment = Equipment(serialNumber: serialNumber, custodian: custodian)
        equipmentList.append(newEquipment)
    }
    
    func checkSensitiveItems() {
        sensitiveItemsChecked = true
    }
    
    func addHandReceipt(item: Equipment, date: Date) {
        let newReceipt = HandReceipt(item: item, date: date)
        handReceipts.append(newReceipt)
    }
}

// MARK: - Equipment

struct Equipment: Identifiable {
    let id = UUID()
    let serialNumber: String
    let custodian: String
}

// MARK: - HandReceipt

struct HandReceipt: Identifiable {
    let id = UUID()
    let item: Equipment
    let date: Date
}

// MARK: - EquipmentTrackerView

struct EquipmentTrackerView: View {
    @StateObject private var viewModel = EquipmentTracker()
    
    var body: some View {
        VStack {
            List(viewModel.equipmentList) { equipment in
                Text("Serial: \(equipment.serialNumber), Custodian: \(equipment.custodian)")
            }
            
            Button("Check Sensitive Items") {
                viewModel.checkSensitiveItems()
            }
            .disabled(viewModel.sensitiveItemsChecked)
            
            Button("Add Hand Receipt") {
                // Placeholder for adding hand receipt logic
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct EquipmentTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        EquipmentTrackerView()
    }
}