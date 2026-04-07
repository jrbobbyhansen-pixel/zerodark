import SwiftUI

struct LLMAssistantView: View {
    @State private var vm = LLMAssistantViewModel()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Model status banner
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .foregroundStyle(.orange)
                    Text(vm.modelStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if vm.messages.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "brain")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.tertiary)
                                    Text("Fully offline AI assistant\nAll inference on-device")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                            ForEach(vm.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if vm.isGenerating {
                                TypingIndicator()
                                    .id("typing")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    .onChange(of: vm.messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(vm.messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: vm.isGenerating) { _, _ in
                        withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                    }
                }

                Divider()

                // Input bar
                HStack(spacing: 10) {
                    // Voice button
                    Button(action: toggleVoice) {
                        Image(systemName: vm.isListeningForVoice ? "mic.fill" : "mic")
                            .foregroundStyle(vm.isListeningForVoice ? .red : .secondary)
                            .frame(width: 28, height: 28)
                    }

                    TextField(vm.isListeningForVoice ? vm.voiceTranscript : "Message...",
                              text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($inputFocused)

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSend ? .accentColor : .secondary)
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Assistant")
            .toolbar {
                if let filename = vm.sessionFilename,
                   let url = try? VaultManager.shared.exportURL(filename: filename) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isGenerating
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        inputFocused = false
        Task { await vm.sendMessage(text) }
    }

    private func toggleVoice() {
        if vm.isListeningForVoice {
            let transcript = vm.stopVoiceInput()
            if !transcript.isEmpty { inputText = transcript }
        } else {
            vm.startVoiceInput()
        }
    }
}

struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .assistant { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.accentColor : Color(.systemGray5),
                                in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            if message.role == .user { Spacer(minLength: 40) }
        }
    }
}

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 40)
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.2 : 0.8)
                        .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                                   value: animating)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 18))
        }
        .onAppear { animating = true }
    }
}
