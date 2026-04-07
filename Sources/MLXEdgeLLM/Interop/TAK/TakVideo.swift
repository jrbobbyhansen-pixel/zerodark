import Foundation
import SwiftUI
import AVFoundation
import CoreLocation
import ARKit

// MARK: - TakVideoPublisher

class TakVideoPublisher: ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var thumbnail: UIImage? = nil
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var thumbnailGenerator: AVAssetImageGenerator?
    
    func startStreaming() {
        guard !isStreaming else { return }
        
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .medium
        
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        
        captureSession?.addInput(videoInput)
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        captureSession?.addOutput(videoOutput!)
        
        captureSession?.startRunning()
        isStreaming = true
    }
    
    func stopStreaming() {
        guard isStreaming else { return }
        
        captureSession?.stopRunning()
        captureSession = nil
        isStreaming = false
    }
    
    func generateThumbnail() {
        guard let captureSession = captureSession else { return }
        
        let asset = AVAsset(url: captureSession.outputURL!)
        thumbnailGenerator = AVAssetImageGenerator(asset: asset)
        thumbnailGenerator?.requestedTimeToleranceAfter = .zero
        thumbnailGenerator?.requestedTimeToleranceBefore = .zero
        
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        thumbnailGenerator?.generateCGImage(at: time, actualTime: nil) { [weak self] image, error in
            if let image = image {
                DispatchQueue.main.async {
                    self?.thumbnail = UIImage(cgImage: image)
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension TakVideoPublisher: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle video frame data here
        // For example, send the sampleBuffer to the TAK server
    }
}

// MARK: - TakVideoView

struct TakVideoView: View {
    @StateObject private var viewModel = TakVideoPublisher()
    
    var body: some View {
        VStack {
            if let thumbnail = viewModel.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            
            Button(action: {
                if viewModel.isStreaming {
                    viewModel.stopStreaming()
                } else {
                    viewModel.startStreaming()
                }
            }) {
                Text(viewModel.isStreaming ? "Stop Streaming" : "Start Streaming")
            }
            
            Button(action: {
                viewModel.generateThumbnail()
            }) {
                Text("Generate Thumbnail")
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct TakVideoView_Previews: PreviewProvider {
    static var previews: some View {
        TakVideoView()
    }
}