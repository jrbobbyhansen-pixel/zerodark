import Foundation
import SwiftUI
import CoreLocation
import ARKit

// MARK: - SpotInterface

class SpotInterface: ObservableObject {
    @Published var isCheckingIn: Bool = false
    @Published var isHelpRequested: Bool = false
    @Published var isSOSActivated: Bool = false
    @Published var currentPosition: CLLocationCoordinate2D?
    @Published var messageStatus: String = "Idle"
    
    private let locationManager = CLLocationManager()
    private let arSession = ARSession()
    
    init() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        
        arSession.delegate = self
    }
    
    func checkIn() {
        isCheckingIn = true
        messageStatus = "Checking In..."
        // Simulate sending a check-in message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isCheckingIn = false
            self.messageStatus = "Checked In"
        }
    }
    
    func requestHelp() {
        isHelpRequested = true
        messageStatus = "Help Requested..."
        // Simulate sending a help request message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isHelpRequested = false
            self.messageStatus = "Help Sent"
        }
    }
    
    func activateSOS() {
        isSOSActivated = true
        messageStatus = "SOS Activated..."
        // Simulate sending an SOS message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isSOSActivated = false
            self.messageStatus = "SOS Sent"
        }
    }
    
    func startPositionTracking() {
        locationManager.startUpdatingLocation()
    }
    
    func stopPositionTracking() {
        locationManager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension SpotInterface: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentPosition = location.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        messageStatus = "Location Error: \(error.localizedDescription)"
    }
}

// MARK: - ARSessionDelegate

extension SpotInterface: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Handle AR frame updates if needed
    }
}

// MARK: - SpotInterfaceView

struct SpotInterfaceView: View {
    @StateObject private var spotInterface = SpotInterface()
    
    var body: some View {
        VStack {
            HStack {
                Button(action: spotInterface.checkIn) {
                    Text("Check In")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(spotInterface.isCheckingIn)
                
                Button(action: spotInterface.requestHelp) {
                    Text("Help")
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(spotInterface.isHelpRequested)
                
                Button(action: spotInterface.activateSOS) {
                    Text("SOS")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(spotInterface.isSOSActivated)
            }
            
            Text("Current Position: \(spotInterface.currentPosition?.description ?? "Not Available")")
                .padding()
            
            Text("Message Status: \(spotInterface.messageStatus)")
                .padding()
        }
        .onAppear {
            spotInterface.startPositionTracking()
        }
        .onDisappear {
            spotInterface.stopPositionTracking()
        }
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D: CustomStringConvertible {
    var description: String {
        "Latitude: \(latitude), Longitude: \(longitude)"
    }
}