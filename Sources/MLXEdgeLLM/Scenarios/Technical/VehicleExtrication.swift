import Foundation
import SwiftUI

// MARK: - VehicleExtricationViewModel

class VehicleExtricationViewModel: ObservableObject {
    @Published var vehicleStabilized = false
    @Published var glassManaged = false
    @Published var doorsRemoved = false
    @Published var dashRolled = false
    @Published var patientProtected = false
    @Published var isElectricVehicle = false
    
    func stabilizeVehicle() {
        vehicleStabilized = true
    }
    
    func manageGlass() {
        glassManaged = true
    }
    
    func removeDoors() {
        doorsRemoved = true
    }
    
    func rollDash() {
        dashRolled = true
    }
    
    func protectPatient() {
        patientProtected = true
    }
    
    func checkElectricVehicle() {
        isElectricVehicle = true
    }
}

// MARK: - VehicleExtricationView

struct VehicleExtricationView: View {
    @StateObject private var viewModel = VehicleExtricationViewModel()
    
    var body: some View {
        VStack {
            Text("Vehicle Extrication Guide")
                .font(.largeTitle)
                .padding()
            
            VStack(alignment: .leading) {
                Toggle("Stabilize Vehicle", isOn: $viewModel.vehicleStabilized)
                Toggle("Manage Glass", isOn: $viewModel.glassManaged)
                Toggle("Remove Doors", isOn: $viewModel.doorsRemoved)
                Toggle("Roll Dash", isOn: $viewModel.dashRolled)
                Toggle("Protect Patient", isOn: $viewModel.patientProtected)
                Toggle("Is Electric Vehicle", isOn: $viewModel.isElectricVehicle)
            }
            .padding()
            
            Button(action: {
                viewModel.stabilizeVehicle()
                viewModel.manageGlass()
                viewModel.removeDoors()
                viewModel.rollDash()
                viewModel.protectPatient()
                viewModel.checkElectricVehicle()
            }) {
                Text("Complete Extrication")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("Vehicle Extrication")
    }
}

// MARK: - VehicleExtricationPreview

struct VehicleExtricationPreview: PreviewProvider {
    static var previews: some View {
        VehicleExtricationView()
    }
}