// ContourGeneratorView.swift — Contour generation UI from LiDAR scan
// Configures interval, triggers generation, previews results, exports GeoJSON

import SwiftUI
import MapKit

struct ContourGeneratorView: View {
    let pointCloud: [SIMD3<Float>]
    let scanOrigin: CLLocationCoordinate2D?

    @State private var interval: Double = 0.5
    @State private var isGenerating = false
    @State private var overlay: ContourOverlay? = nil
    @State private var errorMessage: String? = nil
    @State private var exportURL: URL? = nil
    @State private var addedToMap = false

    private let intervalOptions: [(label: String, value: Double)] = [
        ("0.1 m", 0.1),
        ("0.25 m", 0.25),
        ("0.5 m", 0.5),
        ("1 m", 1.0),
        ("2 m", 2.0)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Stats header
                        statsHeader

                        // Interval picker
                        intervalPicker

                        // Generate button
                        generateButton

                        // Results
                        if let overlay {
                            resultsSection(overlay: overlay)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Contour Generator")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Subviews

    private var statsHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pointCloud.count.formatted())")
                    .font(.title2.bold().monospaced())
                    .foregroundColor(ZDDesign.cyanAccent)
                Text("points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Divider().frame(height: 36)
            VStack(alignment: .leading, spacing: 2) {
                if let origin = scanOrigin {
                    Text(String(format: "%.5f, %.5f", origin.latitude, origin.longitude))
                        .font(.caption.monospaced())
                        .foregroundColor(.green)
                    Text("GPS origin")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("No GPS")
                        .font(.caption.monospaced())
                        .foregroundColor(.orange)
                    Text("contours use relative coords")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(ZDDesign.darkCard)
        .cornerRadius(10)
    }

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contour Interval")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(intervalOptions, id: \.value) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { interval = option.value }
                    } label: {
                        Text(option.label)
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(interval == option.value ? ZDDesign.cyanAccent : ZDDesign.darkCard)
                            .foregroundColor(interval == option.value ? .black : ZDDesign.pureWhite)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var generateButton: some View {
        Button {
            Task { await runGeneration() }
        } label: {
            HStack {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "lines.measurement.horizontal")
                }
                Text(isGenerating ? "Generating…" : "Generate Contours")
                    .font(.headline.bold())
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isGenerating ? Color.gray : ZDDesign.cyanAccent)
            .cornerRadius(12)
        }
        .disabled(isGenerating || pointCloud.isEmpty)
    }

    private func resultsSection(overlay: ContourOverlay) -> some View {
        VStack(spacing: 12) {
            // Summary
            let majorCount = overlay.contourLines.filter(\.isMajor).count
            let minorCount = overlay.contourLines.filter { !$0.isMajor }.count
            let elevations = overlay.contourLines.map(\.elevation)
            let minE = elevations.min() ?? 0
            let maxE = elevations.max() ?? 0

            VStack(spacing: 8) {
                HStack {
                    Label("\(overlay.contourLines.count) lines", systemImage: "lines.measurement.horizontal")
                        .font(.subheadline.bold())
                        .foregroundColor(ZDDesign.cyanAccent)
                    Spacer()
                    Text(String(format: "%.1f–%.1f m", minE, maxE))
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 16) {
                    Label("\(majorCount) major", systemImage: "line.diagonal")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Label("\(minorCount) minor", systemImage: "line.diagonal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding()
            .background(ZDDesign.darkCard)
            .cornerRadius(10)

            // Action buttons
            HStack(spacing: 12) {
                // Add to tactical map
                Button {
                    TacticalOverlayManager.shared.add(overlay)
                    addedToMap = true
                } label: {
                    HStack {
                        Image(systemName: addedToMap ? "checkmark.circle.fill" : "map.fill")
                        Text(addedToMap ? "On Map" : "Add to Map")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(addedToMap ? Color.green : ZDDesign.forestGreen)
                    .cornerRadius(10)
                }
                .disabled(addedToMap)

                // Export GeoJSON
                Button {
                    if let url = ContourGeneratorEngine.shared.saveGeoJSON(overlay) {
                        exportURL = url
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(ZDDesign.pureWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(ZDDesign.darkCard)
                    .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Generation

    private func runGeneration() async {
        isGenerating = true
        errorMessage = nil
        addedToMap = false

        let origin = scanOrigin ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let result = await ContourGeneratorEngine.shared.generate(
            source: .lidar(pointCloud: pointCloud, origin: origin),
            interval: interval
        )

        await MainActor.run {
            isGenerating = false
            if let result {
                overlay = result
            } else {
                errorMessage = "Could not extract contours — try a smaller interval or rescan."
            }
        }
    }
}
