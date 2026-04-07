import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - ContextSnapshot

struct ContextSnapshot: Codable {
    var location: CLLocationCoordinate2D
    var mapViewState: MKMapView.State
    var arSessionState: ARSession.State
    var audioRecordingState: AVAudioRecorder.State
    
    init(location: CLLocationCoordinate2D, mapViewState: MKMapView.State, arSessionState: ARSession.State, audioRecordingState: AVAudioRecorder.State) {
        self.location = location
        self.mapViewState = mapViewState
        self.arSessionState = arSessionState
        self.audioRecordingState = audioRecordingState
    }
    
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    static func load(from url: URL) throws -> ContextSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ContextSnapshot.self, from: data)
    }
}

// MARK: - ContextManager

class ContextManager: ObservableObject {
    @Published var currentSnapshot: ContextSnapshot
    
    init(location: CLLocationCoordinate2D, mapViewState: MKMapView.State, arSessionState: ARSession.State, audioRecordingState: AVAudioRecorder.State) {
        self.currentSnapshot = ContextSnapshot(location: location, mapViewState: mapViewState, arSessionState: arSessionState, audioRecordingState: audioRecordingState)
    }
    
    func saveCurrentContext(to url: URL) throws {
        try currentSnapshot.save(to: url)
    }
    
    func restoreContext(from url: URL) throws {
        let snapshot = try ContextSnapshot.load(from: url)
        currentSnapshot = snapshot
    }
    
    func branchConversation() -> ContextManager {
        return ContextManager(location: currentSnapshot.location, mapViewState: currentSnapshot.mapViewState, arSessionState: currentSnapshot.arSessionState, audioRecordingState: currentSnapshot.audioRecordingState)
    }
    
    func compareContexts(_ other: ContextManager) -> Bool {
        return currentSnapshot == other.currentSnapshot
    }
    
    func rollbackToPreviousState(_ previousSnapshot: ContextSnapshot) {
        currentSnapshot = previousSnapshot
    }
}

// MARK: - Extensions

extension CLLocationCoordinate2D: Codable {
    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

extension MKMapView.State: Codable {
    // Implement Codable for MKMapView.State if necessary
}

extension ARSession.State: Codable {
    // Implement Codable for ARSession.State if necessary
}

extension AVAudioRecorder.State: Codable {
    // Implement Codable for AVAudioRecorder.State if necessary
}