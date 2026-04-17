// ArmDeviceView.swift — First-launch model download screen
// Shown once after first boot. Downloads AI models so the device works fully offline.

import SwiftUI

struct ArmDeviceView: View {
    @ObservedObject private var downloader  = ModelDownloadManager.shared
    @ObservedObject private var llmEngine   = LocalInferenceEngine.shared
    @AppStorage("device_armed") private var deviceArmed = false
    @State private var showSkipConfirm = false
    @State private var llmDownloading  = false

    // True once all three models are ready (downloaded or previously cached)
    private var allReady: Bool {
        llmEngine.modelState == .ready &&
        downloader.embeddingStatus == .downloaded &&
        downloader.visionStatus    == .downloaded
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Header
                VStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 52, weight: .ultraLight))
                        .foregroundColor(ZDDesign.cyanAccent)

                    Text("ARM YOUR DEVICE")
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundColor(ZDDesign.pureWhite)
                        .tracking(6)

                    Text("DOWNLOAD ONCE. OPERATE FOREVER OFFLINE.")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(ZDDesign.mediumGray)
                        .tracking(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 40)

                // Model rows
                VStack(spacing: 14) {
                    ModelDownloadRow(
                        icon:        "brain",
                        name:        "Field AI",
                        detail:      "2.2 GB · Phi-3.5-mini",
                        description: "Answers any field question — TCCC, survival, tactics — fully offline.",
                        status:      llmRowStatus,
                        onDownload:  startLLMDownload
                    )

                    ModelDownloadRow(
                        icon:        "cpu",
                        name:        "Smart Search",
                        detail:      "22 MB · Embedding model",
                        description: "Finds related content without exact keywords. \"stopped breathing\" → CPR.",
                        status:      downloader.embeddingStatus,
                        onDownload:  downloader.downloadEmbeddingModel
                    )

                    ModelDownloadRow(
                        icon:        "eye.fill",
                        name:        "Vision AI",
                        detail:      "1.7 GB · moondream2",
                        description: "Identifies plants, assesses wounds, reads terrain and maps from photos.",
                        status:      downloader.visionStatus,
                        onDownload:  downloader.downloadVisionModel
                    )
                }
                .padding(.horizontal, 24)

                // Total size note
                Text("~4 GB one-time download over WiFi recommended")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)
                    .padding(.top, 16)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    if allReady {
                        Button(action: completeArming) {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                Text("Device Armed — Enter App")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(ZDDesign.successGreen)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                        }
                    } else {
                        Button(action: downloadAll) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download All Models")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(ZDDesign.cyanAccent)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                        }
                        .disabled(anyDownloadActive)
                    }

                    Button("Skip for now") {
                        showSkipConfirm = true
                    }
                    .font(.footnote)
                    .foregroundColor(ZDDesign.mediumGray)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .confirmationDialog(
            "Skip model download?",
            isPresented: $showSkipConfirm,
            titleVisibility: .visible
        ) {
            Button("Skip — I'll download later", role: .destructive) {
                completeArming()
            }
            Button("Keep downloading", role: .cancel) {}
        } message: {
            Text("Without models: AI answers, semantic search, and vision analysis will be unavailable until you download them from Settings.")
        }
        .onChange(of: allReady) { _, ready in
            if ready { completeArming() }
        }
    }

    // MARK: - LLM state bridging

    private var llmRowStatus: ModelDownloadManager.DownloadStatus {
        switch llmEngine.modelState {
        case .ready:                return .downloaded
        case .loading:              return .downloading(progress: llmEngine.loadProgress)
        case .notLoaded:            return .notDownloaded
        case .error(let e):         return .failed(e)
        }
    }

    private var anyDownloadActive: Bool {
        if case .downloading = llmRowStatus            { return true }
        if case .downloading = downloader.embeddingStatus { return true }
        if case .downloading = downloader.visionStatus    { return true }
        return false
    }

    // MARK: - Actions

    private func downloadAll() {
        startLLMDownload()
        downloader.downloadAll()
    }

    private func startLLMDownload() {
        guard llmEngine.modelState == .notLoaded else { return }
        llmDownloading = true
        Task {
            await LocalInferenceEngine.shared.loadModel()
        }
    }

    private func completeArming() {
        deviceArmed = true
    }
}

// MARK: - ModelDownloadRow

private struct ModelDownloadRow: View {
    let icon:        String
    let name:        String
    let detail:      String
    let description: String
    let status:      ModelDownloadManager.DownloadStatus
    let onDownload:  () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBackground)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ZDDesign.pureWhite)
                    Spacer()
                    statusBadge
                }

                Text(detail)
                    .font(.caption2)
                    .foregroundColor(ZDDesign.mediumGray)

                Text(description)
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                if case .downloading(let progress) = status {
                    ProgressView(value: progress)
                        .tint(ZDDesign.cyanAccent)
                        .padding(.top, 4)
                }

                if case .failed(let msg) = status {
                    Text("⚠ \(msg)")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.signalRed)
                }
            }
        }
        .padding(14)
        .background(ZDDesign.darkCard)
        .cornerRadius(12)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .notDownloaded:
            Button(action: onDownload) {
                Text("Download")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ZDDesign.cyanAccent)
                    .foregroundColor(.black)
                    .cornerRadius(6)
            }
        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(ZDDesign.cyanAccent)
        case .unpacking:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6).tint(ZDDesign.safetyYellow)
                Text("Unpacking")
                    .font(.caption2)
                    .foregroundColor(ZDDesign.safetyYellow)
            }
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(ZDDesign.successGreen)
                .font(.title3)
        case .failed:
            Button(action: onDownload) {
                Text("Retry")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ZDDesign.signalRed.opacity(0.2))
                    .foregroundColor(ZDDesign.signalRed)
                    .cornerRadius(6)
            }
        }
    }

    private var iconColor: Color {
        switch status {
        case .downloaded: return ZDDesign.successGreen
        case .downloading, .unpacking: return ZDDesign.cyanAccent
        case .failed: return ZDDesign.signalRed
        case .notDownloaded: return ZDDesign.mediumGray
        }
    }

    private var iconBackground: Color {
        iconColor.opacity(0.15)
    }
}

#Preview {
    ArmDeviceView()
}
