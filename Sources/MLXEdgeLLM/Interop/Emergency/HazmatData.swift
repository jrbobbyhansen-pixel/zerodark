import Foundation
import SwiftUI

// MARK: - HazmatData

class HazmatData: ObservableObject {
    @Published var hazmatItems: [HazmatItem] = []
    
    init() {
        loadHazmatData()
    }
    
    private func loadHazmatData() {
        // Placeholder for actual data loading logic
        hazmatItems = [
            HazmatItem(id: 1, name: "Sodium Chloride", ergCode: "001", nioshGuide: "12345", properties: "Inorganic salt", safetyDataSheet: "SDS-001"),
            HazmatItem(id: 2, name: "Acetylene", ergCode: "002", nioshGuide: "67890", properties: "Flammable gas", safetyDataSheet: "SDS-002")
        ]
    }
}

// MARK: - HazmatItem

struct HazmatItem: Identifiable {
    let id: Int
    let name: String
    let ergCode: String
    let nioshGuide: String
    let properties: String
    let safetyDataSheet: String
}

// MARK: - HazmatView

struct HazmatView: View {
    @StateObject private var viewModel = HazmatData()
    
    var body: some View {
        NavigationView {
            List(viewModel.hazmatItems) { item in
                NavigationLink(destination: HazmatDetailView(item: item)) {
                    Text(item.name)
                }
            }
            .navigationTitle("Hazmat Reference")
        }
    }
}

// MARK: - HazmatDetailView

struct HazmatDetailView: View {
    let item: HazmatItem
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Name: \(item.name)")
            Text("ERG Code: \(item.ergCode)")
            Text("NIOSH Guide: \(item.nioshGuide)")
            Text("Properties: \(item.properties)")
            Text("Safety Data Sheet: \(item.safetyDataSheet)")
        }
        .padding()
        .navigationTitle(item.name)
    }
}

// MARK: - Preview

struct HazmatView_Previews: PreviewProvider {
    static var previews: some View {
        HazmatView()
    }
}