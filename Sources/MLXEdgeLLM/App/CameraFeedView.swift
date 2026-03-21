// CameraFeedView.swift — Live Traffic Camera Feed Viewer

import SwiftUI
import AVKit

enum CameraError: Error {
    case invalidURL
    case httpError(Int)
    case invalidImageData
}

struct CameraFeedView: View {
    let camera: TrafficCamera
    @Environment(\.dismiss) var dismiss
    @StateObject private var camService = TrafficCamService.shared

    @State private var currentFrame: UIImage?
    @State private var isLoading = true
    @State private var lastError: String?
    @State private var lastRefresh = Date()
    @State private var autoRefresh = true
    @State private var refreshTimer: Timer?

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Feed
                feedView

                // Controls
                controlBar
            }
        }
        .onAppear {
            loadFeed()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(camera.displayName)
                    .font(.headline)
                    .foregroundColor(ZDDesign.pureWhite)

                HStack(spacing: 8) {
                    Text(camera.source.rawValue)
                        .font(.caption)
                        .foregroundColor(ZDDesign.cyanAccent)

                    if let city = camera.city {
                        Text("• \(city)")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }

                    if let heading = camera.heading {
                        HStack(spacing: 2) {
                            Image(systemName: "location.north.fill")
                                .rotationEffect(.degrees(heading))
                            Text(cardinalDirection(heading))
                        }
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                    }
                }
            }

            Spacer()

            // Favorite button
            Button {
                if camService.isFavorite(camera) {
                    camService.removeFavorite(camera)
                } else {
                    camService.addFavorite(camera)
                }
            } label: {
                Image(systemName: camService.isFavorite(camera) ? "star.fill" : "star")
                    .foregroundColor(camService.isFavorite(camera) ? ZDDesign.safetyYellow : .white)
                    .font(.title3)
            }

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(ZDDesign.pureWhite)
                    .font(.title2)
            }
            .padding(.leading, 12)
        }
        .padding()
        .background(ZDDesign.darkCard)
    }

    // MARK: - Feed View

    @ViewBuilder
    var feedView: some View {
        switch camera.feedType {
        case .jpeg:
            jpegFeedView
        case .hls:
            hlsFeedView
        case .mjpeg, .rtsp:
            unsupportedFeedView
        }
    }

    var jpegFeedView: some View {
        ZStack {
            if let image = currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .tint(ZDDesign.cyanAccent)
                    .scaleEffect(1.5)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundColor(ZDDesign.mediumGray)
                    Text("Feed unavailable")
                        .foregroundColor(ZDDesign.mediumGray)
                    Button("Retry") {
                        loadFeed()
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Last refresh timestamp
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.pureWhite)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    var hlsFeedView: some View {
        ZStack {
            if let url = URL(string: camera.feedURL) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(ZDDesign.safetyYellow)
                    Text("Invalid HLS URL")
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
        }
        .background(Color.black)
    }

    var unsupportedFeedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(ZDDesign.safetyYellow)
            Text("\(camera.feedType.rawValue.uppercased()) streams not yet supported")
                .foregroundColor(ZDDesign.mediumGray)
            Text("RTSP support coming soon")
                .font(.caption)
                .foregroundColor(ZDDesign.mediumGray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Control Bar

    var controlBar: some View {
        HStack(spacing: 20) {
            // Auto-refresh toggle
            Button {
                autoRefresh.toggle()
                if autoRefresh {
                    startAutoRefresh()
                } else {
                    stopAutoRefresh()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: autoRefresh ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                        .font(.title2)
                    Text("Auto")
                        .font(.caption2)
                }
                .foregroundColor(autoRefresh ? ZDDesign.cyanAccent : .white)
            }

            // Manual refresh
            Button {
                loadFeed()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                    Text("Refresh")
                        .font(.caption2)
                }
                .foregroundColor(ZDDesign.pureWhite)
            }

            Spacer()

            // Share/Save frame
            if let image = currentFrame {
                Button {
                    shareFrame(image)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                        Text("Share")
                            .font(.caption2)
                    }
                    .foregroundColor(ZDDesign.pureWhite)
                }

                Button {
                    saveFrame(image)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                        Text("Save")
                            .font(.caption2)
                    }
                    .foregroundColor(ZDDesign.pureWhite)
                }
            }
        }
        .padding()
        .background(ZDDesign.darkCard)
    }

    // MARK: - Actions

    func loadFeed() {
        isLoading = true
        Task {
            do {
                guard let url = URL(string: camera.feedURL) else { throw CameraError.invalidURL }
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw CameraError.httpError(http.statusCode)
                }
                guard let image = UIImage(data: data) else { throw CameraError.invalidImageData }
                await MainActor.run { currentFrame = image; lastRefresh = Date(); isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    lastError = describeError(error)
                }
            }
        }
    }

    private func describeError(_ error: Error) -> String {
        switch error {
        case CameraError.invalidURL:
            return "Invalid camera URL"
        case CameraError.httpError(let code):
            return "Feed unavailable (HTTP \(code))"
        case CameraError.invalidImageData:
            return "Invalid image data"
        default:
            return "Feed unavailable"
        }
    }

    func startAutoRefresh() {
        guard camera.feedType == .jpeg else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            loadFeed()
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func shareFrame(_ image: UIImage) {
        let activityVC = UIActivityViewController(
            activityItems: [image, "Traffic camera: \(camera.displayName)"],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    func saveFrame(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func cardinalDirection(_ heading: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((heading + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return directions[index]
    }
}
