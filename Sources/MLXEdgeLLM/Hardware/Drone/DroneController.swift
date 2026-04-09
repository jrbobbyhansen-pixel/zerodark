import Foundation
import SwiftUI
import CoreLocation

// MARK: - DroneController

class DroneController: ObservableObject {
    @Published var isDroneConnected: Bool = false
    @Published var droneStatus: String = "Disconnected"
    @Published var batteryLevel: Int = 0
    @Published var altitude: Double = 0.0
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var isFlying: Bool = false
    
    private var drone: DJIDrone?
    
    init() {
        // Initialize DJI SDK and connect to drone
        DJISDKManager.registerApp(with: "YOUR_APP_KEY") { [weak self] error in
            if let error = error {
                print("DJI SDK registration failed: \(error.localizedDescription)")
            } else {
                self?.connectToDrone()
            }
        }
    }
    
    private func connectToDrone() {
        // Connect to the drone
        DJISDKManager.product?.connect { [weak self] error in
            if let error = error {
                print("Drone connection failed: \(error.localizedDescription)")
            } else {
                self?.isDroneConnected = true
                self?.droneStatus = "Connected"
                self?.updateDroneStatus()
            }
        }
    }
    
    private func updateDroneStatus() {
        // Update drone status properties
        if let aircraft = DJISDKManager.product as? DJIAircraft {
            aircraft.battery?.getBatteryInfo { [weak self] batteryInfo, error in
                if let batteryInfo = batteryInfo {
                    self?.batteryLevel = Int(batteryInfo.batteryPercentage)
                }
            }
            
            aircraft.flightController?.getState { [weak self] flightControllerState, error in
                if let flightControllerState = flightControllerState {
                    self?.isFlying = flightControllerState.isFlying
                    self?.altitude = flightControllerState.altitude
                    self?.latitude = flightControllerState.location.coordinate.latitude
                    self?.longitude = flightControllerState.location.coordinate.longitude
                }
            }
        }
    }
    
    func takeoff() {
        guard let flightController = DJISDKManager.product?.flightController else { return }
        flightController.startTakeoff { [weak self] error in
            if let error = error {
                print("Takeoff failed: \(error.localizedDescription)")
            } else {
                self?.droneStatus = "Taking Off"
            }
        }
    }
    
    func land() {
        guard let flightController = DJISDKManager.product?.flightController else { return }
        flightController.startLanding { [weak self] error in
            if let error = error {
                print("Landing failed: \(error.localizedDescription)")
            } else {
                self?.droneStatus = "Landing"
            }
        }
    }
    
    func returnToHome() {
        guard let flightController = DJISDKManager.product?.flightController else { return }
        flightController.startGoHome { [weak self] error in
            if let error = error {
                print("Return to Home failed: \(error.localizedDescription)")
            } else {
                self?.droneStatus = "Returning to Home"
            }
        }
    }
    
    func startWaypointMission(waypoints: [CLLocationCoordinate2D]) {
        guard let flightController = DJISDKManager.product?.flightController else { return }
        
        let waypointMissionBuilder = DJIWaypointMissionBuilder()
        waypoints.enumerated().forEach { index, coordinate in
            let waypoint = DJIWaypoint(coordinate: coordinate)
            waypoint.altitude = 10.0
            waypointMissionBuilder.addWaypoint(waypoint)
        }
        
        let waypointMission = waypointMissionBuilder.build()
        flightController.startMission(waypointMission) { [weak self] error in
            if let error = error {
                print("Waypoint mission failed: \(error.localizedDescription)")
            } else {
                self?.droneStatus = "Executing Waypoint Mission"
            }
        }
    }
}

// MARK: - DroneStatusView

struct DroneStatusView: View {
    @StateObject private var droneController = DroneController()
    
    var body: some View {
        VStack {
            Text("Drone Status")
                .font(.largeTitle)
                .padding()
            
            HStack {
                Text("Status: \(droneController.droneStatus)")
                Spacer()
                Text("Battery: \(droneController.batteryLevel)%")
            }
            .padding()
            
            HStack {
                Text("Altitude: \(String(format: "%.1f", droneController.altitude)) m")
                Spacer()
                Text("Location: \(String(format: "%.6f", droneController.latitude)), \(String(format: "%.6f", droneController.longitude))")
            }
            .padding()
            
            HStack {
                Button(action: droneController.takeoff) {
                    Text("Takeoff")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(droneController.isFlying)
                
                Button(action: droneController.land) {
                    Text("Land")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(!droneController.isFlying)
            }
            .padding()
            
            Button(action: droneController.returnToHome) {
                Text("Return to Home")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .onAppear {
            droneController.connectToDrone()
        }
    }
}

// MARK: - Preview

struct DroneStatusView_Previews: PreviewProvider {
    static var previews: some View {
        DroneStatusView()
    }
}