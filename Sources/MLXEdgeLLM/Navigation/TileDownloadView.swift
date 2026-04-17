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
    // Broad tactical regions (offline readiness for grid-down scenarios)
    RegionPreset(name: "Continental_US", center: .init(latitude: 39.5, longitude: -98.35),
                 span: .init(latitudeDelta: 26.0, longitudeDelta: 58.0), recommendedMinZoom: 4, recommendedMaxZoom: 9, icon: "globe.americas.fill"),
    RegionPreset(name: "Western_US", center: .init(latitude: 40.15, longitude: -113.35),
                 span: .init(latitudeDelta: 17.7, longitudeDelta: 22.7), recommendedMinZoom: 5, recommendedMaxZoom: 11, icon: "mountain.2.fill"),
    RegionPreset(name: "Eastern_US", center: .init(latitude: 36.0, longitude: -75.0),
                 span: .init(latitudeDelta: 23.0, longitudeDelta: 16.0), recommendedMinZoom: 5, recommendedMaxZoom: 11, icon: "tree.fill"),
    RegionPreset(name: "Alaska", center: .init(latitude: 61.3, longitude: -154.5),
                 span: .init(latitudeDelta: 20.2, longitudeDelta: 49.2), recommendedMinZoom: 4, recommendedMaxZoom: 10, icon: "snowflake"),
    RegionPreset(name: "Hawaii", center: .init(latitude: 20.55, longitude: -157.5),
                 span: .init(latitudeDelta: 3.3, longitudeDelta: 5.4), recommendedMinZoom: 6, recommendedMaxZoom: 12, icon: "water.waves"),
    RegionPreset(name: "Central_America", center: .init(latitude: 12.85, longitude: -84.7),
                 span: .init(latitudeDelta: 11.3, longitudeDelta: 15.0), recommendedMinZoom: 5, recommendedMaxZoom: 11, icon: "globe.americas.fill"),
    RegionPreset(name: "Europe", center: .init(latitude: 53.5, longitude: 10.5),
                 span: .init(latitudeDelta: 35.2, longitudeDelta: 42.2), recommendedMinZoom: 4, recommendedMaxZoom: 9, icon: "globe.europe.africa.fill"),
    // Metro and corridor presets (operational detail)
    RegionPreset(name: "Los_Angeles_Metro", center: .init(latitude: 34.05, longitude: -118.24),
                 span: .init(latitudeDelta: 1.2, longitudeDelta: 1.5), recommendedMinZoom: 8, recommendedMaxZoom: 14, icon: "building.2.fill"),
    RegionPreset(name: "Dallas_Fort_Worth", center: .init(latitude: 32.77, longitude: -97.01),
                 span: .init(latitudeDelta: 1.0, longitudeDelta: 1.2), recommendedMinZoom: 8, recommendedMaxZoom: 14, icon: "building.2.fill"),
    RegionPreset(name: "Phoenix_Metro", center: .init(latitude: 33.45, longitude: -112.07),
                 span: .init(latitudeDelta: 1.0, longitudeDelta: 1.3), recommendedMinZoom: 8, recommendedMaxZoom: 14, icon: "building.2.fill"),
    RegionPreset(name: "Houston_Metro", center: .init(latitude: 29.76, longitude: -95.37),
                 span: .init(latitudeDelta: 1.0, longitudeDelta: 1.2), recommendedMinZoom: 8, recommendedMaxZoom: 14, icon: "building.2.fill"),
    RegionPreset(name: "I-10_Corridor_TX-AZ", center: .init(latitude: 31.0, longitude: -103.0),
                 span: .init(latitudeDelta: 4.0, longitudeDelta: 12.0), recommendedMinZoom: 6, recommendedMaxZoom: 12, icon: "road.lanes"),
    RegionPreset(name: "Colorado_Mountains", center: .init(latitude: 39.55, longitude: -105.78),
                 span: .init(latitudeDelta: 2.5, longitudeDelta: 3.0), recommendedMinZoom: 7, recommendedMaxZoom: 13, icon: "mountain.2.fill"),
    RegionPreset(name: "Pacific_Northwest", center: .init(latitude: 47.5, longitude: -121.5),
                 span: .init(latitudeDelta: 2.5, longitudeDelta: 3.0), recommendedMinZoom: 7, recommendedMaxZoom: 13, icon: "tree.fill"),
]

struct TileDownloadView: View {
    @ObservedObject private var downloader = TileDownloadManager.shared
    @ObservedObject private var offlineTiles = OfflineTileProvider.shared
    @State private var regionName = ""
    @State private var minZoom: Double = 8
    @State private var maxZoom: Double = 14
    @State private var showPresets = false
    @State private var showRegionDraw = false
    @State private var showImporter = false
    @State private var importError: String?
    @State private var installedMaps: [URL] = []
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

                // Region selector — full width map, no decorative overlay
                ZStack(alignment: .bottomLeading) {
                    Map(coordinateRegion: $mapRegion)
                        .frame(height: 240)
                    // Crosshair
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(ZDDesign.safetyYellow)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    Text("Pan and zoom — entire visible area will be downloaded")
                        .font(.caption2)
                        .foregroundColor(ZDDesign.pureWhite)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(4)
                        .padding(8)
                }

                Form {

                    // MARK: Installed Maps — always first
                    if !installedMaps.isEmpty {
                        Section {
                            // Active map picker
                            Picker("Active", selection: Binding(
                                get: { offlineTiles.currentMap ?? "" },
                                set: { offlineTiles.selectMap($0) }
                            )) {
                                ForEach(installedMaps, id: \.lastPathComponent) { url in
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .tag(url.deletingPathExtension().lastPathComponent)
                                }
                            }
                            .pickerStyle(.menu)

                            ForEach(installedMaps, id: \.lastPathComponent) { url in
                                let name = url.deletingPathExtension().lastPathComponent
                                HStack {
                                    Image(systemName: "map.fill")
                                        .foregroundColor(ZDDesign.cyanAccent)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.subheadline)
                                        Text(fileSize(url))
                                            .font(.caption)
                                            .foregroundColor(ZDDesign.mediumGray)
                                    }
                                    Spacer()
                                    if name == offlineTiles.currentMap {
                                        Text("ACTIVE")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(ZDDesign.cyanAccent)
                                    }
                                }
                            }
                            .onDelete(perform: deleteMap)
                        } header: {
                            Text("Installed Maps")
                        } footer: {
                            Text("Swipe left to delete. The active map is used when there is no cell service.")
                        }
                    }

                    // MARK: Add Map
                    Section("Add Map") {
                        Button {
                            showPresets = true
                        } label: {
                            Label("Load a Region Preset", systemImage: "map.fill")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button {
                            showRegionDraw = true
                        } label: {
                            Label("Draw Custom Area", systemImage: "lasso")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import .mbtiles / .pmtiles from Files", systemImage: "square.and.arrow.down")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }
                    }

                    // MARK: Download New Map
                    Section {
                        TextField("Region name", text: $regionName)
                            .autocorrectionDisabled()
                            .onChange(of: regionName) { _, new in
                                let cleaned = new.replacingOccurrences(of: " ", with: "_")
                                if cleaned != new { regionName = cleaned }
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Min Zoom")
                                Spacer()
                                Text("\(Int(minZoom))  —  overview")
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                            .font(.caption)
                            Slider(value: $minZoom, in: 4...12, step: 1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Zoom")
                                Spacer()
                                Text("\(Int(maxZoom))  —  street detail")
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                            .font(.caption)
                            Slider(value: $maxZoom, in: 12...18, step: 1)
                        }

                        // Compact estimate — one row
                        HStack {
                            Label("\(estimatedTiles.formatted()) tiles", systemImage: "square.grid.2x2")
                                .foregroundColor(estimatedTiles > 50000 ? ZDDesign.signalRed : ZDDesign.mediumGray)
                            Spacer()
                            Text(String(format: "~%.0f MB", estimatedMB))
                                .foregroundColor(estimatedMB > 500 ? ZDDesign.safetyYellow : ZDDesign.mediumGray)
                        }
                        .font(.caption)

                        if estimatedTiles > 50000 {
                            Label("Large download — reduce area or max zoom.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(ZDDesign.safetyYellow)
                        }
                    } header: {
                        Text("Download New Map")
                    }

                    // MARK: Active download progress
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
                                Text("\(job.failedTiles) tiles failed")
                                    .font(.caption)
                                    .foregroundColor(ZDDesign.safetyYellow)
                            }
                            Button("Cancel", role: .destructive) { downloader.cancelDownload() }
                        }
                    }

                    // MARK: Import error
                    if let err = importError {
                        Section {
                            Label(err, systemImage: "xmark.circle.fill")
                                .foregroundColor(ZDDesign.signalRed)
                                .font(.caption)
                        }
                    }

                    // MARK: Download button
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
                                let missing = TerrainEngine.shared.missingTiles(for: mapRegion)
                                for tile in missing {
                                    try? await TerrainEngine.shared.downloadTile(named: tile)
                                }
                                offlineTiles.scanForMaps()
                                loadInstalledMaps()
                            }
                        } label: {
                            Label("Download Map + Terrain", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ZDDesign.forestGreen)
                        .disabled(downloader.isDownloading || regionName.isEmpty)
                    } footer: {
                        Text("Elevation data for LOS analysis and contour lines is downloaded automatically along with map tiles.")
                    }
                }
            }
            .navigationTitle("Offline Maps")
            .preferredColorScheme(.dark)
            .onAppear {
                offlineTiles.scanForMaps()
                loadInstalledMaps()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [
                    .init(importedAs: "com.zerodark.mbtiles"),
                    .init(importedAs: "com.zerodark.pmtiles")
                ],
                allowsMultipleSelection: false
            ) { result in
                importError = nil
                switch result {
                case .success(let urls):
                    guard let src = urls.first else { return }
                    let accessing = src.startAccessingSecurityScopedResource()
                    defer { if accessing { src.stopAccessingSecurityScopedResource() } }
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dest = docs.appendingPathComponent("OfflineMaps", isDirectory: true)
                        .appendingPathComponent(src.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(
                            at: dest.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try FileManager.default.removeItem(at: dest)
                        }
                        try FileManager.default.copyItem(at: src, to: dest)
                        offlineTiles.scanForMaps()
                        loadInstalledMaps()
                    } catch {
                        importError = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    importError = "Could not open file: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $showPresets) {
                RegionPresetsSheet { preset in
                    regionName = preset.name
                    mapRegion = preset.region
                    minZoom = Double(preset.recommendedMinZoom)
                    maxZoom = Double(preset.recommendedMaxZoom)
                    showPresets = false
                }
            }
            .sheet(isPresented: $showRegionDraw) {
                RegionDrawView { drawnRegion, name in
                    mapRegion = drawnRegion
                    if !name.isEmpty { regionName = name }
                    showRegionDraw = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadInstalledMaps() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mapsDir = docs.appendingPathComponent("OfflineMaps", isDirectory: true)
        installedMaps = ((try? FileManager.default.contentsOfDirectory(
            at: mapsDir, includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        )) ?? [])
        .filter { ["mbtiles", "pmtiles"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func deleteMap(at offsets: IndexSet) {
        for i in offsets {
            let url = installedMaps[i]
            let name = url.deletingPathExtension().lastPathComponent
            try? FileManager.default.removeItem(at: url)
            downloader.deleteRegion(named: name)
        }
        offlineTiles.scanForMaps()
        loadInstalledMaps()
    }

    private func fileSize(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: size)
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
                            Text(preset.name.replacingOccurrences(of: "_", with: " "))
                                .font(.headline)
                                .foregroundColor(ZDDesign.pureWhite)
                            Text("Zoom \(preset.recommendedMinZoom)–\(preset.recommendedMaxZoom) · ~\(String(format: "%.0f", TileDownloadJob(regionName: preset.name, bounds: preset.region, minZoom: preset.recommendedMinZoom, maxZoom: preset.recommendedMaxZoom).estimatedStorageMB)) MB")
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
