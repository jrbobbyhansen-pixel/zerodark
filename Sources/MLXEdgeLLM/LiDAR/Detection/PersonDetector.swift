import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - PersonDetector

class PersonDetector: ObservableObject {
    @Published var peopleCount: Int = 0
    @Published var peoplePositions: [CLLocationCoordinate2D] = []
    @Published var movementPaths: [String: [CLLocationCoordinate2D]] = [:]
    
    private var session: ARSession
    private var lastScanTimestamp: Date?
    
    init(session: ARSession) {
        self.session = session
    }
    
    func processPointCloud(_ pointCloud: ARPointCloud) {
        let currentTime = Date()
        let timeSinceLastScan = lastScanTimestamp?.timeIntervalSince(currentTime) ?? 0
        
        // Perform person detection
        let detectedPeople = detectPeople(in: pointCloud)
        
        // Update people count and positions
        peopleCount = detectedPeople.count
        peoplePositions = detectedPeople.map { $0.position }
        
        // Track movement if enough time has passed
        if timeSinceLastScan > 1.0 {
            trackMovement(for: detectedPeople)
            lastScanTimestamp = currentTime
        }
    }
    
    /// YOLO threat detector providing real-time person detections
    var yoloDetector: YOLOThreatDetector?

    private func detectPeople(in pointCloud: ARPointCloud) -> [DetectedPerson] {
        // Pull person-class detections from YOLO pipeline if available
        guard let yolo = yoloDetector else { return [] }

        return yolo.activeDetections
            .filter { $0.classId == 0 } // COCO class 0 = person
            .compactMap { detection -> DetectedPerson? in
                guard let pos3D = detection.position3D else { return nil }
                return DetectedPerson(
                    identifier: "yolo_person_\(Int(pos3D.x * 100))_\(Int(pos3D.z * 100))",
                    position: CLLocationCoordinate2D(
                        latitude: Double(pos3D.z),  // Approximate mapping
                        longitude: Double(pos3D.x)
                    )
                )
            }
    }
    
    private func trackMovement(for people: [DetectedPerson]) {
        for person in people {
            let identifier = person.identifier
            if let lastPosition = movementPaths[identifier]?.last {
                let currentPosition = person.position
                if currentPosition != lastPosition {
                    movementPaths[identifier, default: []].append(currentPosition)
                }
            } else {
                movementPaths[identifier, default: []].append(person.position)
            }
        }
    }
}

// MARK: - DetectedPerson

struct DetectedPerson {
    let identifier: String
    let position: CLLocationCoordinate2D
}

// MARK: - PrivacyMasking

extension PersonDetector {
    func applyPrivacyMask(to view: some View) -> some View {
        view
            .overlay(
                GeometryReader { geometry in
                    ForEach(peoplePositions, id: \.self) { position in
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 50, height: 50)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            .offset(x: position.longitude, y: position.latitude)
                    }
                }
            )
    }
}