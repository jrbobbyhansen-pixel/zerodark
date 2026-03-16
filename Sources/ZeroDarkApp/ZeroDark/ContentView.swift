import SwiftUI
import PhotosUI
import MLXEdgeLLM
import MLXEdgeLLMUI
import MLXEdgeLLMVoice
import MLXEdgeLLMDocs

// MARK: - ContentView
// 12/10 Delight. Beyond polish. Magic.

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var previousTab = 0
    
    private let tabs = [
        (icon: "message.fill", label: "Chat"),
        (icon: "waveform", label: "Voice"),
        (icon: "eye.fill", label: "Vision"),
        (icon: "gearshape.fill", label: "Settings")
    ]
    
    var body: some View {
        ZStack {
            // Deep background with floating particles
            Theme.background.ignoresSafeArea()
            FloatingParticles()
                .ignoresSafeArea()
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Content with gesture-driven transitions
                TabView(selection: $selectedTab) {
                    ChatView()
                        .tag(0)
                    
                    VoiceView()
                        .tag(1)
                    
                    VisionView()
                        .tag(2)
                    
                    SettingsView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedTab)
                .onChange(of: selectedTab) { newTab in
                    if newTab != previousTab {
                        HapticsEngine.shared.softTap()
                        previousTab = newTab
                    }
                }
                
                // Custom tab bar
                CustomTabBar(selectedTab: $selectedTab, tabs: tabs)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Chat View

struct ChatView: View {
    @State private var message = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showSendParticles = false
    @State private var showSuccess = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                header
                    .animation(.spring(response: 0.3), value: isInputFocused)
                
                // Messages or Empty State
                if messages.isEmpty && !isGenerating {
                    Spacer()
                    EmptyState(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Start a Conversation",
                        subtitle: "Your messages are processed entirely on-device. Private by design."
                    )
                    Spacer()
                } else {
                    // Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: Theme.spacingMD) {
                                ForEach(messages) { msg in
                                    MessageBubble(message: msg)
                                        .id(msg.id)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.95).combined(with: .opacity).combined(with: .offset(y: 10)),
                                            removal: .opacity
                                        ))
                                }
                                
                                if isGenerating {
                                    TypingIndicator()
                                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, Theme.spacingMD)
                            .padding(.top, Theme.spacingMD)
                            .padding(.bottom, Theme.spacing2XL)
                        }
                        .onChange(of: messages.count) { _ in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                proxy.scrollTo(messages.last?.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input
                inputBar
            }
            
            // Toast
            if showToast {
                VStack {
                    Toast(message: toastMessage, type: .success)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 50)
                    Spacer()
                }
                .animation(.spring(response: 0.4), value: showToast)
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("ZeroDark")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    
                    // Model badge
                    Text("8B")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accentMuted)
                        .cornerRadius(4)
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 6, height: 6)
                        .subtleGlow(color: Theme.success)
                    Text("On-Device • Private • Uncensored")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }
            }
            
            Spacer()
            
            // Model selector
            AnimatedButton(action: {}) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface)
                    .cornerRadius(Theme.radiusSM)
            }
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
    }
    
    private var inputBar: some View {
        HStack(spacing: Theme.spacingSM) {
            // Attachment button
            AnimatedButton(action: {}) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.textMuted)
            }
            
            // Text field
            HStack {
                TextField("Message", text: $message)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textPrimary)
                    .focused($isInputFocused)
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, 12)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)
                
                if !message.isEmpty {
                    ZStack {
                        ParticleEmitter(color: Theme.accent, particleCount: 12, isEmitting: $showSendParticles)
                        
                        ElasticButton(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(Theme.accent)
                                .breathingGlow()
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
            .background(Theme.surface)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(isInputFocused ? Theme.accent.opacity(0.3) : Theme.surfaceElevated, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.2), value: isInputFocused)
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, Theme.spacingSM)
        .background(Theme.background.opacity(0.95))
    }
    
    private func sendMessage() {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        // Advanced haptic pattern for send
        HapticsEngine.shared.messageSent()
        showSendParticles = true
        
        let userMessage = ChatMessage(role: .user, content: message)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            messages.append(userMessage)
        }
        message = ""
        
        isGenerating = true
        
        // Simulate response (replace with actual MLX inference)
        let delay = Double.random(in: 1.2...2.0) // Realistic typing delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            HapticsEngine.shared.responseReceived()
            let response = ChatMessage(role: .assistant, content: "I'm ZeroDark, running entirely on your device. No data leaves this phone. What would you like to explore?")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages.append(response)
                isGenerating = false
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var appeared = false
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 50) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 16))
                    .foregroundColor(message.role == .user ? Theme.background : Theme.textPrimary)
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if message.role == .user {
                                LinearGradient(
                                    colors: [Theme.accent, Theme.accent.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                Theme.surface
                            }
                        }
                    )
                    .cornerRadius(20)
                    .cornerRadius(message.role == .user ? 20 : 20, corners: message.role == .user ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
            }
            
            if message.role == .assistant { Spacer(minLength: 50) }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

// Custom corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, 14)
            .background(Theme.surface)
            .cornerRadius(20)
            
            Spacer()
        }
        .onAppear { animating = true }
    }
}

// MARK: - Voice View

struct VoiceView: View {
    @State private var isListening = false
    @State private var audioLevel: CGFloat = 0.3
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: Theme.spacingXL) {
            Spacer()
            
            // Visualizer
            ZStack {
                // Outer pulse rings
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(Theme.accent.opacity(0.1 - Double(index) * 0.03), lineWidth: 1)
                        .frame(width: CGFloat(200 + index * 40), height: CGFloat(200 + index * 40))
                        .scaleEffect(isListening ? 1.0 + CGFloat(index) * 0.05 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: isListening
                        )
                }
                
                // Glow ring
                Circle()
                    .stroke(Theme.accent.opacity(isListening ? 0.3 : 0.1), lineWidth: 2)
                    .frame(width: 160, height: 160)
                    .scaleEffect(isListening ? 1.0 + audioLevel * 0.15 : 1.0)
                    .blur(radius: isListening ? 2 : 0)
                    .animation(.easeOut(duration: 0.1), value: audioLevel)
                
                // Core button - morphing blob when active
                ElasticButton(action: { 
                    isListening.toggle()
                    if isListening {
                        HapticsEngine.shared.voiceActivated()
                        simulateAudioLevels()
                    }
                }) {
                    ZStack {
                        if isListening {
                            MorphingBlob(color: Theme.accent.opacity(0.3))
                                .frame(width: 140, height: 140)
                                .blur(radius: 10)
                        }
                        
                        Circle()
                            .fill(isListening ? Theme.accent : Theme.surface)
                            .frame(width: 120, height: 120)
                            .breathingGlow(color: isListening ? Theme.accent : .clear)
                        
                        Image(systemName: isListening ? "waveform" : "mic.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(isListening ? Theme.background : Theme.accent)
                            .symbolEffect(.variableColor, isActive: isListening)
                    }
                }
            }
            
            // Status
            VStack(spacing: Theme.spacingSM) {
                Text(isListening ? "Listening..." : "Tap to Speak")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                    .animation(.easeInOut, value: isListening)
                
                Text("On-device voice recognition")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textMuted)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    private func simulateAudioLevels() {
        guard isListening else { return }
        audioLevel = CGFloat.random(in: 0.2...1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            simulateAudioLevels()
        }
    }
}

// MARK: - Vision View

struct VisionView: View {
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isAnalyzing = false
    
    var body: some View {
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
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(Theme.radiusLG)
                    
                    if isAnalyzing {
                        RoundedRectangle(cornerRadius: Theme.radiusLG)
                            .fill(Theme.background.opacity(0.7))
                        
                        VStack(spacing: Theme.spacingMD) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                                .scaleEffect(1.5)
                            Text("Analyzing...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingMD)
                
                HStack(spacing: Theme.spacingMD) {
                    Button(action: { selectedImage = nil }) {
                        Text("Clear")
                    }
                    .buttonStyle(GhostButtonStyle())
                    
                    Button(action: analyze) {
                        Text("Analyze")
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            } else {
                // Empty state
                Spacer()
                
                EmptyState(
                    icon: "eye.fill",
                    title: "Analyze Images",
                    subtitle: "Select an image to analyze with on-device vision AI",
                    action: { showImagePicker = true },
                    actionLabel: "Select Image"
                )
                
                Spacer()
            }
        }
        .padding(.top, Theme.spacingMD)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
    }
    
    private func analyze() {
        Haptics.medium()
        isAnalyzing = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isAnalyzing = false
            Haptics.success()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedModel = "Qwen3 8B"
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacingLG) {
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
                    SettingsRow(icon: "cpu.fill", title: "Active Model", value: selectedModel, accent: true)
                    SettingsRow(icon: "arrow.down.circle.fill", title: "Download Models", value: "3 available")
                    SettingsRow(icon: "memorychip.fill", title: "Memory Usage", value: "4.2 GB")
                }
                
                // Voice
                SettingsSection(title: "Voice") {
                    SettingsRow(icon: "waveform", title: "Voice Style", value: "Natural")
                    SettingsRow(icon: "speaker.wave.3.fill", title: "Speed", value: "1.0x")
                    SettingsRow(icon: "person.wave.2.fill", title: "Wake Word", value: "Off")
                }
                
                // Privacy
                SettingsSection(title: "Privacy") {
                    SettingsRow(icon: "lock.shield.fill", title: "On-Device Only", value: "Always", accent: true)
                    SettingsRow(icon: "eye.slash.fill", title: "Incognito Mode", value: "Off")
                    SettingsRow(icon: "trash.fill", title: "Clear All Data", value: "", destructive: true)
                }
                
                // About
                SettingsSection(title: "About") {
                    SettingsRow(icon: "info.circle.fill", title: "Version", value: "1.0.0")
                    SettingsRow(icon: "chevron.left.forwardslash.chevron.right", title: "Open Source", value: "GitHub")
                    SettingsRow(icon: "heart.fill", title: "Built with MLX", value: "")
                }
                
                Spacer(minLength: 100)
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
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, Theme.spacingMD)
            
            VStack(spacing: 0) {
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
    var accent: Bool = false
    var destructive: Bool = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(destructive ? Theme.error : (accent ? Theme.accent : Theme.textSecondary))
                .frame(width: 28)
            
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(destructive ? Theme.error : Theme.textPrimary)
            
            Spacer()
            
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(accent ? Theme.accent : Theme.textSecondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Supporting Types

struct ChatMessage: Identifiable, Equatable {
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
