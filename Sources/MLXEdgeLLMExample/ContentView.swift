import SwiftUI
import MLXEdgeLLM
import PhotosUI

struct ContentView: View {

    // MARK: - State

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var output: String = ""
    @State private var isLoading: Bool = false
    @State private var downloadProgress: Double = 0
    @State private var vision: MLXEdgeLLMVision?
    @State private var modelReady: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                // Model status
                modelStatusView

                // Image picker
                imagePickerView

                // Selected image preview
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                // Action buttons
                actionButtonsView

                // Output
                outputView

                Spacer()
            }
            .padding()
            .navigationTitle("MLXEdgeLLM Demo")
            .task {
                await loadModel()
            }
        }
    }

    // MARK: - Subviews

    private var modelStatusView: some View {
        HStack {
            Circle()
                .fill(modelReady ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            if modelReady {
                Text("Qwen3.5 0.8B — Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if downloadProgress > 0 {
                Text("Downloading model: \(Int(downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: downloadProgress)
                    .frame(width: 100)
            } else {
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.quaternary, in: Capsule())
    }

    private var imagePickerView: some View {
        PhotosPicker(
            selection: $selectedPhoto,
            matching: .images
        ) {
            Label(
                selectedImage == nil ? "Select Receipt Image" : "Change Image",
                systemImage: "photo.badge.plus"
            )
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.blue)
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    output = ""
                }
            }
        }
    }

    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            // Extract receipt
            Button {
                Task { await extractReceipt() }
            } label: {
                Label("Extract Receipt JSON", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAnalyze ? Color.blue : Color.gray.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(canAnalyze ? .white : .secondary)
            }
            .disabled(!canAnalyze)

            // Free prompt
            Button {
                Task { await analyzeImage() }
            } label: {
                Label("Describe Image", systemImage: "eye")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canAnalyze ? Color.purple.opacity(0.8) : Color.gray.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(canAnalyze ? .white : .secondary)
            }
            .disabled(!canAnalyze)

            // Text-only chat test
            Button {
                Task { await testTextChat() }
            } label: {
                Label("Test Text Chat", systemImage: "bubble.left")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(modelReady ? Color.green.opacity(0.8) : Color.gray.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(modelReady ? .white : .secondary)
            }
            .disabled(!modelReady || isLoading)
        }
    }

    private var outputView: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Generating...")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    // MARK: - Computed

    private var canAnalyze: Bool {
        modelReady && selectedImage != nil && !isLoading
    }

    // MARK: - Actions

    private func loadModel() async {
        do {
            vision = try await MLXEdgeLLMVision(
                model: .qwen35_0_8b,
                onProgress: { progress in
                    Task { @MainActor in
                        downloadProgress = progress
                    }
                }
            )
            modelReady = true
        } catch {
            output = "❌ Failed to load model: \(error.localizedDescription)"
        }
    }

    private func extractReceipt() async {
        guard let vision, let image = selectedImage else { return }
        isLoading = true
        output = ""
        do {
            output = try await vision.extractReceipt(image)
        } catch {
            output = "❌ Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func analyzeImage() async {
        guard let vision, let image = selectedImage else { return }
        isLoading = true
        output = ""
        do {
            output = try await vision.analyze("Describe what you see in this image in detail.", image: image)
        } catch {
            output = "❌ Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func testTextChat() async {
        guard let vision else { return }
        isLoading = true
        output = ""
        do {
            output = try await vision.chat("Say hello and introduce yourself in one sentence.")
        } catch {
            output = "❌ Error: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

#Preview {
    ContentView()
}
