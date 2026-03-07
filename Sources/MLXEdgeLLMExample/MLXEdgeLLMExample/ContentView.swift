import SwiftUI
import PhotosUI
import MLXEdgeLLM

// MARK: - View
struct ContentView: View {
    @StateObject private var vm = DemoViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedVisionModel: VisionModel = .qwen35_0_8b
    @State private var visionRunMode: VisionRunMode = .standard
    @State private var selectedSpecializedModel: SpecializedVisionModel = .fastVLM_0_5b_fp16
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    
                    // Image picker
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        imagePreview
                    }
                    .onChange(of: pickerItem) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                vm.selectedImage = PlatformImage(data: data)
                            }
                        }
                    }
                    
                    if let img = vm.selectedImage {
                        // Standard VLMs
                        GroupBox("TextModel VLMs") {
                            HStack {
                                VStack(spacing: 16) {
                                    Picker("Model", selection: $selectedVisionModel) {
                                        ForEach(VisionModel.allCases, id: \.self) { model in
                                            Text(model.displayName).tag(model)
                                        }
                                    }
                                    
                                    Picker("Mode", selection: $visionRunMode) {
                                        ForEach(VisionRunMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                Spacer()
                                btn("Run", isDownloaded: selectedVisionModel.isDownloaded, .blue) {
                                    switch visionRunMode {
                                        case .standard:
                                            await vm.runVLM(model: selectedVisionModel, image: img)
                                        case .stream:
                                            await vm.runStreamVLM(model: selectedVisionModel, image: img)
                                    }
                                }
                                .frame(maxWidth: 120)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        // Specialized OCR
                        GroupBox("Specialized OCR") {
                            HStack {
                                Picker("Model", selection: $selectedSpecializedModel) {
                                    ForEach(SpecializedVisionModel.allCases, id: \.self) { model in
                                        Text(model.displayName).tag(model)
                                    }
                                }
                                
                                Spacer()
                                
                                btn("Run OCR", isDownloaded: selectedSpecializedModel.isDownloaded, .orange) {
                                    await vm.runSpecialized(model: selectedSpecializedModel, image: img)
                                }
                                .frame(maxWidth: 120)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Text("FastVLM: JSON · Granite: DocTags→Markdown")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Select a receipt or document image above")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .padding()
                    }
                    
                    // Text chat (no image needed)
                    btn("Use Text Chat(Qwen3 1.7B)", isDownloaded: TextModel.qwen3_1_7b.isDownloaded, .green) { await vm.runTextChat() }
                    
                    // Progress
                    if !vm.progress.isEmpty {
                        Text(vm.progress).font(.caption).foregroundStyle(.secondary)
                    }
                    
                    // Output
                    if !vm.output.isEmpty {
                        ScrollView {
                            Text(vm.output)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: .infinity)
                        .background(Color.outputBackground)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("MLXEdgeLLM")
            .overlay(loadingOverlay)
        }
    }
    
    @ViewBuilder
    private var imagePreview: some View {
        if let img = vm.selectedImage {
            Image(platformImage: img)
                .resizable().scaledToFit()
                .frame(maxHeight: 200)
                .cornerRadius(10)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 120)
                .overlay {
                    Label("Tap to select image", systemImage: "photo.badge.plus")
                        .foregroundStyle(.secondary)
                }
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if vm.isLoading {
            ProgressView()
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func btn(_ title: String, isDownloaded: Bool, _ color: Color, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            VStack(alignment: .center, spacing: 4) {
                HStack {
                    if isDownloaded {
                        Image(systemName: "square.and.arrow.down.badge.checkmark.fill")
                        Text("Ready")
                            .font(.subheadline.weight(.medium))
                    } else {
                        Image(systemName: "arrow.down.square")
                        Text("Download")
                            .font(.subheadline.weight(.medium))
                    }
                }
                
                Text(title)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }
    
    private enum VisionRunMode: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case stream = "Stream"
        
        var id: String { rawValue }
    }
}

#Preview { ContentView() }
