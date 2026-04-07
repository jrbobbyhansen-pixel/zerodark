import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - HazardDetector

class HazardDetector: ObservableObject {
    @Published var hazards: [Hazard] = []
    @Published var safetyZone: [CLLocationCoordinate2D] = []
    
    private let arSession: ARSession
    private let locationManager: CLLocationManager
    
    init(arSession: ARSession, locationManager: CLLocationManager) {
        self.arSession = arSession
        self.locationManager = locationManager
        setupARSession()
        setupLocationManager()
    }
    
    private func setupARSession() {
        arSession.delegate = self
        arSession.run(ARWorldTrackingConfiguration(), options: [])
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    /// YOLO threat detector providing real-time hazard detections
    var yoloDetector: YOLOThreatDetector?

    func detectHazards() {
        // Pull hazard-relevant detections from YOLO pipeline if available
        guard let yolo = yoloDetector else { return }

        hazards = yolo.activeDetections
            .filter { detection in
                let level = detection.tacticalLevel()
                return level >= .medium
            }
            .compactMap { detection -> Hazard? in
                guard let pos3D = detection.position3D else { return nil }
                let hazardType: HazardType = detection.tacticalCategory == .weapon ? .unstableStructure : .dropOff
                return Hazard(
                    type: hazardType,
                    location: CLLocationCoordinate2D(
                        latitude: Double(pos3D.z),
                        longitude: Double(pos3D.x)
                    )
                )
            }
    }
    
    func markSafetyZone() {
        // Placeholder for safety zone marking logic
        // This should define a safe area based on detected hazards
        // For now, simulate a safety zone
        safetyZone = [
            CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196),
            CLLocationCoordinate2D(latitude: 37.7752, longitude: -122.4197),
            CLLocationCoordinate2D(latitude: 37.7753, longitude: -122.4198)
        ]
    }
    
    func generateAlert(for hazard: Hazard) {
        // Placeholder for alert generation logic
        // This should generate an alert based on the detected hazard
        print("Alert: Hazard detected - \(hazard.type) at \(hazard.location)")
    }
}

// MARK: - Hazard

struct Hazard: Identifiable {
    let id = UUID()
    let type: HazardType
    let location: CLLocationCoordinate2D
}

// MARK: - HazardType

enum HazardType {
    case hole
    case dropOff
    case unstableStructure
}

// MARK: - ARSessionDelegate

extension HazardDetector: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Process AR frame data for hazard detection
        detectHazards()
    }
}

// MARK: - CLLocationManagerDelegate

extension HazardDetector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Update safety zone based on current location
        markSafetyZone()
    }
}

// MARK: - HazardView

struct HazardView: View {
    @StateObject private var hazardDetector = HazardDetector(arSession: ARSession(), locationManager: CLLocationManager())
    
    var body: some View {
        VStack {
            Map(coordinateRegion: .constant(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), latitudinalMeters: 1000, longitudinalMeters: 1000)))
                .edgesIgnoringSafeArea(.all)
            
            List(hazardDetector.hazards) { hazard in
                Text("Hazard: \(hazard.type) at \(hazard.location)")
            }
        }
        .onAppear {
            hazardDetector.detectHazards()
        }
    }
}

// MARK: - Preview

struct HazardView_Previews: PreviewProvider {
    static var previews: some View {
        HazardView()
    }
}