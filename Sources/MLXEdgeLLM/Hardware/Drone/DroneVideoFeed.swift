import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - DroneVideoFeedView

struct DroneVideoFeedView: View {
    @StateObject private var viewModel = DroneVideoFeedViewModel()
    
    var body: some View {
        VStack {
            VideoPlayer(player: viewModel.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    viewModel.startFeed()
                }
                .onDisappear {
                    viewModel.stopFeed()
                }
            
            HStack {
                Button(action: viewModel.captureFrame) {
                    Image(systemName: "camera")
                        .font(.largeTitle)
                }
                .padding()
                
                Button(action: viewModel.toggleRecording) {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle.fill")
                        .font(.largeTitle)
                }
                .padding()
            }
        }
        .sheet(isPresented: $viewModel.isPictureInPicture) {
            VideoPlayer(player: viewModel.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    viewModel.enterPictureInPicture()
                }
                .onDisappear {
                    viewModel.exitPictureInPicture()
                }
        }
    }
}

// MARK: - DroneVideoFeedViewModel

class DroneVideoFeedViewModel: ObservableObject {
    @Published var player: AVPlayer = AVPlayer()
    @Published var isRecording = false
    @Published var isPictureInPicture = false
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var recordingOutput: AVCaptureMovieFileOutput?
    
    func startFeed() {
        guard captureSession == nil else { return }
        
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        
        captureSession?.addInput(videoInput)
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatKey as String: kCVPixelFormatType_32BGRA]
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        captureSession?.addOutput(videoOutput!)
        
        player = AVPlayer(playerItem: AVPlayerItem(asset: AVAsset(url: URL(fileURLWithPath: "/dev/null"))))
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        
        captureSession?.startRunning()
    }
    
    func stopFeed() {
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    func captureFrame() {
        // Implement frame capture logic
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let captureSession = captureSession else { return }
        
        recordingOutput = AVCaptureMovieFileOutput()
        recordingOutput?.startRecording(to: URL(fileURLWithPath: NSTemporaryDirectory() + "recording.mp4"), recordingDelegate: self)
        captureSession.addOutput(recordingOutput!)
        isRecording = true
    }
    
    private func stopRecording() {
        recordingOutput?.stopRecording()
        captureSession?.removeOutput(recordingOutput!)
        recordingOutput = nil
        isRecording = false
    }
    
    func enterPictureInPicture() {
        isPictureInPicture = true
    }
    
    func exitPictureInPicture() {
        isPictureInPicture = false
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension DroneVideoFeedViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process video frames
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension DroneVideoFeedViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // Handle recording completion
    }
}