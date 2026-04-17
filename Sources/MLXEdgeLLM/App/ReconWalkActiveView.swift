import SwiftUI
import ARKit
import RealityKit

struct ReconWalkActiveView: View {
    @ObservedObject private var engine = ReconWalkEngine.shared
    @Environment(\.dismiss) var dismiss: DismissAction
    @State private var covertMode: ReconWalkConfig.CovertMode = .none

    var body: some View {
        ZStack {
            // Background based on covert mode
            Group {
                switch covertMode {
                case .none:
                    ReconARView()
                        .ignoresSafeArea()
                case .texting:
                    CovertTextingView()
                case .photo:
                    CovertPhotoView()
                case .map:
                    CovertMapView()
                }
            }

            // HUD overlay (always visible, subtle)
            VStack {
                // Top: recording indicator + timer + covert switcher
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 10, height: 10)
                            .opacity(engine.isRecording ? 1 : 0)
                        Text(formatTime(engine.elapsedTime))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(ZDDesign.pureWhite)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)

                    Spacer()

                    Menu {
                        ForEach(ReconWalkConfig.CovertMode.allCases, id: \.self) { mode in
                            Button(mode.label) { covertMode = mode }
                        }
                    } label: {
                        Image(systemName: "eye.slash")
                            .foregroundColor(ZDDesign.pureWhite)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                }
                .padding()

                Spacer()

                // Bottom: stats + stop button
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        ReconStatBadge(icon: "ruler", value: "\(Int(engine.distanceWalked))m", label: "Distance")
                        ReconStatBadge(icon: "cube.fill", value: formatLargeNumber(engine.pointCount), label: "Points")
                        ReconStatBadge(icon: "square.stack.3d.up", value: "\(engine.segmentCount)", label: "Segments")
                        ReconStatBadge(icon: "square.fill", value: "\(Int(engine.coverageArea))m²", label: "Coverage")
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Button {
                        engine.stopReconWalk()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("STOP & SAVE").fontWeight(.bold)
                        }
                        .foregroundColor(ZDDesign.pureWhite)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(ZDDesign.signalRed)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear { engine.startReconWalk() }
        .onDisappear { if engine.isRecording { engine.stopReconWalk() } }
    }

    func formatTime(_ s: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60)
    }

    func formatLargeNumber(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n)/1_000_000) :
        n >= 1_000    ? String(format: "%.1fK", Double(n)/1_000) : "\(n)"
    }
}

struct ReconStatBadge: View {
    let icon: String; let value: String; let label: String
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.caption2)
                Text(value).font(.caption.monospacedDigit()).fontWeight(.bold)
            }
            .foregroundColor(ZDDesign.cyanAccent)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
    }
}

// MARK: - AR View

struct ReconARView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.debugOptions = [.showSceneUnderstanding]
        arView.environment.sceneUnderstanding.options = .occlusion
        // Engine manages the actual ARSession; arView just renders
        if let session = ReconWalkEngine.shared.arSession {
            arView.session = session
        }
        return arView
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Covert Mode Views

struct CovertTextingView: View {
    @State private var messages: [(String, Bool)] = [
        ("Hey, what's up?", true), ("Just walking around", false),
        ("Cool, where?", true), ("Near the park", false), ("Nice day for it 👍", true)
    ]
    @State private var draft = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.left").foregroundColor(.blue)
                Text("Messages").fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(uiColor: .systemGray6))
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(messages.indices, id: \.self) { i in
                        HStack {
                            if !messages[i].1 { Spacer() }
                            Text(messages[i].0)
                                .padding(12)
                                .background(messages[i].1 ? Color(uiColor: .systemGray5) : .blue)
                                .foregroundColor(messages[i].1 ? .primary : .white)
                                .cornerRadius(18)
                            if messages[i].1 { Spacer() }
                        }
                    }
                }
                .padding()
            }
            HStack {
                TextField("iMessage", text: $draft)
                    .padding(10)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(20)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2).foregroundColor(.blue)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
        }
        .preferredColorScheme(.light)
    }
}

struct CovertPhotoView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                HStack(spacing: 60) {
                    Image(systemName: "photo.on.rectangle").font(.title).foregroundColor(ZDDesign.pureWhite)
                    Circle().stroke(.white, lineWidth: 3).frame(width: 70, height: 70)
                        .overlay(Circle().stroke(.white, lineWidth: 6).frame(width: 64, height: 64))
                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title).foregroundColor(ZDDesign.pureWhite)
                }
                .padding(.bottom, 50)
            }
        }
    }
}

struct CovertMapView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGray5).ignoresSafeArea()
            VStack {
                Text("Checking directions...")
                    .foregroundColor(ZDDesign.mediumGray)
                    .font(.caption)
            }
        }
    }
}
