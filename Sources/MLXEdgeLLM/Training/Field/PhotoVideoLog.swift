import Foundation
import SwiftUI
import CoreLocation
import AVFoundation

// MARK: - Models

struct MediaItem: Identifiable {
    let id = UUID()
    let url: URL
    let timestamp: Date
    let location: CLLocationCoordinate2D
    let tags: [String]
}

// MARK: - View Models

class PhotoVideoLoggerViewModel: ObservableObject {
    @Published var mediaItems: [MediaItem] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var isRecordingVideo = false
    @Published var videoURL: URL?
    
    private let locationManager = CLLocationManager()
    private let videoCapture = VideoCapture()
    
    init() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func capturePhoto() {
        guard let image = videoCapture.takePhoto() else { return }
        let url = saveImage(image)
        let mediaItem = MediaItem(url: url, timestamp: Date(), location: currentLocation ?? CLLocationCoordinate2D(), tags: [])
        mediaItems.append(mediaItem)
    }
    
    func startRecordingVideo() {
        videoCapture.startRecording { [weak self] url in
            self?.videoURL = url
            self?.isRecordingVideo = false
        }
        isRecordingVideo = true
    }
    
    func stopRecordingVideo() {
        videoCapture.stopRecording()
    }
    
    private func saveImage(_ image: UIImage) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "\(Date().timeIntervalSince1970).jpg"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
        return fileURL
    }
}

extension PhotoVideoLoggerViewModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }
}

// MARK: - Video Capture

class VideoCapture: ObservableObject {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureMovieFileOutput()
    private var fileURL: URL?
    
    init() {
        setupCaptureSession()
    }
    
    func startRecording(completion: @escaping (URL) -> Void) {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("video.mov")
        videoOutput.startRecording(to: fileURL!, recordingDelegate: self)
    }
    
    func stopRecording() {
        videoOutput.stopRecording()
    }
    
    func takePhoto() -> UIImage? {
        guard let videoConnection = videoOutput.connection(with: .video) else { return nil }
        let imageBuffer = videoOutput.sampleBuffer(for: videoConnection)!
        let image = CMSampleBufferGetImageBuffer(imageBuffer)!
        return UIImage(ciImage: CIImage(cvImageBuffer: image))
    }
    
    private func setupCaptureSession() {
        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(input)
            captureSession.addOutput(videoOutput)
            captureSession.startRunning()
        } catch {
            print("Error setting up capture session: \(error)")
        }
    }
}

extension VideoCapture: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording failed with error: \(error)")
        } else {
            fileURL = outputFileURL
        }
    }
}

// MARK: - Views

struct PhotoVideoLoggerView: View {
    @StateObject private var viewModel = PhotoVideoLoggerViewModel()
    
    var body: some View {
        VStack {
            Map(coordinateRegion: .constant(MKCoordinateRegion(center: viewModel.currentLocation ?? CLLocationCoordinate2D(), latitudinalMeters: 1000, longitudinalMeters: 1000)))
                .edgesIgnoringSafeArea(.all)
            
            HStack {
                Button(action: viewModel.capturePhoto) {
                    Image(systemName: "camera")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                
                Button(action: {
                    if viewModel.isRecordingVideo {
                        viewModel.stopRecordingVideo()
                    } else {
                        viewModel.startRecordingVideo()
                    }
                }) {
                    Image(systemName: viewModel.isRecordingVideo ? "stop.circle.fill" : "video.circle")
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
        }
        .onAppear {
            viewModel.startRecordingVideo()
        }
        .onDisappear {
            viewModel.stopRecordingVideo()
        }
    }
}

struct PhotoVideoLoggerView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoVideoLoggerView()
    }
}