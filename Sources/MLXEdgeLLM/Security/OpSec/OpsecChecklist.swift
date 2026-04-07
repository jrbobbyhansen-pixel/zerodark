import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - OpsecChecklist

class OpsecChecklist: ObservableObject {
    @Published var missionSpecific: Bool = false
    @Published var preDeparture: Bool = false
    @Published var communication: Bool = false
    @Published var complianceTracking: Bool = false
    
    func resetChecklist() {
        missionSpecific = false
        preDeparture = false
        communication = false
        complianceTracking = false
    }
}

// MARK: - OpsecChecklistView

struct OpsecChecklistView: View {
    @StateObject private var viewModel = OpsecChecklist()
    
    var body: some View {
        VStack {
            Toggle("Mission Specific", isOn: $viewModel.missionSpecific)
            Toggle("Pre-Departure", isOn: $viewModel.preDeparture)
            Toggle("Communication", isOn: $viewModel.communication)
            Toggle("Compliance Tracking", isOn: $viewModel.complianceTracking)
            
            Button("Reset Checklist") {
                viewModel.resetChecklist()
            }
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .navigationTitle("OPSEC Checklist")
    }
}

// MARK: - Preview

struct OpsecChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        OpsecChecklistView()
    }
}