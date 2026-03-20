// OfflineDataView.swift — Manage USB-transferred offline data
// Shows installed maps, terrain, models and available storage

import SwiftUI

struct OfflineDataView: View {
    @State private var mapPacks: [URL] = []
    @State private var terrainTiles: [URL] = []
    @State private var totalStorage: String = "Calculating..."
    @State private var availableStorage: String = "Calculating..."
    
    var body: some View {
        List {
            // Storage Overview
            Section {
                HStack {
                    Label("Used", systemImage: "internaldrive.fill")
                    Spacer()
                    Text(totalStorage)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Label("Available", systemImage: "externaldrive.fill")
                    Spacer()
                    Text(availableStorage)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("DEVICE STORAGE")
            }

            // Map Packs
            Section {
                if mapPacks.isEmpty {
                    HStack {
                        Image(systemName: "map")
                            .foregroundColor(.secondary)
                        Text("No map packs installed")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(mapPacks, id: \.lastPathComponent) { pack in
                        MapPackRow(url: pack)
                    }
                }
            } header: {
                Text("OFFLINE MAPS (\(mapPacks.count))")
            } footer: {
                Text("Transfer .mbtiles files via USB:\nFinder → iPhone → Files → ZeroDark → Maps/")
            }
            
            // Terrain Data
            Section {
                if terrainTiles.isEmpty {
                    HStack {
                        Image(systemName: "mountain.2")
                            .foregroundColor(.secondary)
                        Text("No terrain data installed")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(terrainTiles, id: \.lastPathComponent) { tile in
                        TerrainTileRow(url: tile)
                    }
                }
            } header: {
                Text("TERRAIN DATA (\(terrainTiles.count))")
            } footer: {
                Text("Transfer .hgt or .tiff files via USB:\nFinder → iPhone → Files → ZeroDark → Terrain/")
            }
            
            // USB Transfer Instructions
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    InstructionRow(step: 1, text: "Connect iPhone to Mac via USB")
                    InstructionRow(step: 2, text: "Open Finder, select iPhone in sidebar")
                    InstructionRow(step: 3, text: "Click 'Files' tab")
                    InstructionRow(step: 4, text: "Expand ZeroDark, drag files into Maps/ or Terrain/")
                    InstructionRow(step: 5, text: "Wait for transfer to complete")
                    InstructionRow(step: 6, text: "Pull down here to refresh")
                }
                .padding(.vertical, 8)
            } header: {
                Text("HOW TO ADD DATA")
            }
        }
        .navigationTitle("Offline Data")
        .refreshable {
            loadData()
        }
        .onAppear {
            loadData()
        }
    }
    
    private func loadData() {
        // Load map packs from offline maps directory
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let mapsDir = paths[0].appendingPathComponent("OfflineMaps", isDirectory: true)
        let terrainDir = paths[0].appendingPathComponent("Terrain", isDirectory: true)

        // Get map files
        mapPacks = (try? fileManager.contentsOfDirectory(at: mapsDir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "mbtiles" }) ?? []

        // Get terrain files
        terrainTiles = (try? fileManager.contentsOfDirectory(at: terrainDir, includingPropertiesForKeys: nil).filter { ["hgt", "tiff"].contains($0.pathExtension.lowercased()) }) ?? []

        // Calculate storage
        let mapSize = mapPacks.reduce(Int64(0)) { total, url in
            total + ((try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        }
        let terrainSize = terrainTiles.reduce(Int64(0)) { total, url in
            total + ((try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        }

        let totalBytes = mapSize + terrainSize
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        totalStorage = formatter.string(fromByteCount: totalBytes)
        
        // Available storage
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? Int64 {
            availableStorage = formatter.string(fromByteCount: freeSpace)
        }
    }
}

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
                    .foregroundColor(.secondary)
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

struct TerrainTileRow: View {
    let url: URL
    
    var body: some View {
        HStack {
            Image(systemName: "mountain.2.fill")
                .foregroundColor(.brown)
            VStack(alignment: .leading) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.body)
                Text(fileSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
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

struct InstructionRow: View {
    let step: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    NavigationStack {
        OfflineDataView()
    }
}
