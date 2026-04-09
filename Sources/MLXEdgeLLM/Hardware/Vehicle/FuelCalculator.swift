import Foundation
import SwiftUI
import CoreLocation

// MARK: - FuelCalculator

class FuelCalculator: ObservableObject {
    @Published var fuelLevel: Double = 100.0
    @Published var fuelEfficiency: Double = 10.0 // km/l
    @Published var terrainFactor: Double = 1.0
    @Published var loadFactor: Double = 1.0
    @Published var reserveFuel: Double = 10.0
    @Published var refuelPoints: [CLLocationCoordinate2D] = []
    
    func calculateRange() -> Double {
        let effectiveEfficiency = fuelEfficiency * terrainFactor * loadFactor
        return fuelLevel * effectiveEfficiency
    }
    
    func calculateConsumption(distance: Double) -> Double {
        let effectiveEfficiency = fuelEfficiency * terrainFactor * loadFactor
        return distance / effectiveEfficiency
    }
    
    func addRefuelPoint(location: CLLocationCoordinate2D) {
        refuelPoints.append(location)
    }
    
    func removeRefuelPoint(at index: Int) {
        refuelPoints.remove(at: index)
    }
    
    func checkReserveWarning() -> Bool {
        return fuelLevel <= reserveFuel
    }
}

// MARK: - FuelCalculatorView

struct FuelCalculatorView: View {
    @StateObject private var viewModel = FuelCalculator()
    
    var body: some View {
        VStack {
            Text("Fuel Level: \(viewModel.fuelLevel, specifier: "%.1f")%")
                .font(.headline)
            
            Text("Range: \(viewModel.calculateRange(), specifier: "%.1f") km")
                .font(.subheadline)
            
            HStack {
                Text("Terrain Factor: \(viewModel.terrainFactor, specifier: "%.1f")")
                Slider(value: $viewModel.terrainFactor, in: 0.5...2.0)
            }
            
            HStack {
                Text("Load Factor: \(viewModel.loadFactor, specifier: "%.1f")")
                Slider(value: $viewModel.loadFactor, in: 0.5...2.0)
            }
            
            Button(action: {
                viewModel.addRefuelPoint(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            }) {
                Text("Add Refuel Point")
            }
            
            List(viewModel.refuelPoints, id: \.self) { location in
                Text("Lat: \(location.latitude), Lon: \(location.longitude)")
            }
            
            if viewModel.checkReserveWarning() {
                Text("Reserve Fuel Warning!")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct FuelCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        FuelCalculatorView()
    }
}