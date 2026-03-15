import SwiftUI
import PhotosUI
import MLXEdgeLLM
import MLXEdgeLLMUI
import MLXEdgeLLMVoice
import MLXEdgeLLMDocs

// MARK: - ContentView
// SquadOps Design: Deep impact. Elegant. Minimal chrome.

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Deep black background
            Theme.background
                .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                // 💬 Chat - Primary experience
                ChatView()
                    .tabItem {
                        Label("Chat", systemImage: "message.fill")
                    }
                    .tag(0)
                
                // 🎤 Voice
                VoiceView()
                    .tabItem {
                        Label("Voice", systemImage: "waveform")
                    }
                    .tag(1)
                
                // 👁️ Vision
                VisionView()
                    .tabItem {
                        Label("Vision", systemImage: "eye.fill")
                    }
                    .tag(2)
                
                // ⚙️ Settings
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .tint(Theme.accent)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Chat View

struct ChatView: View {
    @State private var message = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.spacingMD) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if isGenerating {
                                TypingIndicator()
                            }
                        }
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.top, Theme.spacingMD)
                        .padding(.bottom, Theme.spacing2XL)
                    }
                    .onChange(of: messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                
                // Input
                inputBar
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ZeroDark")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 8, height: 8)
                        .subtleGlow(color: Theme.success)
                    Text("On-Device • Private")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
        .background(Theme.background)
    }
    
    private var inputBar: some View {
        HStack(spacing: Theme.spacingSM) {
            // Text field
            HStack {
                TextField("Message", text: $message)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingSM)
                
                if !message.isEmpty {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.accent)
                            .subtleGlow()
                    }
                    .padding(.trailing, Theme.spacingXS)
                }
            }
            .background(Theme.surface)
            .cornerRadius(Theme.radiusXL)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXL)
                    .stroke(Theme.surfaceElevated, lineWidth: 1)
            )
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
        .background(Theme.background)
    }
    
    private func sendMessage() {
        guard !message.isEmpty else { return }
        
        let userMessage = ChatMessage(role: .user, content: message)
        messages.append(userMessage)
        message = ""
        
        isGenerating = true
        
        // Simulate response (replace with actual MLX inference)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let response = ChatMessage(role: .assistant, content: "This is a placeholder response. Connect to ZeroDarkAI for real inference.")
            messages.append(response)
            isGenerating = false
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 16))
                    .foregroundColor(message.role == .user ? Theme.background : Theme.textPrimary)
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, Theme.spacingSM)
                    .background(message.role == .user ? Theme.accent : Theme.surface)
                    .cornerRadius(Theme.radiusLG)
            }
            
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.textMuted)
                        .frame(width: 8, height: 8)
                        .opacity(animating ? 0.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .background(Theme.surface)
            .cornerRadius(Theme.radiusLG)
            
            Spacer()
        }
        .onAppear { animating = true }
    }
}

// MARK: - Voice View

struct VoiceView: View {
    @State private var isListening = false
    @State private var audioLevel: CGFloat = 0.3
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: Theme.spacingXL) {
                Spacer()
                
                // Visualizer
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(Theme.accent.opacity(0.2), lineWidth: 2)
                        .frame(width: 240, height: 240)
                        .scaleEffect(isListening ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isListening)
                    
                    // Middle ring
                    Circle()
                        .stroke(Theme.accent.opacity(0.4), lineWidth: 3)
                        .frame(width: 180, height: 180)
                        .scaleEffect(isListening ? 1.0 + audioLevel * 0.2 : 1.0)
                    
                    // Core button
                    Button(action: { isListening.toggle() }) {
                        ZStack {
                            Circle()
                                .fill(isListening ? Theme.accent : Theme.surface)
                                .frame(width: 120, height: 120)
                                .activeGlow(color: Theme.accent, isActive: isListening)
                            
                            Image(systemName: isListening ? "waveform" : "mic.fill")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(isListening ? Theme.background : Theme.accent)
                        }
                    }
                }
                
                // Status
                VStack(spacing: Theme.spacingSM) {
                    Text(isListening ? "Listening..." : "Tap to Speak")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    
                    Text("On-device voice recognition")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
                
                Spacer()
                Spacer()
            }
        }
    }
}

// MARK: - Vision View

struct VisionView: View {
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: Theme.spacingLG) {
                // Header
                HStack {
                    Text("Vision")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, Theme.spacingMD)
                
                if let image = selectedImage {
                    // Show selected image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(Theme.radiusLG)
                        .padding(.horizontal, Theme.spacingMD)
                    
                    Button("Analyze") {}
                        .buttonStyle(AccentButtonStyle())
                } else {
                    // Empty state
                    Spacer()
                    
                    VStack(spacing: Theme.spacingMD) {
                        ZStack {
                            Circle()
                                .fill(Theme.surface)
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "eye.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.accent)
                        }
                        
                        Text("Analyze Images")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        
                        Text("Select an image to analyze with vision AI")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                        
                        Button("Select Image") {
                            showImagePicker = true
                        }
                        .buttonStyle(GhostButtonStyle())
                        .padding(.top, Theme.spacingSM)
                    }
                    
                    Spacer()
                }
            }
            .padding(.top, Theme.spacingMD)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Theme.spacingMD) {
                    // Header
                    HStack {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.top, Theme.spacingMD)
                    
                    // Model Selection
                    SettingsSection(title: "Model") {
                        SettingsRow(icon: "cpu.fill", title: "Active Model", value: "Qwen3 8B")
                        SettingsRow(icon: "arrow.down.circle.fill", title: "Download Models", value: "")
                    }
                    
                    // Voice
                    SettingsSection(title: "Voice") {
                        SettingsRow(icon: "waveform", title: "Voice Style", value: "Natural")
                        SettingsRow(icon: "speaker.wave.3.fill", title: "Speed", value: "1.0x")
                    }
                    
                    // Privacy
                    SettingsSection(title: "Privacy") {
                        SettingsRow(icon: "lock.shield.fill", title: "On-Device Only", value: "Enabled")
                        SettingsRow(icon: "trash.fill", title: "Clear History", value: "")
                    }
                    
                    // About
                    SettingsSection(title: "About") {
                        SettingsRow(icon: "info.circle.fill", title: "Version", value: "1.0.0")
                        SettingsRow(icon: "star.fill", title: "Rate App", value: "")
                    }
                    
                    Spacer(minLength: 100)
                }
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, Theme.spacingMD)
            
            VStack(spacing: 1) {
                content
            }
            .background(Theme.surface)
            .cornerRadius(Theme.radiusMD)
            .padding(.horizontal, Theme.spacingMD)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Theme.accent)
                .frame(width: 28)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
            
            Spacer()
            
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textSecondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM + 4)
        .background(Theme.surface)
    }
}

// MARK: - Supporting Types

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
}

enum MessageRole {
    case user
    case assistant
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
