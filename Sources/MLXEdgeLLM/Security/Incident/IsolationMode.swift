import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - IsolationMode

class IsolationMode: ObservableObject {
    @Published var isIsolated: Bool = false
    @Published var location: CLLocationCoordinate2D?
    @Published var arSession: ARSession?
    @Published var audioRecorder: AVAudioRecorder?
    
    private let locationManager = CLLocationManager()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        setupARSession()
        setupAudioRecorder()
    }
    
    func toggleIsolation() {
        isIsolated.toggle()
    }
    
    private func setupARSession() {
        arSession = ARSession()
        arSession?.run(ARWorldTrackingConfiguration())
    }
    
    private func setupAudioRecorder() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: getDocumentsDirectory().appendingPathComponent("recording.m4a"), settings: settings)
            audioRecorder?.prepareToRecord()
        } catch {
            print("Failed to set up audio recorder: \(error)")
        }
    }
    
    func startRecording() {
        audioRecorder?.record()
    }
    
    func stopRecording() {
        audioRecorder?.stop()
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

// MARK: - CLLocationManagerDelegate

extension IsolationMode: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location.coordinate
    }
}

// MARK: - IsolationModeView

struct IsolationModeView: View {
    @StateObject private var viewModel = IsolationMode()
    
    var body: some View {
        VStack {
            Toggle("Isolation Mode", isOn: $viewModel.isIsolated)
                .onChange(of: viewModel.isIsolated) { _ in
                    viewModel.toggleIsolation()
                }
            
            if let location = viewModel.location {
                Text("Location: \(location.latitude), \(location.longitude)")
            }
            
            Button("Start Recording") {
                viewModel.startRecording()
            }
            
            Button("Stop Recording") {
                viewModel.stopRecording()
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct IsolationModeView_Previews: PreviewProvider {
    static var previews: some View {
        IsolationModeView()
    }
}