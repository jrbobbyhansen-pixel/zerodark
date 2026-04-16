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
                    Button {
                        showingResults = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                ScanGalleryView()
            }
            .fullScreenCover(isPresented: $showReconWalk) {
                ReconWalkActiveView()
            }
            .onChange(of: engine.isScanning) { _, scanning in
                if !scanning, let result = engine.lastScanResult {
                    // Generate tactical room report from scan
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
                    showingResults = true
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
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("room-intel-\(Int(Date().timeIntervalSince1970)).txt")
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
                                    .font(.system(size: 8))
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
            .onChange(of: lidarMode) { _, newMode in
                // engine.pipeline?.activeMode = newMode  — deferred
            }

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
                        Text(engine.isScanning ? "STOP" : "\(scanSpeedMode.rawValue.uppercased()) SCAN")
                            .font(.headline.bold())
                    }
                    .foregroundColor(ZDDesign.pureWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(engine.isScanning ? ZDDesign.signalRed : ZDDesign.forestGreen)
                    .cornerRadius(12)
                }

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
                        Text(reconEngine.isRecording ? "STOP" : "RECON WALK")
                            .font(.headline.bold())
                    }
                    .foregroundColor(ZDDesign.pureWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(reconEngine.isRecording ? ZDDesign.signalRed : ZDDesign.cyanAccent)
                    .cornerRadius(12)
                }
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

// MARK: - Post-scan results sheet

struct LiDARResultsView: View {
    let result: LiDARScanResult
    @Environment(\.dismiss) var dismiss: DismissAction
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary header card
                summaryCard

                // Tab picker: Structural / Tactical / Terrain
                Picker("Analysis", selection: $selectedTab) {
                    Text("Structural").tag(0)
                    Text("Tactical").tag(1)
                    Text("Terrain").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content
                ScrollView {
                    switch selectedTab {
                    case 0: structuralView
                    case 1: tacticalView
                    default: terrainView
                    }
                }
            }
            .navigationTitle("Scan Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        shareScanAsCoT(result)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            // Threat level badge
            let level = result.tacticalAnalysis?.riskScore ?? 0
            VStack {
                Image(systemName: threatIcon(level))
                    .font(.title)
                    .foregroundColor(threatColor(level))
                Text(threatLabel(level))
                    .font(.caption.bold())
                    .foregroundColor(threatColor(level))
            }
            .frame(width: 80)
            .padding()
            .background(ZDDesign.darkBackground.opacity(0.4))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(result.pointCount.formatted()) points")
                    .font(.headline)
                if let structural = result.structuralAnalysis {
                    Text("\(structural.surfaces.count) surfaces · \(structural.openings.count) openings")
                        .font(.caption).foregroundColor(ZDDesign.mediumGray)
                    if !structural.entryPoints.isEmpty {
                        Text("\(structural.entryPoints.count) entry points")
                            .font(.caption).foregroundColor(ZDDesign.safetyYellow)
                    }
                }
                if let tactical = result.tacticalAnalysis {
                    Text("\(tactical.observationPosts.count) OPs · \(tactical.approachRoutes.count) routes")
                        .font(.caption).foregroundColor(ZDDesign.cyanAccent)
                }
                Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundColor(ZDDesign.mediumGray)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.15))
    }

    private var structuralView: some View {
        LazyVStack(spacing: 8) {
            guard let s = result.structuralAnalysis else {
                return AnyView(Text("No structural data").foregroundColor(ZDDesign.mediumGray).padding())
            }
            return AnyView(VStack(spacing: 8) {
                // Entry points
                if !s.entryPoints.isEmpty {
                    analysisSection(
                        title: "Entry Points (\(s.entryPoints.count))",
                        icon: "door.right.hand.open",
                        color: ZDDesign.safetyYellow
                    ) {
                        ForEach(s.entryPoints, id: \.id) { ep in
                            HStack {
                                Text(ep.opening.type.description)
                                Spacer()
                                Text(String(format: "%.1f × %.1fm", ep.opening.dimensions.x, ep.opening.dimensions.y))
                                    .font(.caption.monospaced())
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Surfaces
                analysisSection(title: "Surfaces (\(s.surfaces.count))", icon: "square.3.layers.3d", color: ZDDesign.skyBlue) {
                    let grouped = Dictionary(grouping: s.surfaces, by: \.type)
                    ForEach(grouped.keys.sorted(by: { $0.description < $1.description }), id: \.self) { type in
                        HStack {
                            Text(type.description)
                            Spacer()
                            Text("\(grouped[type]?.count ?? 0)")
                                .font(.caption.monospaced())
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                }

                // Vulnerabilities
                if !s.structuralVulnerabilities.isEmpty {
                    analysisSection(title: "Vulnerabilities (\(s.structuralVulnerabilities.count))", icon: "exclamationmark.shield", color: ZDDesign.signalRed) {
                        ForEach(s.structuralVulnerabilities, id: \.id) { v in
                            Text(v.description)
                                .font(.caption)
                                .padding(.vertical, 2)
                        }
                    }
                }
            })
        }
        .padding()
    }

    private var tacticalView: some View {
        LazyVStack(spacing: 8) {
            guard let t = result.tacticalAnalysis else {
                return AnyView(Text("No tactical data").foregroundColor(ZDDesign.mediumGray).padding())
            }
            return AnyView(VStack(spacing: 8) {
                // Overall assessment text
                Text(t.overallAssessment)
                    .font(.caption)
                    .padding()
                    .background(ZDDesign.darkBackground.opacity(0.3))
                    .cornerRadius(8)

                if !t.observationPosts.isEmpty {
                    analysisSection(title: "Observation Posts (\(t.observationPosts.count))", icon: "binoculars.fill", color: ZDDesign.cyanAccent) {
                        ForEach(t.observationPosts.prefix(5), id: \.id) { op in
                            HStack {
                                Text("Coverage: \(Int(op.coverage * 100))%")
                                Spacer()
                                Text("Concealment: \(Int(op.concealment * 100))%")
                                    .font(.caption.monospaced())
                            }
                            .font(.caption)
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !t.concealmentPositions.isEmpty {
                    analysisSection(title: "Concealment (\(t.concealmentPositions.count))", icon: "eye.slash", color: ZDDesign.darkSage) {
                        ForEach(t.concealmentPositions.prefix(5), id: \.id) { pos in
                            Text("Radius: \(Int(pos.radius))m")
                                .font(.caption)
                                .padding(.vertical, 2)
                        }
                    }
                }

                if !t.approachRoutes.isEmpty {
                    analysisSection(title: "Approach Routes (\(t.approachRoutes.count))", icon: "arrow.triangle.turn.up.right.circle", color: ZDDesign.forestGreen) {
                        ForEach(t.approachRoutes.prefix(3), id: \.id) { route in
                            Text(route.description)
                                .font(.caption)
                                .padding(.vertical, 2)
                        }
                    }
                }
            })
        }
        .padding()
    }

    private var terrainView: some View {
        LazyVStack(spacing: 8) {
            guard let t = result.terrainAnalysis else {
                return AnyView(Text("No terrain data").foregroundColor(ZDDesign.mediumGray).padding())
            }
            return AnyView(VStack(spacing: 8) {
                if !t.coverPositions.isEmpty {
                    analysisSection(title: "Cover Positions (\(t.coverPositions.count))", icon: "shield.fill", color: ZDDesign.forestGreen) {
                        ForEach(t.coverPositions.prefix(5), id: \.id) { pos in
                            HStack {
                                Text(pos.type.description)
                                Spacer()
                                Text("Protection: \(Int(pos.protection * 100))%")
                                    .font(.caption.monospaced())
                            }
                            .font(.caption)
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !t.deadSpace.isEmpty {
                    analysisSection(title: "Dead Space (\(t.deadSpace.count) zones)", icon: "eye.trianglebadge.exclamationmark", color: ZDDesign.sunsetOrange) {
                        Text("Areas not visible from current position — movement corridors available")
                            .font(.caption)
                    }
                }
            })
        }
        .padding()
    }

    // Helper: section card builder
    @ViewBuilder
    private func analysisSection<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundColor(color)
            content()
        }
        .padding()
        .background(ZDDesign.darkBackground.opacity(0.35))
        .cornerRadius(10)
    }

    // Share scan summary as CoT message to TAK peers
    private func shareScanAsCoT(_ result: LiDARScanResult) {
        guard let loc = result.location else { return }
        let summary = """
        LiDAR Scan Report
        Points: \(result.pointCount)
        Surfaces: \(result.structuralAnalysis?.surfaces.count ?? 0)
        Entry Points: \(result.structuralAnalysis?.entryPoints.count ?? 0)
        Cover Positions: \(result.terrainAnalysis?.coverPositions.count ?? 0)
        Risk: \(result.tacticalAnalysis.map { $0.riskScore < 0.3 ? "LOW" : $0.riskScore < 0.7 ? "MEDIUM" : "HIGH" } ?? "UNKNOWN")
        Location: \(MGRSConverter.toMGRS(coordinate: loc, precision: 4))
        """
        FreeTAKConnector.shared.sendPresence(coordinate: loc, callsign: AppConfig.deviceCallsign + "-SCAN")
        MeshService.shared.broadcastText(summary)
    }

    // Threat display helpers
    private func threatColor(_ score: Float) -> Color {
        score < 0.3 ? ZDDesign.successGreen : score < 0.7 ? ZDDesign.safetyYellow : ZDDesign.signalRed
    }
    private func threatIcon(_ score: Float) -> String {
        score < 0.3 ? "checkmark.shield.fill" : score < 0.7 ? "exclamationmark.triangle.fill" : "xmark.shield.fill"
    }
    private func threatLabel(_ score: Float) -> String {
        score < 0.3 ? "LOW RISK" : score < 0.7 ? "ELEVATED" : "HIGH RISK"
    }
}

// MARK: - Scan history view

struct LiDARHistoryView: View {
    @ObservedObject private var engine = LiDARCaptureEngine.shared
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            Group {
                if engine.scanHistory.isEmpty {
                    VStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("No scans yet")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(engine.scanHistory) { result in
                        NavigationLink(destination: LiDARResultsView(result: result)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(result.pointCount.formatted()) points")
                                        .font(.headline)
                                    Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundColor(ZDDesign.mediumGray)
                                    if let t = result.tacticalAnalysis {
                                        let risk = t.riskScore
                                        Text(risk < 0.3 ? "Low Risk" : risk < 0.7 ? "Elevated" : "High Risk")
                                            .font(.caption)
                                            .foregroundColor(risk < 0.3 ? ZDDesign.successGreen : risk < 0.7 ? ZDDesign.safetyYellow : ZDDesign.signalRed)
                                    }
                                }
                                Spacer()
                                if let loc = result.location {
                                    Text(MGRSConverter.toMGRS(coordinate: loc, precision: 4))
                                        .font(.caption2.monospaced())
                                        .foregroundColor(ZDDesign.mediumGray)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
