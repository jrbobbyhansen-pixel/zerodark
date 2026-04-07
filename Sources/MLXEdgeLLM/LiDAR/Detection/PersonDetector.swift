// PersonDetector.swift — YOLO-based person detection and 3D tracking
// Filters YOLO class 0 (person) detections, tracks identities across frames
// via nearest-neighbor matching in 3D space

import Foundation
import simd

// MARK: - Detected Person

struct DetectedPerson: Identifiable {
    let id: String
    var position: SIMD3<Float>
    var confidence: Float
    var lastSeen: TimeInterval
    var path: [SIMD3<Float>]
}

// MARK: - PersonDetector

class PersonDetector: ObservableObject {
    @Published private(set) var peopleCount: Int = 0
    @Published private(set) var trackedPeople: [DetectedPerson] = []

    /// Maximum distance (meters) to match a detection to an existing track
    var matchThreshold: Float = 1.5

    /// Time (seconds) before an unseen track is dropped
    var trackTimeout: TimeInterval = 3.0

    /// Maximum path history per person
    var maxPathLength: Int = 100

    private var nextTrackId: Int = 0

    // MARK: - Update from YOLO Detections

    /// Process YOLO detections and update person tracks.
    /// Call this each frame (or after each YOLO inference cycle).
    func update(detections: [YOLODetection], timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        // Filter for person class (COCO class 0)
        let personDetections = detections.filter { $0.classId == 0 && $0.position3D != nil }

        // Match detections to existing tracks using nearest-neighbor in 3D
        var matched = Set<Int>() // indices into trackedPeople that got matched
        var unmatched: [(SIMD3<Float>, Float)] = [] // (position, confidence) of unmatched detections

        for detection in personDetections {
            guard let pos = detection.position3D else { continue }

            var bestIdx: Int?
            var bestDist: Float = matchThreshold

            for (i, person) in trackedPeople.enumerated() {
                if matched.contains(i) { continue }
                let dist = simd_distance(pos, person.position)
                if dist < bestDist {
                    bestDist = dist
                    bestIdx = i
                }
            }

            if let idx = bestIdx {
                // Update existing track
                matched.insert(idx)
                trackedPeople[idx].position = pos
                trackedPeople[idx].confidence = detection.confidence
                trackedPeople[idx].lastSeen = timestamp
                trackedPeople[idx].path.append(pos)
                if trackedPeople[idx].path.count > maxPathLength {
                    trackedPeople[idx].path.removeFirst()
                }
            } else {
                unmatched.append((pos, detection.confidence))
            }
        }

        // Create new tracks for unmatched detections
        for (pos, conf) in unmatched {
            let person = DetectedPerson(
                id: "person_\(nextTrackId)",
                position: pos,
                confidence: conf,
                lastSeen: timestamp,
                path: [pos]
            )
            trackedPeople.append(person)
            nextTrackId += 1
        }

        // Remove stale tracks
        trackedPeople.removeAll { timestamp - $0.lastSeen > trackTimeout }

        peopleCount = trackedPeople.count
    }

    /// Get all person positions as 3D points (for tactical analysis).
    var personPositions: [SIMD3<Float>] {
        trackedPeople.map(\.position)
    }

    /// Reset all tracks.
    func reset() {
        trackedPeople.removeAll()
        peopleCount = 0
        nextTrackId = 0
    }
}
