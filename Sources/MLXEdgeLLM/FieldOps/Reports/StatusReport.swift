import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - StatusReport

struct StatusReport {
    var sections: [ReportSection]
    var generationDate: Date
    var location: CLLocationCoordinate2D?
    var arSessionStatus: ARSession.Status?
    var audioRecordingURL: URL?
}

// MARK: - ReportSection

struct ReportSection {
    var title: String
    var content: String
}

// MARK: - StatusReportGenerator

class StatusReportGenerator: ObservableObject {
    @Published var report: StatusReport?
    @Published var isGenerating = false
    
    private let locationManager = CLLocationManager()
    private let arSession = ARSession()
    private var audioRecorder: AVAudioRecorder?
    
    init() {
        locationManager.delegate = self
        arSession.delegate = self
    }
    
    func generateReport() async {
        isGenerating = true
        defer { isGenerating = false }
        
        let location = await fetchLocation()
        let arStatus = await fetchARSessionStatus()
        let audioURL = await recordAudio()
        
        let sections = [
            ReportSection(title: "Location", content: locationDescription(location)),
            ReportSection(title: "AR Session Status", content: arStatusDescription(arStatus)),
            ReportSection(title: "Audio Recording", content: audioURL?.absoluteString ?? "No recording")
        ]
        
        report = StatusReport(sections: sections, generationDate: Date(), location: location, arSessionStatus: arStatus, audioRecordingURL: audioURL)
    }
    
    private func fetchLocation() async -> CLLocationCoordinate2D? {
        return await withCheckedContinuation { continuation in
            locationManager.requestLocation()
            continuation.resume(returning: nil)
        }
    }
    
    private func fetchARSessionStatus() async -> ARSession.Status {
        return await withCheckedContinuation { continuation in
            arSession.run()
            continuation.resume(returning: arSession.status)
        }
    }
    
    private func recordAudio() async -> URL? {
        return await withCheckedContinuation { continuation in
            let audioURL = getDocumentsDirectory().appendingPathComponent("recording.m4a")
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            do {
                audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
                audioRecorder?.record(forDuration: 5.0)
                audioRecorder?.stop()
                continuation.resume(returning: audioURL)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func locationDescription(_ location: CLLocationCoordinate2D?) -> String {
        guard let location = location else { return "Unknown location" }
        return "Latitude: \(location.latitude), Longitude: \(location.longitude)"
    }
    
    private func arStatusDescription(_ status: ARSession.Status) -> String {
        return "Status: \(status.rawValue)"
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

// MARK: - CLLocationManagerDelegate

extension StatusReportGenerator: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            report?.location = location.coordinate
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - ARSessionDelegate

extension StatusReportGenerator: ARSessionDelegate {
    func session(_ session: ARSession, didChange status: ARSession.Status) {
        report?.arSessionStatus = status
    }
}