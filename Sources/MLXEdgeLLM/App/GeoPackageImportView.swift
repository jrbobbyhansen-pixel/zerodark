// GeoPackageImportView.swift — GeoPackage file import UI

import SwiftUI
import UniformTypeIdentifiers

struct GeoPackageImportView: View {
    @ObservedObject private var service = GeoPackageService.shared
    @State private var showFilePicker = false
    @State private var selectedLayer: GPKGLayer?
    @Environment(\.dismiss) private var dismiss: DismissAction

    var onFeaturesImported: (([GPKGFeature]) -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                List {
                    // Import section
                    Section {
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Import GeoPackage File", systemImage: "square.and.arrow.down")
                                .foregroundColor(ZDDesign.cyanAccent)
                        }

                        if service.isImporting {
                            HStack {
                                ProgressView()
                                    .tint(ZDDesign.cyanAccent)
                                Text("Importing...")
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                    } header: {
                        Text("Import")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    // Available files
                    Section {
                        let files = service.listAvailableFiles()
                        if files.isEmpty {
                            Text("No GeoPackage files")
                                .foregroundColor(ZDDesign.mediumGray)
                                .italic()
                        } else {
                            ForEach(files, id: \.absoluteString) { url in
                                Button {
                                    Task {
                                        try? await service.importGeoPackage(from: url)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.fill")
                                            .foregroundColor(ZDDesign.cyanAccent)
                                        Text(url.lastPathComponent)
                                            .foregroundColor(ZDDesign.pureWhite)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Available Files")
                            .foregroundColor(ZDDesign.mediumGray)
                    } footer: {
                        Text("Transfer .gpkg files via USB:\nFinder → iPhone → Files → ZeroDark → GeoPackages/")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .listRowBackground(ZDDesign.darkCard)

                    // Imported layers
                    if !service.importedLayers.isEmpty {
                        Section {
                            ForEach(service.importedLayers) { layer in
                                Button {
                                    selectedLayer = layer
                                } label: {
                                    HStack {
                                        Image(systemName: iconForGeometry(layer.geometryType))
                                            .foregroundColor(.orange)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(layer.name)
                                                .foregroundColor(ZDDesign.pureWhite)
                                            Text("\(layer.featureCount) features • \(layer.geometryType.rawValue)")
                                                .font(.caption)
                                                .foregroundColor(ZDDesign.mediumGray)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(ZDDesign.mediumGray)
                                    }
                                }
                            }
                        } header: {
                            if let fileName = service.currentFileName {
                                Text("Layers in \(fileName)")
                                    .foregroundColor(ZDDesign.mediumGray)
                            } else {
                                Text("Layers")
                                    .foregroundColor(ZDDesign.mediumGray)
                            }
                        }
                        .listRowBackground(ZDDesign.darkCard)
                    }

                    // Error display
                    if let error = service.errorMessage {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                        }
                        .listRowBackground(ZDDesign.darkCard)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("GeoPackage Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(ZDDesign.cyanAccent)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "gpkg") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task {
                        guard url.startAccessingSecurityScopedResource() else { return }
                        defer { url.stopAccessingSecurityScopedResource() }
                        try? await service.importGeoPackage(from: url)
                    }
                }
            }
            .sheet(item: $selectedLayer) { layer in
                GeoPackageLayerDetailView(layer: layer)
            }
        }
    }

    private func iconForGeometry(_ type: GPKGFeature.GeometryType) -> String {
        switch type {
        case .point: return "mappin"
        case .lineString: return "line.diagonal"
        case .polygon: return "hexagon"
        case .multiPoint: return "mappin.and.ellipse"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Layer Detail View

struct GeoPackageLayerDetailView: View {
    let layer: GPKGLayer

    @ObservedObject private var service = GeoPackageService.shared
    @State private var features: [GPKGFeature] = []
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            ZStack {
                ZDDesign.darkBackground.ignoresSafeArea()

                List {
                    Section {
                        LabeledContent("Name", value: layer.name)
                        LabeledContent("Type", value: layer.geometryType.rawValue)
                        LabeledContent("Features", value: "\(layer.featureCount)")
                    }
                    .listRowBackground(ZDDesign.darkCard)
                    .foregroundColor(ZDDesign.pureWhite)

                    Section {
                        ForEach(features) { feature in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.name)
                                    .font(.headline)
                                    .foregroundColor(ZDDesign.pureWhite)
                                if let coord = feature.coordinates.first {
                                    Text(MGRSConverter.toMGRS(coordinate: coord, precision: 4))
                                        .font(.caption)
                                        .foregroundColor(ZDDesign.mediumGray)
                                }
                            }
                        }
                    } header: {
                        Text("Features")
                            .foregroundColor(ZDDesign.mediumGray)
                    }
                    .listRowBackground(ZDDesign.darkCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(layer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ZDDesign.mediumGray)
                }
            }
            .onAppear {
                features = service.getFeatures(from: layer.name)
            }
        }
    }
}

#Preview {
    GeoPackageImportView()
}
