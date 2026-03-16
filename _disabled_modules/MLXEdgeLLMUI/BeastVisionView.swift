import SwiftUI
import MLXEdgeLLM
import PhotosUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Beast Vision View

/// Multi-image vision view with all Beast Mode capabilities
public struct BeastVisionView: View {
    @StateObject private var viewModel = BeastVisionViewModel()
    @State private var inputText = ""
    @State private var showModelPicker = false
    @State private var showParamControls = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @FocusState private var inputFocused: Bool
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Memory warning
                MemoryWarningBanner()
                    .padding(.horizontal)
                
                // Main content
                ScrollView {
                    VStack(spacing: 16) {
                        // Image grid
                        ImageGrid(
                            images: viewModel.selectedImages,
                            onRemove: { index in
                                viewModel.selectedImages.remove(at: index)
                            }
                        )
                        
                        // Add images buttons
                        HStack(spacing: 12) {
                            Button {
                                showImagePicker = true
                            } label: {
                                Label("Photos", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.bordered)
                            
                            #if os(iOS)
                            Button {
                                showCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera")
                            }
                            .buttonStyle(.bordered)
                            #endif
                            
                            Button {
                                pasteFromClipboard()
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        // Response area
                        if !viewModel.output.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Response")
                                        .font(.headline)
                                    Spacer()
                                    
                                    Button {
                                        #if os(iOS)
                                        UIPasteboard.general.string = viewModel.output
                                        #else
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(viewModel.output, forType: .string)
                                        #endif
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                }
                                
                                // Thinking (for reasoning models)
                                if let thinking = viewModel.thinkingText, !thinking.isEmpty {
                                    ThinkingView(thinking: thinking)
                                }
                                
                                Text(viewModel.output)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.beastGray6)
                                    .cornerRadius(12)
                                
                                // Stats
                                if let stats = viewModel.lastStats {
                                    Text(stats.summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Loading
                        if !viewModel.progress.isEmpty {
                            HStack {
                                ProgressView()
                                Text(viewModel.progress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                
                // Performance overlay
                if viewModel.isLoading || viewModel.lastStats != nil {
                    PerformanceOverlay(
                        stats: viewModel.lastStats,
                        isGenerating: viewModel.isLoading
                    )
                    .padding(.bottom, 8)
                }
                
                // Input area
                VisionInputBar(
                    text: $inputText,
                    isLoading: viewModel.isLoading,
                    canSend: !viewModel.selectedImages.isEmpty,
                    isFocused: $inputFocused,
                    onSend: sendQuery,
                    onStop: viewModel.stopGeneration
                )
            }
            .navigationTitle("Vision")
            .beastNavBarInline()
            .toolbar { visionToolbarContent }
            .sheet(isPresented: $showModelPicker) {
                VisionModelPicker(selectedModel: $viewModel.selectedModel)
            }
            .sheet(isPresented: $showParamControls) {
                ParameterControlsSheet(params: $viewModel.params)
            }
            .sheet(isPresented: $showImagePicker) {
                MultiImagePicker(images: $viewModel.selectedImages, maxImages: 4)
            }
            #if os(iOS)
            .sheet(isPresented: $showCamera) {
                CameraView { image in
                    if viewModel.selectedImages.count < 4 {
                        viewModel.selectedImages.append(image)
                    }
                }
            }
            #endif
        }
    }
    
    private var shortModelName: String {
        viewModel.selectedModel.displayName
            .replacingOccurrences(of: "⚡👁️ ", with: "")
            .components(separatedBy: " ").first ?? "Vision"
    }
    
    @ToolbarContentBuilder
    private var visionToolbarContent: some ToolbarContent {
        #if os(iOS) || os(visionOS)
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button { showModelPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text(shortModelName).font(.caption)
                    }
                }
                Button { showParamControls = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                Button { showModelPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text(shortModelName).font(.caption)
                    }
                }
                Button { showParamControls = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        #endif
    }
    
    private func sendQuery() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = text.isEmpty ? "Describe what you see in detail." : text
        inputFocused = false
        Task {
            await viewModel.run(prompt: prompt)
        }
    }
    
    private func pasteFromClipboard() {
        #if os(iOS)
        if let image = UIPasteboard.general.image {
            if viewModel.selectedImages.count < 4 {
                viewModel.selectedImages.append(image)
            }
        }
        #else
        if let data = NSPasteboard.general.data(forType: .tiff),
           let image = NSImage(data: data) {
            if viewModel.selectedImages.count < 4 {
                viewModel.selectedImages.append(image)
            }
        }
        #endif
    }
}

// MARK: - Image Grid

struct ImageGrid: View {
    let images: [PlatformImage]
    let onRemove: (Int) -> Void
    
    var body: some View {
        if images.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Add up to 4 images")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(Color.beastGray6)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(.secondary.opacity(0.5))
            )
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    ImageThumbnail(image: image, onRemove: { onRemove(index) })
                }
            }
        }
    }
}

struct ImageThumbnail: View {
    let image: PlatformImage
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            #if os(iOS)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 150)
                .clipped()
                .cornerRadius(12)
            #else
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 150)
                .clipped()
                .cornerRadius(12)
            #endif
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(6)
        }
    }
}

// MARK: - Vision Input Bar

struct VisionInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let canSend: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask about the image(s)...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.beastGray6)
                .cornerRadius(20)
                .lineLimit(1...4)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit {
                    if canSend { onSend() }
                }
            
            if isLoading {
                StopGenerationButton(action: onStop)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? .cyan : .gray)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Vision Model Picker

struct VisionModelPicker: View {
    @Binding var selectedModel: Model
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var monitor = SystemMonitor.shared
    
    var body: some View {
        NavigationStack {
            List {
                // General vision models
                Section {
                    ForEach(Model.visionModels, id: \.rawValue) { model in
                        ModelRow(
                            model: model,
                            isSelected: selectedModel == model,
                            canLoad: model.approximateSizeMB < monitor.memoryAvailableMB
                        ) {
                            selectedModel = model
                            dismiss()
                        }
                    }
                } header: {
                    Label("Vision Models", systemImage: "eye")
                }
                
                // Specialized models
                Section {
                    ForEach(Model.specializedModels, id: \.rawValue) { model in
                        ModelRow(
                            model: model,
                            isSelected: selectedModel == model,
                            canLoad: model.approximateSizeMB < monitor.memoryAvailableMB
                        ) {
                            selectedModel = model
                            dismiss()
                        }
                    }
                } header: {
                    Label("OCR / Document", systemImage: "doc.text.viewfinder")
                }
            }
            .navigationTitle("Vision Models")
            .beastNavBarInline()
            .beastToolbarCancel(dismiss)
        }
    }
}

// MARK: - Multi-Image Picker

#if os(iOS)
struct MultiImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let maxImages: Int
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = maxImages - images.count
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePicker
        
        init(_ parent: MultiImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            for result in results {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            if self?.parent.images.count ?? 0 < self?.parent.maxImages ?? 4 {
                                self?.parent.images.append(image)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            parent.dismiss()
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#else
// macOS stub
struct MultiImagePicker: View {
    @Binding var images: [NSImage]
    let maxImages: Int
    
    var body: some View {
        Text("Image picker not implemented for macOS")
    }
}
#endif

// MARK: - Beast Vision ViewModel

@MainActor
final class BeastVisionViewModel: ObservableObject {
    @Published var selectedImages: [PlatformImage] = []
    @Published var output = ""
    @Published var thinkingText: String?
    @Published var progress = ""
    @Published var isLoading = false
    @Published var lastStats: GenerationStats?
    
    @Published var selectedModel: Model = .qwen3_vl_8b
    @Published var params: BeastModeParams = .balanced
    
    private var engine: BeastEngine?
    
    func run(prompt: String) async {
        guard !selectedImages.isEmpty else { return }
        
        isLoading = true
        output = ""
        thinkingText = nil
        
        do {
            // Load engine if needed
            if engine == nil || engine?.model != selectedModel {
                progress = "Loading \(selectedModel.displayName)..."
                engine = BeastEngine(model: selectedModel, params: params)
                try await engine?.load(onProgress: { [weak self] p in
                    self?.progress = p
                })
            }
            
            engine?.setParams(params)
            progress = ""
            
            _ = try await engine?.generateVision(
                prompt: prompt,
                images: selectedImages,
                onToken: { [weak self] partial in
                    let (thinking, answer) = ThinkingParser.parse(partial)
                    self?.thinkingText = thinking
                    self?.output = answer
                },
                onStats: { [weak self] stats in
                    self?.lastStats = stats
                }
            )
            
        } catch {
            output = "❌ \(error.localizedDescription)"
        }
        
        isLoading = false
        progress = ""
    }
    
    func stopGeneration() {
        engine?.stop()
    }
}

// MARK: - Preview

#Preview {
    BeastVisionView()
}
