import Foundation
import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - ThermalCamera

class ThermalCamera: ObservableObject {
    @Published var isLiveViewActive = false
    @Published var capturedImage: UIImage? = nil
    @Published var temperaturePalette: TemperaturePalette = .ironbow
    @Published var temperatureSpan: TemperatureSpan = .default
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // MARK: - Initialization
    
    init() {
        setupCaptureSession()
    }
    
    // MARK: - Setup
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(for: .thermal) else { return }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession?.addInput(input)
        } catch {
            print("Error setting up thermal camera input: \(error)")
            return
        }
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_16BGRA]
        videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession?.addOutput(videoOutput!)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
    }
    
    // MARK: - Live View
    
    func startLiveView(in view: UIView) {
        guard let previewLayer = previewLayer else { return }
        view.layer.addSublayer(previewLayer)
        previewLayer.frame = view.bounds
        captureSession?.startRunning()
        isLiveViewActive = true
    }
    
    func stopLiveView() {
        captureSession?.stopRunning()
        isLiveViewActive = false
    }
    
    // MARK: - Capture
    
    func captureImage() {
        guard let videoOutput = videoOutput else { return }
        videoOutput.connection(with: .video)?.isVideoMirrored = true
        videoOutput.connection(with: .video)?.isVideoOrientationSupported = true
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.connection(with: .video)?.videoSettings = settings
        
        videoOutput.requestMediaDataOutputSampleBuffer(fromConnection: videoOutput.connection(with: .video)!, atOutputTime: CMTime.zero, withSampleBufferDelegate: self, queue: DispatchQueue.main)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ThermalCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvImageBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        capturedImage = UIImage(cgImage: cgImage)
    }
}

// MARK: - TemperaturePalette

enum TemperaturePalette: String, CaseIterable {
    case ironbow
    case grayscale
    case rainbow
    case jet
}

// MARK: - TemperatureSpan

enum TemperatureSpan: String, CaseIterable {
    case `default`
    case narrow
    case wide
}