// IdentitySettings.swift
// Let users name their AI and give it a voice
// Make it THEIRS

import SwiftUI
import MLXEdgeLLM

public struct IdentitySettingsTab: View {
    @StateObject private var vm = IdentitySettingsViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Agent Preview Card
                    agentPreviewCard
                    
                    // Name Section
                    nameSection
                    
                    // Personality Section
                    personalitySection
                    
                    // Voice Section
                    voiceSection
                    
                    // Response Style
                    responseStyleSection
                    
                    // Presets
                    presetsSection
                    
                    // Save Button
                    saveButton
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("🎭 Identity")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Agent Preview Card
    
    private var agentPreviewCard: some View {
        VStack(spacing: 16) {
            // Avatar
            Text(vm.avatarEmoji)
                .font(.system(size: 80))
            
            // Name
            Text(vm.agentName)
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            
            // Wake phrase
            Text("\"\(vm.wakePhrase)\"")
                .font(.subheadline)
                .foregroundColor(.cyan)
                .italic()
            
            // Personality badge
            Text(vm.personality.rawValue)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.3))
                .cornerRadius(20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.2), Color.cyan.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
    }
    
    // MARK: - Name Section
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeader(title: "Name", icon: "person.fill")
            
            TextField("Agent Name", text: $vm.agentName)
                .textFieldStyle(.roundedBorder)
                .font(.title2)
            
            // Emoji picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Avatar")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.avatarOptions, id: \.self) { emoji in
                            Button {
                                vm.avatarEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 36))
                                    .padding(8)
                                    .background(
                                        vm.avatarEmoji == emoji ?
                                        Color.cyan.opacity(0.3) : Color.white.opacity(0.05)
                                    )
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Personality Section
    
    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeader(title: "Personality", icon: "brain.head.profile")
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AgentIdentity.Personality.allCases, id: \.self) { personality in
                    PersonalityCard(
                        personality: personality,
                        isSelected: vm.personality == personality
                    ) {
                        vm.personality = personality
                    }
                }
            }
            
            if vm.personality == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Personality")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    TextEditor(text: $vm.customPersonality)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Voice Section
    
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Voice", icon: "waveform")
            
            // Voice type picker
            Picker("Voice Type", selection: $vm.voiceType) {
                ForEach(AgentIdentity.VoiceType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            // Voice selection (for system voices)
            if vm.voiceType == .system || vm.voiceType == .personal {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Voice")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(vm.availableVoices) { voice in
                                VoiceRow(
                                    voice: voice,
                                    isSelected: vm.selectedVoiceID == voice.id,
                                    onSelect: {
                                        vm.selectedVoiceID = voice.id
                                    },
                                    onPreview: {
                                        vm.previewVoice(voice)
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            // Voice cloning (for custom voice)
            if vm.voiceType == .custom {
                VoiceCloningSection(vm: vm)
            }
            
            // Speed & pitch sliders
            VStack(spacing: 12) {
                HStack {
                    Text("Speed")
                        .foregroundColor(.gray)
                    Slider(value: $vm.voiceSpeed, in: 0.5...2.0)
                        .tint(.cyan)
                    Text(String(format: "%.1fx", vm.voiceSpeed))
                        .foregroundColor(.white)
                        .frame(width: 50)
                }
                
                HStack {
                    Text("Pitch")
                        .foregroundColor(.gray)
                    Slider(value: $vm.voicePitch, in: -0.5...0.5)
                        .tint(.purple)
                    Text(vm.voicePitch >= 0 ? "+\(String(format: "%.1f", vm.voicePitch))" : String(format: "%.1f", vm.voicePitch))
                        .foregroundColor(.white)
                        .frame(width: 50)
                }
            }
            
            // Test voice button
            Button {
                vm.testVoice()
            } label: {
                HStack {
                    Image(systemName: vm.isSpeaking ? "stop.fill" : "play.fill")
                    Text(vm.isSpeaking ? "Stop" : "Test Voice")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.cyan)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Response Style
    
    private var responseStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeader(title: "Response Style", icon: "text.bubble")
            
            Picker("Style", selection: $vm.responseStyle) {
                ForEach(AgentIdentity.ResponseStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            
            Text(responseStyleDescription)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    private var responseStyleDescription: String {
        switch vm.responseStyle {
        case .brief: return "Short, direct answers (1-2 sentences)"
        case .balanced: return "Clear explanations (2-4 sentences)"
        case .detailed: return "Thorough responses with context"
        case .conversational: return "Back-and-forth dialogue style"
        }
    }
    
    // MARK: - Presets
    
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeader(title: "Quick Presets", icon: "sparkles")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    PresetButton(name: "Jarvis", emoji: "🎩", personality: "Professional") {
                        vm.applyPreset(.jarvis)
                    }
                    PresetButton(name: "Friday", emoji: "💫", personality: "Friendly") {
                        vm.applyPreset(.friday)
                    }
                    PresetButton(name: "Max", emoji: "🚀", personality: "Enthusiastic") {
                        vm.applyPreset(.max)
                    }
                    PresetButton(name: "Sage", emoji: "🧘", personality: "Calm") {
                        vm.applyPreset(.sage)
                    }
                    PresetButton(name: "Pixel", emoji: "⚡", personality: "Concise") {
                        vm.applyPreset(.pixel)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Save Button
    
    private var saveButton: some View {
        Button {
            vm.saveIdentity()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Identity")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .padding(.vertical)
    }
}

// MARK: - View Model

@MainActor
class IdentitySettingsViewModel: ObservableObject {
    @Published var agentName = "Zero Dark"
    @Published var wakePhrase = "Hey Zero Dark"
    @Published var avatarEmoji = "🤖"
    @Published var personality: AgentIdentity.Personality = .professional
    @Published var customPersonality = ""
    @Published var voiceType: AgentIdentity.VoiceType = .system
    @Published var selectedVoiceID: String?
    @Published var voiceSpeed: Float = 1.0
    @Published var voicePitch: Float = 0.0
    @Published var responseStyle: AgentIdentity.ResponseStyle = .balanced
    @Published var isSpeaking = false
    @Published var availableVoices: [VoiceSynthesisEngine.VoiceOption] = []
    
    let avatarOptions = ["🤖", "🧠", "💫", "🎩", "🚀", "⚡", "🌟", "👾", "🔮", "🎭", "🦾", "🛸", "🌙", "🔥", "💎"]
    
    private var voiceEngine: VoiceSynthesisEngine?
    
    init() {
        Task {
            await loadCurrentIdentity()
            await loadVoices()
        }
    }
    
    func loadCurrentIdentity() async {
        let identity = await AgentIdentity.shared.getIdentity()
        agentName = identity.name
        wakePhrase = identity.wakePhrase
        avatarEmoji = identity.avatarEmoji
        personality = identity.personality
        customPersonality = identity.personalityPrompt
        voiceType = identity.voice.voiceType
        selectedVoiceID = identity.voice.systemVoiceID
        voiceSpeed = identity.voice.speed
        voicePitch = identity.voice.pitch
        responseStyle = identity.responseStyle
    }
    
    func loadVoices() async {
        voiceEngine = VoiceSynthesisEngine.shared
        availableVoices = voiceEngine?.availableVoices ?? []
    }
    
    func previewVoice(_ voice: VoiceSynthesisEngine.VoiceOption) {
        voiceEngine?.previewVoice(voice)
    }
    
    func testVoice() {
        if isSpeaking {
            voiceEngine?.stop()
            isSpeaking = false
        } else {
            isSpeaking = true
            let testText = "Hello! I'm \(agentName). How can I help you today?"
            voiceEngine?.speak(testText) {
                Task { @MainActor in
                    self.isSpeaking = false
                }
            }
        }
    }
    
    func applyPreset(_ preset: AgentIdentity.Identity) {
        agentName = preset.name
        wakePhrase = preset.wakePhrase
        avatarEmoji = preset.avatarEmoji
        personality = preset.personality
        customPersonality = preset.personalityPrompt
        responseStyle = preset.responseStyle
    }
    
    func saveIdentity() {
        Task {
            var identity = AgentIdentity.Identity()
            identity.name = agentName
            identity.wakePhrase = "Hey \(agentName)"
            identity.avatarEmoji = avatarEmoji
            identity.personality = personality
            identity.personalityPrompt = customPersonality
            identity.voice.voiceType = voiceType
            identity.voice.systemVoiceID = selectedVoiceID
            identity.voice.speed = voiceSpeed
            identity.voice.pitch = voicePitch
            identity.responseStyle = responseStyle
            
            await AgentIdentity.shared.setIdentity(identity)
        }
    }
}

// MARK: - Components

struct SettingsHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.cyan)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

struct PersonalityCard: View {
    let personality: AgentIdentity.Personality
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(personality.rawValue)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .black : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.cyan : Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct VoiceRow: View {
    let voice: VoiceSynthesisEngine.VoiceOption
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .cyan : .gray)
                    
                    VStack(alignment: .leading) {
                        Text(voice.name)
                            .foregroundColor(.white)
                        Text(voice.quality.rawValue)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
            }
            
            Button(action: onPreview) {
                Image(systemName: "play.circle")
                    .foregroundColor(.cyan)
            }
        }
        .padding(8)
        .background(isSelected ? Color.cyan.opacity(0.1) : Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct VoiceCloningSection: View {
    @ObservedObject var vm: IdentitySettingsViewModel
    @StateObject private var recorder = VoiceRecorder.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record Your Voice")
                .font(.subheadline)
                .foregroundColor(.white)
            
            Text("Record 5 sample phrases to clone your voice")
                .font(.caption)
                .foregroundColor(.gray)
            
            ProgressView(value: recorder.recordingProgress)
                .tint(.purple)
            
            Text("Progress: \(recorder.recordedSamples.count)/\(recorder.samplePhrases.count)")
                .font(.caption)
                .foregroundColor(.gray)
            
            Button {
                // Start recording next sample
            } label: {
                HStack {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    Text(recorder.isRecording ? "Stop Recording" : "Record Sample")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.purple)
        }
    }
}

struct PresetButton: View {
    let name: String
    let emoji: String
    let personality: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.title)
                Text(name)
                    .font(.caption)
                    .foregroundColor(.white)
                Text(personality)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }
}

#Preview {
    IdentitySettingsTab()
}
