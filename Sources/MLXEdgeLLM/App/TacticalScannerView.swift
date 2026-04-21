// TacticalScannerView.swift — QR/Document/Torch scanner UI (ZeroDark-TACTICAL-SCANNER spec)

import SwiftUI
import AVFoundation

/// Camera preview wrapper
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Tactical scanner UI
struct TacticalScannerView: View {
    @StateObject private var scanner = TacticalScanner()
    @State private var selectedMode: ScanMode = .qr
    @State private var showResult = false
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        ZStack {
            // Camera preview
            if selectedMode != .torch {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(ZDDesign.pureWhite)
                    }

                    Spacer()

                    Text("Tactical Scanner")
                        .font(.headline)
                        .foregroundColor(ZDDesign.pureWhite)

                    Spacer()

                    Image(systemName: "qrcode.viewfinder")
                        .foregroundColor(ZDDesign.cyanAccent)
                }
                .padding()
                .background(ZDDesign.darkCard)

                Spacer()

                if selectedMode != .torch {
                    // Live camera preview tied to the scanner's capture session.
                    // Reticle overlay tells the operator where to point the device.
                    ZStack {
                        CameraPreviewView(session: scanner.captureSession)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Reticle + hint
                        VStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(ZDDesign.cyanAccent, lineWidth: 2)
                                .frame(width: 260, height: 260)
                            Text("Point at \(selectedMode == .qr ? "QR code" : "document")")
                                .font(.caption)
                                .foregroundColor(ZDDesign.pureWhite)
                                .padding(6)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(6)
                        }
                    }
                }

                Spacer()

                // Mode selector
                VStack(spacing: 12) {
                    Picker("Mode", selection: $selectedMode) {
                        Text("QR Code").tag(ScanMode.qr)
                        Text("Document").tag(ScanMode.document)
                        Text("Torch/Signal").tag(ScanMode.torch)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedMode) { oldMode, newMode in
                        scanner.stopScanning()
                        scanner.startScanning(mode: newMode)
                    }

                    // Mode-specific controls
                    if selectedMode == .torch {
                        VStack(spacing: 8) {
                            Button(action: { Task { scanner.sendSOS() } }) {
                                HStack {
                                    Image(systemName: "flashlight.on.fill")
                                    Text("Send SOS")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(.red.opacity(0.2))
                                .cornerRadius(6)
                                .foregroundColor(.red)
                            }

                            Button(action: {}) {
                                HStack {
                                    Image(systemName: "ellipsis")
                                    Text("Send Morse")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(ZDDesign.cyanAccent.opacity(0.2))
                                .cornerRadius(6)
                                .foregroundColor(ZDDesign.cyanAccent)
                            }
                        }
                    } else {
                        Text("Scanning...")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
                .padding()
                .background(ZDDesign.darkCard)

                // Result display
                if let result = scanner.lastResult {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(ZDDesign.successGreen)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan successful")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(ZDDesign.pureWhite)

                                Text(result.data)
                                    .font(.caption2)
                                    .foregroundColor(ZDDesign.mediumGray)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button(action: { UIPasteboard.general.string = result.data }) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(ZDDesign.cyanAccent)
                            }
                        }
                        .padding(8)
                        .background(ZDDesign.darkCard.opacity(0.5))
                        .cornerRadius(6)
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            scanner.startScanning(mode: selectedMode)
        }
        .onDisappear {
            scanner.stopScanning()
        }
    }
}

#Preview {
    TacticalScannerView()
}
