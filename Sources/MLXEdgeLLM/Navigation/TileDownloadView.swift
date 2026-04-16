// TileDownloadView.swift — Offline Map Tile Download Interface

import SwiftUI
import MapKit

// MARK: - Region Preset

private struct RegionPreset: Identifiable {
    let id = UUID()
    let name: String
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
    let recommendedMinZoom: Int
    let recommendedMaxZoom: Int
    let icon: String

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: span)
    }
}

private let regionPresets: [RegionPreset] = [
    RegionPreset(name: "Los Angeles Metro", center: .init(latitude: 34.05, longitude: -118.24),
                 span: .init(latitudeDelta: 1.2, longitudeDelta: 1.5), recommendedMinZoom: 8, recommendedMaxZoom: 15, icon: "building.2.fill"),
    RegionPreset(name: "Dallas/Fort Worth", center: .init(latitude: 32.77, longitude: -97.01),
                 span: .init(latitudeDelta: 1.0, longitudeDelta: 1.2), recommendedMinZoom: 8, recommendedMaxZoom: 15, icon: "building.2.fill"),
    RegionPreset(name: "Phoenix Metro", center: .init(latitude: 33.45, longitude: -112.07),
                 span: .init(latitudeDelta: 1.0, longitudeDelta: 1.3), recommendedMinZoom: 8, recommendedMaxZoom: 15, icon: "building.2.fill"),
    RegionPreset(name: "Houston Metro", center: .init(latitude: 29.76, longitude: -95.37),
                 span: .init(latitudeDelta: 1.0, longitudeDelta: 1.2), recommendedMinZoom: 8, recommendedMaxZoom: 15, icon: "building.2.fill"),
    RegionPreset(name: "Chicago Metro", center: .init(latitude: 41.88, longitude: -87.63),
                 span: .init(latitudeDelta: 0.8, longitudeDelta: 1.0), recommendedMinZoom: 8, recommendedMaxZoom: 15, icon: "building.2.fill"),
    RegionPreset(name: "I-10 Corridor (TX–AZ)", center: .init(latitude: 31.0, longitude: -103.0),
                 span: .init(latitudeDelta: 4.0, longitudeDelta: 12.0), recommendedMinZoom: 6, recommendedMaxZoom: 12, icon: "road.lanes"),
    RegionPreset(name: "I-35 Corridor (TX)", center: .init(latitude: 30.5, longitude: -97.8),
                 span: .init(latitudeDelta: 3.5, longitudeDelta: 1.0), recommendedMinZoom: 7, recommendedMaxZoom: 13, icon: "road.lanes"),
    RegionPreset(name: "Colorado Mountains", center: .init(latitude: 39.55, longitude: -105.78),
                 span: .init(latitudeDelta: 2.5, longitudeDelta: 3.0), recommendedMinZoom: 7, recommendedMaxZoom: 14, icon: "mountain.2.fill"),
    RegionPreset(name: "Appalachian (VA–NC)", center: .init(latitude: 36.5, longitude: -81.5),
                 span: .init(latitudeDelta: 3.0, longitudeDelta: 3.5), recommendedMinZoom: 7, recommendedMaxZoom: 14, icon: "mountain.2.fill"),
    RegionPreset(name: "Pacific Northwest", center: .init(latitude: 47.5, longitude: -121.5),
                 span: .init(latitudeDelta: 2.5, longitudeDelta: 3.0), recommendedMinZoom: 7, recommendedMaxZoom: 14, icon: "tree.fill"),
    RegionPreset(name: "Gulf Coast (TX)", center: .init(latitude: 28.0, longitude: -97.0),
                 span: .init(latitudeDelta: 2.0, longitudeDelta: 3.0), recommendedMinZoom: 7, recommendedMaxZoom: 14, icon: "water.waves"),
    RegionPreset(name: "US Overview", center: .init(latitude: 39.5, longitude: -98.35),
                 span: .init(latitudeDelta: 22.0, longitudeDelta: 35.0), recommendedMinZoom: 4, recommendedMaxZoom: 9, icon: "globe.americas.fill"),
]

struct TileDownloadView: View {
    @ObservedObject private var downloader = TileDownloadManager.shared
    @State private var regionName = ""
    @State private var minZoom: Double = 8
    @State private var maxZoom: Double = 16
    @State private var showPresets = false
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
                            .foregroundColor(ZDDesign.pureWhite)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                            .padding(8)
                    }

                Form {
                    Section("Quick Presets") {
                        Button {
                            showPresets = true
                        } label: {
                            Label("Load a Region Preset", systemImage: "map.fill")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }

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
                                            .font(.caption).foregroundColor(ZDDesign.mediumGray)
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

                    Section("Terrain Data") {
                        let missingTerrain = TerrainEngine.shared.missingTiles(for: mapRegion)
                        if missingTerrain.isEmpty {
                            Label("Terrain data available for this region", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundColor(ZDDesign.successGreen)
                        } else {
                            Label("\(missingTerrain.count) terrain tile\(missingTerrain.count == 1 ? "" : "s") needed for elevation/LOS", systemImage: "mountain.2.fill")
                                .font(.caption).foregroundColor(ZDDesign.safetyYellow)
                            Button {
                                Task {
                                    for tile in missingTerrain {
                                        try? await TerrainEngine.shared.downloadTile(named: tile)
                                    }
                                }
                            } label: {
                                Label("Download Terrain (\(missingTerrain.count) tiles)", systemImage: "arrow.down.circle.fill")
                                    .font(.caption)
                            }
                            .tint(ZDDesign.forestGreen)
                        }
                    }

                    Section {
                        Button {
                            guard !regionName.isEmpty, !downloader.isDownloading else { return }
                            Task {
                                await downloader.startDownload(
                                    regionName: regionName,
                                    bounds: mapRegion,
                                    minZoom: Int(minZoom),
                                    maxZoom: Int(maxZoom)
                                )
                                // Auto-download terrain tiles for same region
                                let missing = TerrainEngine.shared.missingTiles(for: mapRegion)
                                for tile in missing {
                                    try? await TerrainEngine.shared.downloadTile(named: tile)
                                }
                            }
                        } label: {
                            Label("Download Map + Terrain", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ZDDesign.forestGreen)
                        .disabled(downloader.isDownloading || regionName.isEmpty)
                    }
                }
            }
            .navigationTitle("Offline Maps")
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showPresets) {
                RegionPresetsSheet { preset in
                    regionName = preset.name.replacingOccurrences(of: " ", with: "_")
                    mapRegion = preset.region
                    minZoom = Double(preset.recommendedMinZoom)
                    maxZoom = Double(preset.recommendedMaxZoom)
                    showPresets = false
                }
            }
        }
    }
}

// MARK: - Region Presets Sheet

private struct RegionPresetsSheet: View {
    let onSelect: (RegionPreset) -> Void
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            List(regionPresets) { preset in
                Button {
                    onSelect(preset)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: preset.icon)
                            .foregroundColor(ZDDesign.cyanAccent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.headline)
                                .foregroundColor(ZDDesign.pureWhite)
                            Text("Zoom \(preset.recommendedMinZoom)–\(preset.recommendedMaxZoom)")
                                .font(.caption)
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                    }
                }
            }
            .navigationTitle("Region Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
