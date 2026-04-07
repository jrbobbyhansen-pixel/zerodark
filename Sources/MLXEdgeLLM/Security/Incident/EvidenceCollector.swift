import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - EvidenceCollector

class EvidenceCollector: ObservableObject {
    @Published var evidenceItems: [EvidenceItem] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var arSession: ARSession?
    
    private let locationManager = CLLocationManager()
    private let audioRecorder = AVAudioRecorder()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        setupAudioRecorder()
    }
    
    func collectEvidence() {
        guard let location = currentLocation else { return }
        let timestamp = Date()
        let audioURL = recordAudio()
        
        let evidenceItem = EvidenceItem(location: location, timestamp: timestamp, audioURL: audioURL)
        evidenceItems.append(evidenceItem)
    }
    
    private func setupAudioRecorder() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioURL = documentsDirectory.appendingPathComponent("evidence.m4a")
        
        audioRecorder = try! AVAudioRecorder(url: audioURL, settings: settings)
        audioRecorder.delegate = self
    }
    
    private func recordAudio() -> URL {
        audioRecorder.record(forDuration: 5.0)
        return audioRecorder.url
    }
}

// MARK: - CLLocationManagerDelegate

extension EvidenceCollector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }
}

// MARK: - AVAudioRecorderDelegate

extension EvidenceCollector: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            print("Audio recording successful")
        } else {
            print("Audio recording failed")
        }
    }
}

// MARK: - EvidenceItem

struct EvidenceItem: Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let timestamp: Date
    let audioURL: URL
}

// MARK: - EvidenceCollectorView

struct EvidenceCollectorView: View {
    @StateObject private var evidenceCollector = EvidenceCollector()
    
    var body: some View {
        VStack {
            Map(coordinateRegion: .constant(MKCoordinateRegion(center: evidenceCollector.currentLocation ?? CLLocationCoordinate2D(), latitudinalMeters: 1000, longitudinalMeters: 1000)))
                .edgesIgnoringSafeArea(.all)
            
            Button(action: {
                evidenceCollector.collectEvidence()
            }) {
                Text("Collect Evidence")
            }
            .padding()
            
            List(evidenceCollector.evidenceItems) { item in
                VStack(alignment: .leading) {
                    Text("Location: \(item.location.latitude), \(item.location.longitude)")
                    Text("Timestamp: \(item.timestamp, formatter: DateFormatter())")
                    Button(action: {
                        // Export evidence for analysis
                    }) {
                        Text("Export")
                    }
                }
            }
        }
        .navigationTitle("Evidence Collector")
    }
}

// MARK: - DateFormatter

extension DateFormatter {
    init() {
        self.init()
        self.dateStyle = .medium
        self.timeStyle = .medium
    }
}