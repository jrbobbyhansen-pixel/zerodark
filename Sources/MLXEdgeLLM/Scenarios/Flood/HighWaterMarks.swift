import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - HighWaterMarkLogger

class HighWaterMarkLogger: ObservableObject {
    @Published var highWaterMarks: [HighWaterMark] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var currentTimestamp: Date = Date()
    
    private let locationManager = CLLocationManager()
    private let arSession = ARSession()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        arSession.delegate = self
        arSession.run()
    }
    
    func logHighWaterMark(photo: UIImage) {
        guard let location = currentLocation else { return }
        let highWaterMark = HighWaterMark(location: location, timestamp: currentTimestamp, photo: photo)
        highWaterMarks.append(highWaterMark)
    }
    
    func exportHighWaterMarks() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(highWaterMarks)
            return data
        } catch {
            print("Failed to encode high water marks: \(error)")
            return nil
        }
    }
}

// MARK: - HighWaterMark

struct HighWaterMark: Codable, Identifiable {
    let id = UUID()
    let location: CLLocationCoordinate2D
    let timestamp: Date
    let photo: UIImage
    
    enum CodingKeys: String, CodingKey {
        case id
        case locationLatitude
        case locationLongitude
        case timestamp
        case photoData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        locationLatitude = try container.decode(Double.self, forKey: .locationLatitude)
        locationLongitude = try container.decode(Double.self, forKey: .locationLongitude)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        photoData = try container.decode(Data.self, forKey: .photoData)
        photo = UIImage(data: photoData) ?? UIImage()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(location.latitude, forKey: .locationLatitude)
        try container.encode(location.longitude, forKey: .locationLongitude)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(photo.pngData() ?? Data(), forKey: .photoData)
    }
}

// MARK: - CLLocationManagerDelegate

extension HighWaterMarkLogger: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location.coordinate
    }
}

// MARK: - ARSessionDelegate

extension HighWaterMarkLogger: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        currentTimestamp = frame.timestamp
    }
}

// MARK: - HighWaterMarkView

struct HighWaterMarkView: View {
    @StateObject private var logger = HighWaterMarkLogger()
    @State private var image: UIImage?
    
    var body: some View {
        VStack {
            Map(coordinateRegion: .constant(MKCoordinateRegion(center: logger.currentLocation ?? CLLocationCoordinate2D(), latitudinalMeters: 1000, longitudinalMeters: 1000)))
                .edgesIgnoringSafeArea(.all)
            
            Button(action: takePhoto) {
                Text("Log High Water Mark")
            }
            .padding()
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
            }
        }
        .onAppear {
            logger.exportHighWaterMarks()
        }
    }
    
    private func takePhoto() {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        guard let backCamera = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            captureSession.addInput(input)
        } catch {
            print("Error setting device input: \(error)")
            return
        }
        
        let photoOutput = AVCapturePhotoOutput()
        captureSession.addOutput(photoOutput)
        
        captureSession.startRunning()
        
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension HighWaterMarkView: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else { return }
        self.image = image
        logger.logHighWaterMark(photo: image)
    }
}