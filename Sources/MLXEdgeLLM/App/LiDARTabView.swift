// LiDARTabView.swift — Tactical LiDAR Scanning Interface with AR Mesh Visualization

import SwiftUI
import ARKit
import RealityKit
import AVFoundation

struct LiDARTabView: View {
    @ObservedObject private var engine = LiDARCaptureEngine.shared
    @ObservedObject private var analyzer = TacticalRoomAnalyzer.shared
    @State private var showingResults = false
    @ObservedObject private var reconEngine = ReconWalkEngine.shared
    @State private var showReconWalk = false
    @State private var lidarMode: LiDARMode = .full
    @State private var scanSpeedMode: ScanSpeedMode = .standard
    @State private var showPermissionAlert = false
    @State private var showRoomIntelReport = false
    @State private var roomIntelReport: RoomIntelReport? = nil
    @State private var shareURL: URL?
    @State private var showTerrainAnalysis = false
    @State private var terrainPointCloud: [SIMD3<Float>] = []
    @State private var showContourGenerator = false
    @State private var scanOrigin: CLLocationCoordinate2D? = nil
    @State private var showAnnotations = false

    var body: some View {
        NavigationStack {
            ZStack {
                // AR view always present - session starts/stops with scan
                LiDARARView(engine: engine, mode: lidarMode)
                    .ignoresSafeArea()

                VStack {
                    // Top HUD — always visible during scan
                    if engine.isScanning {
                        scanHUD
                    }

                    Spacer()

                    // Scan mode and controls at bottom
                    scanControls
                }
            }
            .navigationTitle("LiDAR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if !terrainPointCloud.isEmpty {
                            Button {
                                showTerrainAnalysis = true
                            } label: {
                                Image(systemName: "mountain.2")
                            }
                            .a11yIcon("Terrain slope analysis")
                            Button {
                                showContourGenerator = true
                            } label: {
                                Image(systemName: "lines.measurement.horizontal")
                            }
                            .a11yIcon("Contour generator")
                        }
                        Button {
                            showAnnotations = true
                        } label: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .a11yIcon("Scan annotations")
                        Button {
                            showingResults = true
                        } label: {
                            Image(systemName: "list.bullet.below.rectangle")
                        }
                        .a11yIcon("Scan gallery")
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                ScanGalleryView()
            }
            .fullScreenCover(isPresented: $showReconWalk) {
                ReconWalkActiveView()
            }
            // Auto-dismiss Recon Walk full screen when engine stops (handles stop from within the cover)
            .onChange(of: reconEngine.isRecording) { _, recording in
                if !recording { showReconWalk = false }
            }
            .onChange(of: engine.isScanning) { _, scanning in
                if !scanning, let result = engine.lastScanResult {
                    // Generate room intel report — show it alone (not showingResults, which conflicts)
                    Task {
                        let report = await analyzer.analyzeRoom(
                            meshAnchors: result.meshAnchors,
                            pointCloud: result.pointCloud,
                            scanDuration: result.scanDuration,
                            speedMode: scanSpeedMode
                        )
                        roomIntelReport = report
                        showRoomIntelReport = true
                    }
                    // Capture point cloud for terrain slope analysis and contour generation
                    terrainPointCloud = result.pointCloud
                    scanOrigin = result.location
                }
            }
            .onAppear { checkCameraPermission() }
            .alert("Camera Access Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("ZeroDark needs camera access to perform LiDAR scanning. Enable it in Settings → Privacy → Camera.")
            }
            .sheet(isPresented: $showRoomIntelReport) {
                if let report = roomIntelReport {
                    RoomIntelReportView(report: report) { text in
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let url = docs.appendingPathComponent("room-intel-\(Int(Date().timeIntervalSince1970)).txt")
                        try? text.write(to: url, atomically: true, encoding: .utf8)
                        showRoomIntelReport = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            shareURL = url
                        }
                    }
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(isPresented: $showTerrainAnalysis) {
                TerrainSlopeAnalyzerView(pointCloud: terrainPointCloud)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showContourGenerator) {
                ContourGeneratorView(
                    pointCloud: terrainPointCloud,
                    scanOrigin: scanOrigin
                )
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showAnnotations) {
                PointCloudAnnotatorView()
            }
        }
    }

    // MARK: - Scan HUD (shown during active scan)

    private var scanHUD: some View {
        VStack(spacing: 4) {
            HStack {
                // Point count with threshold indicator
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(engine.currentPointCount.formatted()) pts", systemImage: "cube.fill")
                        .font(.caption.monospaced())
                        .foregroundColor(engine.hasReachedMinimum ? ZDDesign.successGreen : ZDDesign.cyanAccent)
                    
                    // Points per second rate
                    Text("\(engine.pointsPerSecond) pts/sec")
                        .font(.caption2.monospaced())
                        .foregroundColor(.gray)
                }
                .padding(6)
                .background(ZDDesign.darkBackground.opacity(0.7))
                .cornerRadius(6)

                Spacer()

                // Quality indicator (5 bars targeting 200K points)
                HStack(spacing: 2) {
                    ForEach(0..<5) { i in
                        Rectangle()
                            .fill(Float(i) < engine.scanProgress * 5 ? qualityColor : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 16)
                            .cornerRadius(2)
                    }
                }
                .padding(6)
                .background(ZDDesign.darkBackground.opacity(0.7))
                .cornerRadius(6)
            }
            .padding(.horizontal)
            
            // Guidance message - real-time feedback
            Text(engine.scanGuidance.rawValue)
                .font(.caption.bold())
                .foregroundColor(guidanceColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ZDDesign.darkBackground.opacity(0.8))
                .cornerRadius(8)

            // Progress bar
            ProgressView(value: engine.scanProgress)
                .tint(qualityColor)
                .padding(.horizontal)
            
            // Coverage heat map — shows which directions have been scanned
            coverageGridView
                .padding(.top, 8)
        }
        .padding(.top, 8)
    }
    
    private var qualityColor: Color {
        if engine.currentPointCount >= LiDARCaptureEngine.goodScanPoints {
            return .green
        } else if engine.currentPointCount >= LiDARCaptureEngine.minimumUsablePoints {
            return .yellow
        } else {
            return ZDDesign.cyanAccent
        }
    }
    
    private var guidanceColor: Color {
        switch engine.scanGuidance {
        case .scanSlower, .moveCloser:
            return .orange
        case .excellentScan, .goodScan:
            return .green
        case .minimumReached:
            return .yellow
        default:
            return .white
        }
    }
    
    // MARK: - Coverage Heat Map
    
    /// 8x8 grid showing which directions have been scanned
    /// Rows = pitch (up/down), Cols = yaw (left/right)
    /// Green = well covered, red/empty = needs scanning
    private var coverageGridView: some View {
        VStack(spacing: 1) {
            // Labels for orientation
            HStack {
                Text("←")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
                Text("COVERAGE")
                    .font(.caption2.bold())
                    .foregroundColor(ZDDesign.pureWhite)
                Spacer()
                Text("→")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 4)
            
            // The actual grid
            VStack(spacing: 1) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<8, id: \.self) { col in
                            let density = engine.coverageGrid[row][col]
                            let maxDensity = engine.coverageGrid.flatMap { $0 }.max() ?? 1.0
                            let normalized = maxDensity > 0 ? density / maxDensity : 0
                            
                            Rectangle()
                                .fill(coverageColor(for: normalized))
                                .frame(width: 12, height: 8)
                        }
                    }
                }
            }
            .padding(4)
            .background(ZDDesign.darkBackground.opacity(0.7))
            .cornerRadius(6)
        }
        .frame(width: 120)
    }
    
    private func coverageColor(for density: Float) -> Color {
        if density < 0.1 {
            return Color.red.opacity(0.3)  // Not scanned
        } else if density < 0.5 {
            return Color.yellow.opacity(0.6)  // Partial
        } else {
            return Color.green.opacity(0.8)  // Good coverage
        }
    }

    // MARK: - Permission Check

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted { DispatchQueue.main.async { showPermissionAlert = true } }
            }
        case .denied, .restricted:
            showPermissionAlert = true
        case .authorized:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Scan Controls (always at bottom)

    private var scanControls: some View {
        VStack(spacing: 12) {
            // Speed mode selector (only when not scanning)
            if !engine.isScanning {
                HStack(spacing: 8) {
                    ForEach(ScanSpeedMode.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { scanSpeedMode = mode }
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: mode.icon)
                                    .font(.caption)
                                Text(mode.rawValue)
                                    .font(.caption2.bold())
                                Text(mode.description)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .background(scanSpeedMode == mode ? mode.color.opacity(0.25) : ZDDesign.darkCard)
                            .foregroundColor(scanSpeedMode == mode ? mode.color : .secondary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(scanSpeedMode == mode ? mode.color : Color.clear, lineWidth: 1)
                            )
                        }
                        .accessibilityLabel("\(mode.rawValue) scan mode: \(mode.description)")
                    }
                }
                .padding(.horizontal)
            }

            // Live tactical counts during scan
            if engine.isScanning {
                HStack(spacing: 16) {
                    Label("\(analyzer.liveEntryCount) entries", systemImage: "door.right.hand.closed")
                        .font(.caption.monospaced())
                        .foregroundColor(.orange)
                    Label("\(analyzer.liveCoverCount) cover", systemImage: "shield.fill")
                        .font(.caption.monospaced())
                        .foregroundColor(.green)
                }
                .padding(.horizontal)
            }

            // Mode picker: Depth / Mesh / Full
            Picker("Mode", selection: $lidarMode) {
                ForEach(LiDARMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: lidarMode) { _, _ in }

            // Two-button row: Quick Scan + Recon Walk
            HStack(spacing: 12) {
                // Quick Scan — speed mode configures capture parameters
                Button {
                    if engine.isScanning {
                        engine.stopScan()
                    } else {
                        var config = LiDARScanConfig()
                        // Apply LOD parameters based on speed mode
                        switch scanSpeedMode {
                        case .fast:     config.meshDetail = .low
                        case .standard: config.meshDetail = .medium
                        case .detailed: config.meshDetail = .high
                        }
                        engine.startScan(config: config)
                    }
                } label: {
                    HStack {
                        Image(systemName: engine.isScanning ? "stop.circle.fill" : "viewfinder.circle.fill")
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text(engine.isScanning ? "STOP" : "\(scanSpeedMode.rawValue.uppercased()) SCAN")
                            .font(.headline.bold())
                    }
                    .foregroundColor(ZDDesign.pureWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(engine.isScanning ? ZDDesign.signalRed : ZDDesign.forestGreen)
                    .cornerRadius(12)
                }
                .accessibilityLabel(engine.isScanning ? "Stop scan" : "Start \(scanSpeedMode.rawValue) scan")

                // Recon Walk
                Button {
                    if reconEngine.isRecording {
                        reconEngine.stopReconWalk()
                    } else {
                        showReconWalk = true
                    }
                } label: {
                    HStack {
                        Image(systemName: reconEngine.isRecording ? "stop.circle.fill" : "figure.walk")
                            .font(.title2)
                            .accessibilityHidden(true)
                        Text(reconEngine.isRecording ? "STOP" : "RECON WALK")
                            .font(.headline.bold())
                    }
                    .foregroundColor(ZDDesign.pureWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(reconEngine.isRecording ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                    .cornerRadius(12)
                }
                .accessibilityLabel(reconEngine.isRecording ? "Stop recon walk" : "Start recon walk")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - ARView wrapper for live mesh visualization

struct LiDARARView: UIViewRepresentable {
    @ObservedObject var engine: LiDARCaptureEngine
    var mode: LiDARMode = .full
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Request camera permission if needed
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.startARSession(arView)
                    }
                }
            }
        } else if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            startARSession(arView)
        }
        
        return arView
    }
    
    private func startARSession(_ arView: ARView) {
        // Set up the ARView for the engine (gives it the session reference)
        engine.setupARView(arView)
        
        // Start with scene reconstruction enabled so mesh can show immediately when scanning starts
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .none
        
        // Enable LiDAR mesh reconstruction from the start (required for mesh visualization)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        // Enable depth semantics if available
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        
        arView.session.run(config)
        
        // Enable scene understanding for mesh display
        arView.environment.sceneUnderstanding.options = [.occlusion, .receivesLighting]
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if engine.isScanning {
            // Mode-dependent visualization
            if mode.showsMesh {
                uiView.debugOptions = [.showSceneUnderstanding]
            } else {
                uiView.debugOptions = []
            }
        } else {
            uiView.debugOptions = []
        }
    }
    
    class Coordinator: NSObject {
        var parent: LiDARARView

        init(_ parent: LiDARARView) {
            self.parent = parent
        }
    }
}

