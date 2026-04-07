import Foundation
import SwiftUI
import CoreLocation
import AVFoundation
import ARKit

// MARK: - VoiceMemo

struct VoiceMemo: Identifiable, Codable {
    let id = UUID()
    let audioData: Data
    let timestamp: Date
    let location: CLLocationCoordinate2D
    let compressedData: Data?
    
    init(audioData: Data, timestamp: Date, location: CLLocationCoordinate2D) {
        self.audioData = audioData
        self.timestamp = timestamp
        self.location = location
        self.compressedData = nil
    }
    
    func compress() -> VoiceMemo {
        guard let compressed = audioData.compress() else { return self }
        return VoiceMemo(audioData: audioData, timestamp: timestamp, location: location, compressedData: compressed)
    }
}

// MARK: - VoiceMemoRecorder

class VoiceMemoRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var voiceMemo: VoiceMemo?
    private var audioRecorder: AVAudioRecorder?
    private var locationManager: CLLocationManager?
    
    init() {
        setupLocationManager()
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        guard let audioURL = getDocumentsDirectory().appendingPathComponent("recording.m4a") else { return }
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("Failed to record audio: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        isRecording = false
        
        if let audioURL = audioRecorder?.url {
            do {
                let audioData = try Data(contentsOf: audioURL)
                let timestamp = Date()
                let location = locationManager?.location?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                let voiceMemo = VoiceMemo(audioData: audioData, timestamp: timestamp, location: location)
                self.voiceMemo = voiceMemo
            } catch {
                print("Failed to read recorded audio data: \(error)")
            }
        }
    }
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
    }
}

// MARK: - CLLocationManagerDelegate

extension VoiceMemoRecorder: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location update handling if needed
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error)")
    }
}

// MARK: - Data Compression

extension Data {
    func compress() -> Data? {
        var compressedData: Data?
        let compressionStream = compression_stream()
        compression_stream_init(&compressionStream, COMPRESSION_STREAM_ENCODE, COMPRESSION_LZFSE, nil, nil, 0)
        
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var sourceBuffer = self.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        var sourceBytesRemaining = self.count
        
        while sourceBytesRemaining > 0 {
            let sourceLength = min(sourceBytesRemaining, bufferSize)
            compression_stream_process(&compressionStream, sourceBuffer, sourceLength, &buffer, bufferSize, COMPRESSION_STREAM_FINAL)
            compressedData?.append(contentsOf: buffer.prefix(compressionStream.dst_size))
            sourceBuffer = sourceBuffer.advanced(by: sourceLength)
            sourceBytesRemaining -= sourceLength
        }
        
        compression_stream_end(&compressionStream)
        compression_stream_destroy(&compressionStream)
        
        return compressedData
    }
}

// MARK: - Helper Functions

func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}