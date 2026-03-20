// TileDownloadView.swift — Offline Map Tile Download Interface

import SwiftUI
import MapKit

struct TileDownloadView: View {
    @StateObject private var downloader = TileDownloadManager.shared
    @State private var regionName = ""
    @State private var minZoom: Double = 8
    @State private var maxZoom: Double = 16
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )

    var estimatedTiles: Int {
        downloader.estimateTileCount(bounds: mapRegion, minZoom: Int(minZoom), maxZoom: Int(maxZoom))
    }

    var estimatedMB: Double {
        TileDownloadJob(regionName: "", bounds: mapRegion, minZoom: Int(minZoom), maxZoom: Int(maxZoom))
            .estimatedStorageMB
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Map region selector
                Map(coordinateRegion: $mapRegion)
                    .frame(height: 280)
                    .overlay(
                        Rectangle()
                            .strokeBorder(ZDDesign.safetyYellow, lineWidth: 2)
                            .padding(20)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Text("Drag to set download region")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .padding(8)
                    }

                Form {
                    Section("Region") {
                        TextField("Region name (e.g. 'Colorado_Mountains')", text: $regionName)

                        VStack(alignment: .leading) {
                            Text("Min Zoom: \(Int(minZoom)) (overview)")
                            Slider(value: $minZoom, in: 4...12, step: 1)
                        }

                        VStack(alignment: .leading) {
                            Text("Max Zoom: \(Int(maxZoom)) (street detail)")
                            Slider(value: $maxZoom, in: 12...18, step: 1)
                        }
                    }

                    Section("Estimate") {
                        HStack {
                            Text("Tiles")
                            Spacer()
                            Text("\(estimatedTiles.formatted())")
                                .foregroundColor(estimatedTiles > 50000 ? ZDDesign.signalRed : ZDDesign.successGreen)
                        }
                        HStack {
                            Text("Storage")
                            Spacer()
                            Text(String(format: "%.0f MB", estimatedMB))
                                .foregroundColor(estimatedMB > 500 ? ZDDesign.safetyYellow : ZDDesign.successGreen)
                        }
                        if estimatedTiles > 50000 {
                            Text("Warning: Large download. Reduce zoom range or area.")
                                .font(.caption)
                                .foregroundColor(ZDDesign.safetyYellow)
                        }
                    }

                    // Active download progress
                    if let job = downloader.activeJob {
                        Section("Downloading: \(job.regionName)") {
                            ProgressView(value: job.progress)
                                .tint(ZDDesign.forestGreen)
                            HStack {
                                Text("\(job.downloadedTiles) / \(job.totalTiles) tiles")
                                Spacer()
                                Text(String(format: "%.1f%%", job.progress * 100))
                            }
                            .font(.caption)
                            if job.failedTiles > 0 {
                                Text("\(job.failedTiles) failed (will retry)")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.safetyYellow)
                            }
                            Button("Cancel") { downloader.cancelDownload() }
                                .foregroundColor(ZDDesign.signalRed)
                        }
                    }

                    // Downloaded regions
                    if !downloader.jobs.filter({ $0.status == .complete }).isEmpty {
                        Section("Downloaded Regions") {
                            ForEach(downloader.jobs.filter({ $0.status == .complete })) { job in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(job.regionName).font(.headline)
                                        Text("\(job.downloadedTiles) tiles · \(String(format: "%.0f MB", job.estimatedStorageMB))")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(ZDDesign.successGreen)
                                }
                            }
                            .onDelete { indexSet in
                                let completed = downloader.jobs.filter { $0.status == .complete }
                                for i in indexSet {
                                    downloader.deleteRegion(named: completed[i].regionName)
                                }
                            }
                        }
                    }

                    Section {
                        Button("Download This Region") {
                            guard !regionName.isEmpty, !downloader.isDownloading else { return }
                            Task {
                                await downloader.startDownload(
                                    regionName: regionName,
                                    bounds: mapRegion,
                                    minZoom: Int(minZoom),
                                    maxZoom: Int(maxZoom)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .background(
                            downloader.isDownloading || regionName.isEmpty
                            ? Color.gray.opacity(0.4)
                            : ZDDesign.forestGreen
                        )
                        .cornerRadius(10)
                        .disabled(downloader.isDownloading || regionName.isEmpty)
                    }
                }
            }
            .navigationTitle("Offline Maps")
            .preferredColorScheme(.dark)
        }
    }
}
