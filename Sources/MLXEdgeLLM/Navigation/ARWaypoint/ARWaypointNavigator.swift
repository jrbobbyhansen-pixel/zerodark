// ARWaypointNavigator.swift — Walk-to-waypoint AR heading overlay.
//
// Deliberately NOT an ARKit world-tracking view. Pure compass + GPS bearing is
// more robust in degraded-SLAM scenarios (caves, low light, featureless terrain).
//
// Pipeline:
//   - AVCaptureVideoPreviewLayer renders the rear camera fullscreen as background
//   - BreadcrumbEngine.shared.heading drives the "which way am I facing" input
//   - Current position from LocationManager.shared.currentLocation
//   - Great-circle bearing from current → target; delta = targetBearing - heading
//   - Arrow rotates by delta so it always points toward the target
//   - HUD shows distance, bearing, bearing delta, ETA at walking pace (1.4 m/s)

import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - ARWaypointNavigatorView

struct ARWaypointNavigatorView: View {
    let target: CLLocationCoordinate2D
    let targetName: String

    @ObservedObject private var breadcrumb = BreadcrumbEngine.shared
    @ObservedObject private var location = LocationManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ARWaypointCameraPreview()
                .ignoresSafeArea()

            // Dim scrim so the HUD stays legible over bright scenes
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                topHUD
                Spacer()
                arrowView
                Spacer()
                bottomHUD
            }
            .padding()
        }
        .navigationTitle("Walk to Waypoint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - HUDs

    private var topHUD: some View {
        VStack(spacing: 4) {
            Text(targetName.isEmpty ? "Target" : targetName)
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(String(format: "%.0f m", distanceMeters))
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .foregroundColor(ZDDesign.cyanAccent)
            if !arrivedAtTarget {
                Text("ETA \(etaString) at 1.4 m/s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("ARRIVED")
                    .font(.caption.bold())
                    .foregroundColor(ZDDesign.successGreen)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
    }

    private var bottomHUD: some View {
        HStack(spacing: 20) {
            stat(label: "HDG",  value: String(format: "%03.0f°", breadcrumb.heading))
            stat(label: "BRG",  value: String(format: "%03.0f°", targetBearingDeg))
            stat(label: "Δ",    value: String(format: "%+04.0f°", deltaDeg), tint: deltaTint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
    }

    private func stat(label: String, value: String, tint: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundColor(tint)
        }
    }

    // MARK: - Arrow

    private var arrowView: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.4), lineWidth: 1)
                .frame(width: 240, height: 240)
            Circle()
                .fill(ZDDesign.cyanAccent.opacity(arrivedAtTarget ? 0.35 : 0.12))
                .frame(width: 200, height: 200)
            if arrivedAtTarget {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 120))
                    .foregroundColor(ZDDesign.successGreen)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundColor(ZDDesign.cyanAccent)
                    .rotationEffect(.degrees(deltaDeg))
                    .animation(.easeOut(duration: 0.15), value: deltaDeg)
            }
        }
    }

    // MARK: - Computed

    private var currentCoord: CLLocationCoordinate2D {
        location.locationOrDefault
    }

    private var distanceMeters: Double {
        currentCoord.distance(to: target)
    }

    private var arrivedAtTarget: Bool { distanceMeters < 5 }

    private var targetBearingDeg: Double {
        Self.bearingDeg(from: currentCoord, to: target)
    }

    /// Delta is normalized to (-180, 180]. Positive = target to the right of heading.
    private var deltaDeg: Double {
        var d = targetBearingDeg - breadcrumb.heading
        while d >  180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
    }

    private var deltaTint: Color {
        let abs = Swift.abs(deltaDeg)
        if abs < 10 { return ZDDesign.successGreen }
        if abs < 45 { return ZDDesign.cyanAccent }
        return ZDDesign.safetyYellow
    }

    private var etaString: String {
        guard !arrivedAtTarget else { return "--" }
        let seconds = distanceMeters / 1.4
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "< 1 min" }
        return "\(minutes) min"
    }

    // MARK: - Math

    /// Initial great-circle bearing from a → b in degrees (0–360, 0 = north, 90 = east).
    static func bearingDeg(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude  * .pi / 180
        let lat2 = b.latitude  * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brad = atan2(y, x)
        let bdeg = brad * 180 / .pi
        return (bdeg + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Camera Preview

struct ARWaypointCameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.configureSession()
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { super.init(coder: coder); backgroundColor = .black }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }

        func configureSession() {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.beginConfiguration()
            session.sessionPreset = .high
            session.addInput(input)
            session.commitConfiguration()

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)
            self.previewLayer = layer

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        deinit {
            session.stopRunning()
        }
    }
}
