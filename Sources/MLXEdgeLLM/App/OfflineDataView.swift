// OfflineDataView.swift — Offline Data Management (Download + USB Transfer)

import SwiftUI
import MapKit
import CoreLocation

struct OfflineDataView: View {
    @ObservedObject private var downloadManager = OfflineDownloadManager.shared
    @State private var mapPacks: [URL] = []
    @State private var terrainTiles: [URL] = []
    @State private var totalStorage: String = "Calculating..."
    @State private var availableStorage: String = "Calculating..."
    @State private var showStateSelector = false
    
    var body: some View {
        List {
            // Storage Overview
            Section {
                HStack {
                    Label("Offline Data", systemImage: "internaldrive.fill")
                    Spacer()
                    Text(totalStorage)
                        .foregroundColor(ZDDesign.mediumGray)
                }
                HStack {
                    Label("Available", systemImage: "externaldrive.fill")
                    Spacer()
                    Text(availableStorage)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            } header: {
                Text("Storage")
            }
            
            // Download Actions
            Section {
                // Download current location
                Button {
                    Task { await downloadManager.downloadCurrentLocation() }
                } label: {
                    HStack {
                        Label("Download Current Area", systemImage: "location.fill")
                        Spacer()
                        if downloadManager.isDownloading && downloadManager.currentDownloadName == "Current Location" {
                            ProgressView()
                        }
                    }
                }
                .disabled(downloadManager.isDownloading)
                
                // Download by state
                Button {
                    showStateSelector = true
                } label: {
                    Label("Download by State", systemImage: "map.fill")
                }
                .disabled(downloadManager.isDownloading)
                
                // iOS offline maps
                Button {
                    openOfflineMapsSettings()
                } label: {
                    HStack {
                        Label("iOS Offline Maps", systemImage: "apple.logo")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                }
            } header: {
                Text("Download Terrain Data")
            } footer: {
                Text("Elevation data enables contour lines and slope analysis. For base map tiles, use iOS Settings > Maps > Offline Maps.")
            }
            
            // Download Progress
            if downloadManager.isDownloading {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(downloadManager.currentDownloadName)
                                .font(.headline)
                            Spacer()
                            Text("\(Int(downloadManager.downloadProgress * 100))%")
                                .foregroundColor(ZDDesign.mediumGray)
                        }
                        ProgressView(value: downloadManager.downloadProgress)
                            .tint(ZDDesign.cyanAccent)
                        Text("Tile \(downloadManager.currentTileIndex + 1) of \(downloadManager.totalTiles)")
                            .font(.caption)
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                } header: {
                    Text("Downloading")
                }
            }

            // Downloaded Terrain (from SRTM)
            Section {
                if terrainTiles.isEmpty {
                    HStack {
                        Image(systemName: "mountain.2")
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("No terrain data")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                } else {
                    ForEach(terrainTiles, id: \.lastPathComponent) { tile in
                        TerrainTileRow(url: tile, onDelete: {
                            deleteTile(tile)
                        })
                    }
                }
            } header: {
                Text("Terrain Tiles (\(terrainTiles.count))")
            }

            // Map Packs (USB transferred)
            Section {
                if mapPacks.isEmpty {
                    HStack {
                        Image(systemName: "map")
                            .foregroundColor(ZDDesign.mediumGray)
                        Text("No map packs")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                } else {
                    ForEach(mapPacks, id: \.lastPathComponent) { pack in
                        MapPackRow(url: pack)
                    }
                }
            } header: {
                Text("Map Packs (\(mapPacks.count))")
            } footer: {
                Text("Transfer .mbtiles via USB: Finder → iPhone → Files → ZeroDark")
            }
        }
        .navigationTitle("Offline Data")
        .refreshable {
            loadData()
        }
        .onAppear {
            loadData()
        }
        .sheet(isPresented: $showStateSelector) {
            StateSelectorView(downloadManager: downloadManager, onDismiss: {
                showStateSelector = false
                loadData()
            })
        }
    }
    
    private func openOfflineMapsSettings() {
        if let url = URL(string: "App-prefs:MAPS") {
            UIApplication.shared.open(url)
        }
    }
    
    private func deleteTile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        loadData()
    }
    
    private func loadData() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let containerRoot = docs.deletingLastPathComponent()
        let fm = FileManager.default

        // Map packs
        let mapDirs: [URL] = [
            docs.appendingPathComponent("OfflineMaps"),
            docs.appendingPathComponent("Maps"),
            containerRoot.appendingPathComponent("OfflineMaps"),
            containerRoot.appendingPathComponent("Maps")
        ]
        var seenMapNames = Set<String>()
        mapPacks = mapDirs.flatMap { dir -> [URL] in
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        }.filter { $0.pathExtension == "mbtiles" }
        .filter { seenMapNames.insert($0.lastPathComponent).inserted }

        // Terrain tiles
        let terrainDirs: [URL] = [
            docs.appendingPathComponent("Terrain"),
            docs.appendingPathComponent("SRTM"),
            containerRoot.appendingPathComponent("Terrain"),
            containerRoot.appendingPathComponent("SRTM")
        ]
        var seenTerrainNames = Set<String>()
        terrainTiles = terrainDirs.flatMap { dir -> [URL] in
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        }.filter { ["hgt", "tiff"].contains($0.pathExtension.lowercased()) }
        .filter { seenTerrainNames.insert($0.lastPathComponent).inserted }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Storage calculation
        let mapSize = mapPacks.reduce(Int64(0)) { total, url in
            total + ((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        }
        let terrainSize = terrainTiles.reduce(Int64(0)) { total, url in
            total + ((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        totalStorage = formatter.string(fromByteCount: mapSize + terrainSize)

        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? Int64 {
            availableStorage = formatter.string(fromByteCount: freeSpace)
        }
    }
}

// MARK: - State Selector

struct StateSelectorView: View {
    @ObservedObject var downloadManager: OfflineDownloadManager
    let onDismiss: () -> Void
    @State private var searchText = ""
    
    var filteredStates: [USState] {
        if searchText.isEmpty {
            return USState.allCases
        }
        return USState.allCases.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredStates) { state in
                    StateDownloadRow(state: state, downloadManager: downloadManager)
                }
            }
            .searchable(text: $searchText, prompt: "Search states")
            .navigationTitle("Select State")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}

struct StateDownloadRow: View {
    let state: USState
    @ObservedObject var downloadManager: OfflineDownloadManager
    
    var downloadedCount: Int {
        state.tiles.filter { downloadManager.downloadedTiles.contains($0) }.count
    }
    
    var isFullyDownloaded: Bool {
        !state.tiles.isEmpty && downloadedCount == state.tiles.count
    }
    
    var isPartiallyDownloaded: Bool {
        downloadedCount > 0 && downloadedCount < state.tiles.count
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.name)
                    .font(.body)
                if state.tiles.isEmpty {
                    Text("Not mapped yet")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("\(downloadedCount)/\(state.tiles.count) tiles • ~\(state.estimatedSize)")
                        .font(.caption)
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
            
            Spacer()
            
            if state.tiles.isEmpty {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.orange)
            } else if isFullyDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ZDDesign.successGreen)
            } else if downloadManager.isDownloading && downloadManager.currentDownloadState == state {
                VStack {
                    ProgressView()
                    Text("\(Int(downloadManager.downloadProgress * 100))%")
                        .font(.caption2)
                }
            } else {
                Button {
                    Task { await downloadManager.downloadState(state) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        if isPartiallyDownloaded {
                            Text("Resume")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(ZDDesign.cyanAccent)
                }
                .disabled(downloadManager.isDownloading)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Terrain Tile Row

struct TerrainTileRow: View {
    let url: URL
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "mountain.2.fill")
                .foregroundColor(.brown)
            VStack(alignment: .leading) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(.body, design: .monospaced))
                Text(fileSize)
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
    }
    
    private var fileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Map Pack Row

struct MapPackRow: View {
    let url: URL
    
    var body: some View {
        HStack {
            Image(systemName: "map.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.body)
                Text(fileSize)
                    .font(.caption)
                    .foregroundColor(ZDDesign.mediumGray)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
    
    private var fileSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - US States with SRTM Coverage

enum USState: String, CaseIterable, Identifiable {
    case alabama, alaska, arizona, arkansas, california
    case colorado, connecticut, delaware, florida, georgia
    case hawaii, idaho, illinois, indiana, iowa
    case kansas, kentucky, louisiana, maine, maryland
    case massachusetts, michigan, minnesota, mississippi, missouri
    case montana, nebraska, nevada, newHampshire, newJersey
    case newMexico, newYork, northCarolina, northDakota, ohio
    case oklahoma, oregon, pennsylvania, rhodeIsland, southCarolina
    case southDakota, tennessee, texas, utah, vermont
    case virginia, washington, westVirginia, wisconsin, wyoming
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .newHampshire: return "New Hampshire"
        case .newJersey: return "New Jersey"
        case .newMexico: return "New Mexico"
        case .newYork: return "New York"
        case .northCarolina: return "North Carolina"
        case .northDakota: return "North Dakota"
        case .southCarolina: return "South Carolina"
        case .southDakota: return "South Dakota"
        case .westVirginia: return "West Virginia"
        case .rhodeIsland: return "Rhode Island"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
    
    var tiles: [String] {
        switch self {
        case .texas:
            return ["N26W098", "N26W099", "N26W100", "N27W098", "N27W099", "N27W100",
                    "N28W097", "N28W098", "N28W099", "N28W100", "N28W101",
                    "N29W095", "N29W096", "N29W097", "N29W098", "N29W099", "N29W100", "N29W101", "N29W102", "N29W103", "N29W104", "N29W105",
                    "N30W094", "N30W095", "N30W096", "N30W097", "N30W098", "N30W099", "N30W100", "N30W101", "N30W102", "N30W103", "N30W104", "N30W105",
                    "N31W094", "N31W095", "N31W096", "N31W097", "N31W098", "N31W099", "N31W100", "N31W101", "N31W102", "N31W103", "N31W104", "N31W105", "N31W106",
                    "N32W094", "N32W095", "N32W096", "N32W097", "N32W098", "N32W099", "N32W100", "N32W101", "N32W102", "N32W103", "N32W104", "N32W105", "N32W106",
                    "N33W095", "N33W096", "N33W097", "N33W098", "N33W099", "N33W100", "N33W101", "N33W102", "N33W103",
                    "N34W100", "N34W101", "N34W102", "N34W103",
                    "N35W100", "N35W101", "N35W102", "N35W103",
                    "N36W100", "N36W101", "N36W102", "N36W103"]
        case .colorado:
            return ["N37W103", "N37W104", "N37W105", "N37W106", "N37W107", "N37W108", "N37W109",
                    "N38W103", "N38W104", "N38W105", "N38W106", "N38W107", "N38W108", "N38W109",
                    "N39W103", "N39W104", "N39W105", "N39W106", "N39W107", "N39W108", "N39W109",
                    "N40W103", "N40W104", "N40W105", "N40W106", "N40W107", "N40W108", "N40W109",
                    "N41W103", "N41W104", "N41W105", "N41W106", "N41W107", "N41W108", "N41W109"]
        case .newMexico:
            return ["N31W104", "N31W105", "N31W106", "N31W107", "N31W108", "N31W109",
                    "N32W104", "N32W105", "N32W106", "N32W107", "N32W108", "N32W109",
                    "N33W104", "N33W105", "N33W106", "N33W107", "N33W108", "N33W109",
                    "N34W104", "N34W105", "N34W106", "N34W107", "N34W108", "N34W109",
                    "N35W104", "N35W105", "N35W106", "N35W107", "N35W108", "N35W109",
                    "N36W104", "N36W105", "N36W106", "N36W107", "N36W108", "N36W109"]
        case .oklahoma:
            return ["N33W095", "N33W096", "N33W097", "N33W098", "N33W099", "N33W100", "N33W101", "N33W102", "N33W103",
                    "N34W095", "N34W096", "N34W097", "N34W098", "N34W099", "N34W100",
                    "N35W095", "N35W096", "N35W097", "N35W098", "N35W099", "N35W100",
                    "N36W095", "N36W096", "N36W097", "N36W098", "N36W099", "N36W100"]
        case .louisiana:
            return ["N29W090", "N29W091", "N29W092", "N29W093", "N29W094",
                    "N30W090", "N30W091", "N30W092", "N30W093", "N30W094",
                    "N31W090", "N31W091", "N31W092", "N31W093", "N31W094",
                    "N32W090", "N32W091", "N32W092", "N32W093", "N32W094"]
        case .arkansas:
            return ["N33W090", "N33W091", "N33W092", "N33W093", "N33W094", "N33W095",
                    "N34W090", "N34W091", "N34W092", "N34W093", "N34W094", "N34W095",
                    "N35W090", "N35W091", "N35W092", "N35W093", "N35W094", "N35W095",
                    "N36W090", "N36W091", "N36W092", "N36W093", "N36W094", "N36W095"]
        default:
            return [] // Will add more states as needed
        }
    }
    
    var tileCount: Int { tiles.count }
    
    var estimatedSize: String {
        let mb = tiles.count * 3
        if mb >= 100 { return "\(mb) MB" }
        if mb > 0 { return "~\(mb) MB" }
        return "N/A"
    }
}

// MARK: - Download Manager

@MainActor
final class OfflineDownloadManager: ObservableObject {
    static let shared = OfflineDownloadManager()
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var currentDownloadName = ""
    @Published var currentDownloadState: USState?
    @Published var currentTileIndex = 0
    @Published var totalTiles = 0
    @Published var downloadedTiles: [String] = []
    
    private let engine = TerrainEngine.shared
    
    init() {
        refreshDownloadedTiles()
    }
    
    func refreshDownloadedTiles() {
        downloadedTiles = engine.availableTiles()
    }
    
    func downloadCurrentLocation() async {
        guard let location = CLLocationManager().location else { return }
        
        isDownloading = true
        currentDownloadName = "Current Location"
        currentTileIndex = 0
        totalTiles = 1
        downloadProgress = 0
        
        do {
            try await engine.downloadTile(for: location.coordinate)
            downloadProgress = 1.0
        } catch {
        }
        
        refreshDownloadedTiles()
        isDownloading = false
    }
    
    func downloadState(_ state: USState) async {
        guard !state.tiles.isEmpty else { return }
        
        isDownloading = true
        currentDownloadState = state
        currentDownloadName = state.name
        downloadProgress = 0
        
        let tilesToDownload = state.tiles.filter { !downloadedTiles.contains($0) }
        totalTiles = tilesToDownload.count
        
        for (index, tile) in tilesToDownload.enumerated() {
            currentTileIndex = index
            do {
                try await engine.downloadTile(named: tile)
                downloadProgress = Double(index + 1) / Double(totalTiles)
                refreshDownloadedTiles()
            } catch {
            }
        }
        
        currentDownloadState = nil
        isDownloading = false
    }
}

#Preview {
    NavigationStack {
        OfflineDataView()
    }
}
