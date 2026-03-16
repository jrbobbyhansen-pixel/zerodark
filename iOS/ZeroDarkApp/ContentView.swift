import SwiftUI

struct ContentView: View {
    @State private var prompt = ""
    @State private var response = "Ready. Type a message below."
    @State private var isGenerating = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Response area
                ScrollView {
                    Text(response)
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                
                Spacer()
                
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
            .navigationTitle("ZeroDark")
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
    
    private func generate() {
        guard !prompt.isEmpty else { return }
        let currentPrompt = prompt
        prompt = ""
        isGenerating = true
        
        // Placeholder - will integrate MLX later
        Task {
            try? await Task.sleep(for: .seconds(1))
            response = "You asked: \(currentPrompt)\n\n[MLX model integration pending]"
            isGenerating = false
        }
    }
}

#Preview {
    ContentView()
}
