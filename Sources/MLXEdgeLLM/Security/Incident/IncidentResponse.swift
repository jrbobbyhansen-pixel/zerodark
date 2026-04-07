import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Incident Response Models

struct IncidentReport {
    var incidentType: IncidentType
    var location: CLLocationCoordinate2D
    var timestamp: Date
    var evidence: [Evidence]
    var notes: String
}

enum IncidentType {
    case cyberAttack
    case physicalThreat
    case dataLeak
    case other(String)
}

struct Evidence {
    var type: EvidenceType
    var data: Data
    var description: String
}

enum EvidenceType {
    case photo
    case video
    case audio
    case logFile
    case other(String)
}

// MARK: - Incident Response ViewModel

class IncidentResponseViewModel: ObservableObject {
    @Published var incidentReport: IncidentReport
    @Published var isRecording: Bool = false
    @Published var isRecordingAudio: Bool = false
    @Published var recordedVideoURL: URL?
    @Published var recordedAudioURL: URL?
    
    private let locationManager = CLLocationManager()
    private let session = ARSession()
    private var audioRecorder: AVAudioRecorder?
    
    init() {
        incidentReport = IncidentReport(
            incidentType: .other("Unknown"),
            location: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            timestamp: Date(),
            evidence: [],
            notes: ""
        )
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func updateIncidentType(_ type: IncidentType) {
        incidentReport.incidentType = type
    }
    
    func updateNotes(_ notes: String) {
        incidentReport.notes = notes
    }
    
    func startRecordingVideo() {
        let configuration = ARWorldTrackingConfiguration()
        session.run(configuration)
        isRecording = true
    }
    
    func stopRecordingVideo() {
        session.pause()
        isRecording = false
    }
    
    func startRecordingAudio() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: getDocumentsDirectory().appendingPathComponent("recording.m4a"), settings: settings)
            audioRecorder?.record()
            isRecordingAudio = true
        } catch {
            print("Failed to record audio: \(error)")
        }
    }
    
    func stopRecordingAudio() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecordingAudio = false
    }
    
    func addEvidence(_ evidence: Evidence) {
        incidentReport.evidence.append(evidence)
    }
    
    func escalateIncident() {
        // Implement escalation logic here
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

// MARK: - Location Manager Delegate

extension IncidentResponseViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        incidentReport.location = location.coordinate
    }
}

// MARK: - Incident Response View

struct IncidentResponseView: View {
    @StateObject private var viewModel = IncidentResponseViewModel()
    
    var body: some View {
        VStack {
            Text("Incident Response")
                .font(.largeTitle)
                .padding()
            
            Form {
                Section(header: Text("Incident Details")) {
                    Picker("Incident Type", selection: $viewModel.incidentReport.incidentType) {
                        ForEach(IncidentType.allCases, id: \.self) { type in
                            Text(type.description)
                        }
                    }
                    
                    TextField("Notes", text: $viewModel.incidentReport.notes)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Section(header: Text("Location")) {
                    Text("Latitude: \(viewModel.incidentReport.location.latitude)")
                    Text("Longitude: \(viewModel.incidentReport.location.longitude)")
                }
                
                Section(header: Text("Evidence")) {
                    Button(action: {
                        // Add photo evidence
                    }) {
                        Text("Add Photo")
                    }
                    
                    Button(action: {
                        // Add video evidence
                    }) {
                        Text("Add Video")
                    }
                    
                    Button(action: {
                        // Add audio evidence
                    }) {
                        Text("Add Audio")
                    }
                    
                    Button(action: {
                        // Add log file evidence
                    }) {
                        Text("Add Log File")
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button(action: {
                        viewModel.startRecordingVideo()
                    }) {
                        Text("Start Recording Video")
                    }
                    
                    Button(action: {
                        viewModel.stopRecordingVideo()
                    }) {
                        Text("Stop Recording Video")
                    }
                    
                    Button(action: {
                        viewModel.startRecordingAudio()
                    }) {
                        Text("Start Recording Audio")
                    }
                    
                    Button(action: {
                        viewModel.stopRecordingAudio()
                    }) {
                        Text("Stop Recording Audio")
                    }
                    
                    Button(action: {
                        viewModel.escalateIncident()
                    }) {
                        Text("Escalate Incident")
                    }
                }
            }
        }
        .navigationTitle("Incident Response")
    }
}

// MARK: - Preview

struct IncidentResponseView_Previews: PreviewProvider {
    static var previews: some View {
        IncidentResponseView()
    }
}