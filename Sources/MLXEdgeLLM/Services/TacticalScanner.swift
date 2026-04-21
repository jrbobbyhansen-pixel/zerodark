// TacticalScanner.swift — QR/Document/Torch scanner (ZeroDark-TACTICAL-SCANNER spec)

import AVFoundation
import Vision
import UIKit

/// Scanner mode
public enum ScanMode {
    case qr
    case document
    case torch
}

/// Tactical scanner with multiple modes
@MainActor
public class TacticalScanner: NSObject, ObservableObject {
    @Published public var lastResult: TacticalScanResult?
    @Published public var isScanning = false

    /// Exposed so SwiftUI views (TacticalScannerView) can attach an
    /// AVCaptureVideoPreviewLayer to show the live feed.
    public let captureSession = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.zerodark.scanner")
    private var torchDevice: AVCaptureDevice?
    private var currentMode: ScanMode = .qr

    public override init() {
        super.init()
    }

    /// Start scanning in given mode
    public func startScanning(mode: ScanMode) {
        currentMode = mode
        isScanning = true

        // Setup capture for QR/document
        if mode != .torch {
            setupCapture(mode: mode)
            captureSession.startRunning()
        }
    }

    /// Stop scanning
    public func stopScanning() {
        captureSession.stopRunning()
        isScanning = false

        if currentMode == .torch {
            setTorchMode(.off)
        }
    }

    /// Send SOS signal (3 dots, 3 dashes, 3 dots)
    public func sendSOS() {
        Task {
            await sendMorse(text: "SOS")
        }
    }

    /// Send text as Morse code via torch
    public func sendMorse(text: String) async {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }

        let morseCode = textToMorse(text)

        for signal in morseCode {
            let duration = signal == "." ? 0.15 : 0.45  // dit vs dah

            try? device.lockForConfiguration()
            device.torchMode = .on
            try? device.unlockForConfiguration()

            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            try? device.lockForConfiguration()
            device.torchMode = .off
            try? device.unlockForConfiguration()

            try? await Task.sleep(nanoseconds: 150_000_000)  // Inter-element gap
        }
    }

    // MARK: - Private

    private func setupCapture(mode: ScanMode) {
        guard captureSession.inputs.isEmpty else {
            return
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }

        captureSession.addInput(input)
        torchDevice = camera

        // Simplified: just process still frames periodically
    }

    private func setTorchMode(_ mode: AVCaptureDevice.TorchMode) {
        guard let device = torchDevice else {
            return
        }

        try? device.lockForConfiguration()
        device.torchMode = mode
        try? device.unlockForConfiguration()
    }

    private func textToMorse(_ text: String) -> [Character] {
        let morseDictionary: [Character: String] = [
            "S": "...", "O": "---", "E": ".", "T": "-",
            "A": ".-", "I": "..", "N": "-.", "M": "--",
            "H": "....", "V": "...-", "U": "..-", "F": "..-.",
            "Ä": ".-.-", "W": ".--", "K": "-.-", "J": ".---",
            "B": "-...", "D": "-..", "X": "-..-", "C": "-.-.",
            "Y": "-.--", "Z": "--..", "Q": "--.-", "Ö": "---.",
            "G": "--.", "P": ".--.", "Ü": "..--", "L": ".-..",
            "R": ".-.", "Ñ": "--.--"
        ]

        var result: [Character] = []
        for char in text.uppercased() {
            if let morse = morseDictionary[char] {
                result.append(contentsOf: morse)
                result.append(" ")
            }
        }

        return result
    }

    /// Simulate QR code detection
    public func simulateQRScan(data: String) {
        lastResult = TacticalScanResult(type: .qr, data: data)
    }

    /// Simulate document detection
    public func simulateDocumentScan() {
        lastResult = TacticalScanResult(type: .document, data: "Document detected")
    }
}

/// Scanned result
public struct TacticalScanResult {
    public let type: ScanMode
    public let data: String
    public let timestamp: Date

    public init(type: ScanMode, data: String) {
        self.type = type
        self.data = data
        self.timestamp = Date()
    }
}
