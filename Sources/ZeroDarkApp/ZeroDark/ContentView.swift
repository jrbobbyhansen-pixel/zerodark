import SwiftUI
import PhotosUI
import MLXEdgeLLM
import MLXEdgeLLMUI
import MLXEdgeLLMVoice
import MLXEdgeLLMDocs

// MARK: - Root View

struct ContentView: View {
    @State private var tab = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            
            Group {
                switch tab {
                case 0: ChatTab()
                case 1: VoiceTab()
                case 2: VisionTab()
                case 3: SettingsTab()
                default: ChatTab()
                }
            }
            
            // Tab bar - minimal, bottom edge
            HStack(spacing: 0) {
                TabButton(icon: "bubble.left", label: "Chat", selected: tab == 0) { tab = 0 }
                TabButton(icon: "waveform", label: "Voice", selected: tab == 1) { tab = 1 }
                TabButton(icon: "viewfinder", label: "Vision", selected: tab == 2) { tab = 2 }
                TabButton(icon: "slider.horizontal.3", label: "Settings", selected: tab == 3) { tab = 3 }
            }
            .padding(.horizontal, Theme.space4)
            .padding(.top, Theme.space3)
            .padding(.bottom, 28)
            .background(
                Theme.background
                    .overlay(
                        LinearGradient(
                            colors: [Theme.background.opacity(0), Theme.background],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .frame(height: 40)
                        .offset(y: -30),
                        alignment: .top
                    )
            )
        }
        .preferredColorScheme(.dark)
    }
}

struct TabButton: View {
    let icon: String
    let label: String
    let selected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            Haptic.select()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: selected ? "\(icon).fill" : icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(selected ? Theme.text : Theme.textTertiary)
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(selected ? Theme.text : Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Chat

struct ChatTab: View {
    @State private var input = ""
    @State private var messages: [Message] = []
    @State private var isThinking = false
    @FocusState private var focused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - typography forward
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZeroDark")
                        .font(Theme.titleFont)
                        .foregroundColor(Theme.text)
                    
                    Text("On-device · Private")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                }
                
                Spacer()
                
                // Model indicator - subtle
                Text("8B")
                    .font(Theme.monoFont)
                    .foregroundColor(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .padding(.horizontal, Theme.space5)
            .padding(.top, Theme.space6)
            .padding(.bottom, Theme.space4)
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.space4) {
                        if messages.isEmpty {
                            emptyState
                                .padding(.top, 100)
                        }
                        
                        ForEach(messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                        
                        if isThinking {
                            ThinkingIndicator()
                        }
                    }
                    .padding(.horizontal, Theme.space5)
                    .padding(.bottom, 120)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(messages.last?.id)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Input - clean, no border until focused
            HStack(spacing: Theme.space3) {
                TextField("Message", text: $input, axis: .vertical)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.text)
                    .lineLimit(1...6)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                
                if !input.isEmpty {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.background)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, Theme.space4)
            .padding(.vertical, Theme.space3)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous)
                    .stroke(focused ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, Theme.space5)
            .padding(.bottom, 90)
            .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.space4) {
            Text("Ask anything")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.text)
            
            Text("Running locally. Nothing leaves this device.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        Haptic.tap()
        
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(Message(role: .user, content: text))
        }
        input = ""
        isThinking = true
        
        // Simulate
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            Haptic.success()
            withAnimation(.easeOut(duration: 0.2)) {
                messages.append(Message(role: .assistant, content: "Running entirely on this device. No servers, no tracking, no limits. What would you like to explore?"))
                isThinking = false
            }
        }
    }
}

struct Message: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    
    enum Role { case user, assistant }
}

struct MessageRow: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: Theme.space3) {
            if message.role == .user {
                Spacer(minLength: 48)
            }
            
            Text(message.content)
                .font(Theme.bodyFont)
                .foregroundColor(message.role == .user ? Theme.text : Theme.textSecondary)
                .padding(.horizontal, Theme.space4)
                .padding(.vertical, Theme.space3)
                .background(message.role == .user ? Theme.surface : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous))
                .overlay(
                    Group {
                        if message.role == .user {
                            RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        }
                    }
                )
            
            if message.role == .assistant {
                Spacer(minLength: 48)
            }
        }
    }
}

struct ThinkingIndicator: View {
    @State private var dots = 0
    
    var body: some View {
        HStack {
            Text("Thinking" + String(repeating: ".", count: dots))
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .frame(width: 80, alignment: .leading)
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { timer in
                dots = (dots + 1) % 4
            }
        }
    }
}

// MARK: - Voice

struct VoiceTab: View {
    @State private var isListening = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Just a circle. Nothing fancy.
            Button(action: {
                Haptic.tap()
                isListening.toggle()
            }) {
                ZStack {
                    Circle()
                        .fill(isListening ? Theme.accent : Theme.surface)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Circle()
                                .stroke(isListening ? Theme.accent : Theme.border, lineWidth: 1)
                        )
                    
                    Image(systemName: "waveform")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(isListening ? .white : Theme.textSecondary)
                }
            }
            .scaleEffect(isListening ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isListening)
            
            Text(isListening ? "Listening..." : "Tap to speak")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .padding(.top, Theme.space6)
            
            Spacer()
            Spacer()
        }
        .padding(.bottom, 100)
    }
}

// MARK: - Vision

struct VisionTab: View {
    @State private var showPicker = false
    @State private var image: UIImage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Vision")
                    .font(Theme.titleFont)
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, Theme.space5)
            .padding(.top, Theme.space6)
            
            Spacer()
            
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous))
                    .padding(.horizontal, Theme.space5)
                
                HStack(spacing: Theme.space3) {
                    Button("Clear") { image = nil }
                        .buttonStyle(SecondaryButton())
                    
                    Button("Analyze") { }
                        .buttonStyle(PrimaryButton())
                }
                .padding(.top, Theme.space5)
            } else {
                VStack(spacing: Theme.space4) {
                    Image(systemName: "photo")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.textTertiary)
                    
                    Text("Select an image to analyze")
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.textTertiary)
                    
                    Button("Choose Image") { showPicker = true }
                        .buttonStyle(SecondaryButton())
                        .padding(.top, Theme.space2)
                }
            }
            
            Spacer()
            Spacer()
        }
        .padding(.bottom, 100)
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $image)
        }
    }
}

// MARK: - Settings

struct SettingsTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(Theme.titleFont)
                        .foregroundColor(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, Theme.space5)
                .padding(.top, Theme.space6)
                .padding(.bottom, Theme.space6)
                
                SettingsGroup(title: "Model") {
                    SettingsRow(label: "Active", value: "Qwen 8B")
                    SettingsRow(label: "Memory", value: "4.2 GB")
                }
                
                SettingsGroup(title: "Voice") {
                    SettingsRow(label: "Style", value: "Natural")
                    SettingsRow(label: "Speed", value: "1.0×")
                }
                
                SettingsGroup(title: "About") {
                    SettingsRow(label: "Version", value: "1.0.0")
                    SettingsRow(label: "Source", value: "GitHub")
                }
            }
            .padding(.bottom, 120)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, Theme.space5)
                .padding(.bottom, Theme.space2)
            
            VStack(spacing: 0) {
                content
            }
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius2, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, Theme.space5)
            .padding(.bottom, Theme.space6)
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.text)
            
            Spacer()
            
            Text(value)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space3 + 2)
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.image = img }
            parent.dismiss()
        }
    }
}

#Preview { ContentView() }
