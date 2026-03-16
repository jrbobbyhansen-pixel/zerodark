import SwiftUI
import MLXEdgeLLM

struct ContentView: View {
    @StateObject private var modelManager = MLXModelManager.shared
    @State private var prompt = ""
    @State private var response = ""
    @State private var isGenerating = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Model status
                if !modelManager.isReady {
                    modelLoadingView
                } else {
                    chatView
                }
            }
            .navigationTitle("ZeroDark")
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
    
    // MARK: - Model Loading
    
    private var modelLoadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if modelManager.isLoading {
                VStack(spacing: 16) {
                    ProgressView(value: modelManager.loadProgress)
                        .tint(.cyan)
                        .scaleEffect(1.5)
                    
                    Text("Loading model... \(Int(modelManager.loadProgress * 100))%")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(40)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "brain")
                        .font(.system(size: 60))
                        .foregroundColor(.cyan)
                    
                    Text("Select a Model")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    ForEach(modelManager.availableModels) { model in
                        Button {
                            Task {
                                try? await modelManager.loadModel(model.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(model.name)
                                        .font(.headline)
                                    Text(model.size)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if model.recommended {
                                    Text("Recommended")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.cyan.opacity(0.2))
                                        .foregroundColor(.cyan)
                                        .cornerRadius(4)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            
            Spacer()
        }
    }
    
    // MARK: - Chat
    
    private var chatView: some View {
        VStack(spacing: 0) {
            // Response area
            ScrollView {
                if response.isEmpty {
                    VStack(spacing: 16) {
                        Spacer(minLength: 100)
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.cyan.opacity(0.5))
                        Text("Ask me anything")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                } else {
                    Text(response)
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            
            // Stats
            if modelManager.tokensPerSecond > 0 {
                HStack {
                    Text("\(modelManager.tokensPerSecond, specifier: "%.1f") tok/s")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            // Input
            HStack(spacing: 12) {
                TextField("Message", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                
                Button {
                    generate()
                } label: {
                    Image(systemName: isGenerating ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(.cyan)
                }
                .disabled(prompt.isEmpty && !isGenerating)
            }
            .padding()
        }
    }
    
    private func generate() {
        guard !prompt.isEmpty else { return }
        
        let currentPrompt = prompt
        prompt = ""
        isGenerating = true
        response = ""
        
        Task {
            response = await UnifiedInferenceEngine.shared.generate(
                prompt: currentPrompt,
                maxTokens: 512
            )
            isGenerating = false
        }
    }
}

#Preview {
    ContentView()
}
