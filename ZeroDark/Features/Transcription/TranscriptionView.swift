import SwiftUI

struct TranscriptionView: View {
    @State private var manager = TranscriptionManager()
    @State private var newKeyword = ""
    @State private var keywords: [String] = UserDefaults.standard.array(forKey: "ZD_Keywords") as? [String] ?? []
    @State private var errorMessage: String?
    @State private var exportURL: URL?
    @State private var showingExport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    Circle()
                        .fill(manager.isListening ? Color.red : Color.gray)
                        .frame(width: 10, height: 10)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: manager.isListening)
                    Text(manager.isListening ? "Listening" : "Idle")
                        .font(.caption)
                    Spacer()
                    if manager.alertCount > 0 {
                        Label("\(manager.alertCount)", systemImage: "bell.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))

                // Live transcript
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(manager.currentTranscript.isEmpty ? "Transcript will appear here..." : manager.currentTranscript)
                            .font(.body)
                            .foregroundStyle(manager.currentTranscript.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .id("bottom")
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: manager.currentTranscript) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }

                Divider()

                // Keywords
                VStack(alignment: .leading, spacing: 8) {
                    Text("Alert Keywords")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(keywords, id: \.self) { kw in
                                HStack(spacing: 4) {
                                    Text(kw)
                                        .font(.caption)
                                    Button { removeKeyword(kw) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                    HStack {
                        TextField("Add keyword...", text: $newKeyword)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        Button("Add") { addKeyword() }
                            .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Controls
                HStack(spacing: 16) {
                    Button(action: toggleListening) {
                        Label(manager.isListening ? "Stop" : "Start Listening",
                              systemImage: manager.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(manager.isListening ? .red : .accentColor)

                    if let filename = manager.sessionFilename,
                       let url = try? VaultManager.shared.exportURL(filename: filename) {
                        ShareLink(item: url) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Transcription")
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func toggleListening() {
        if manager.isListening {
            manager.stopListening()
        } else {
            do {
                try manager.startListening()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !keywords.contains(kw) else { return }
        keywords.append(kw)
        manager.setKeywords(keywords)
        newKeyword = ""
    }

    private func removeKeyword(_ kw: String) {
        keywords.removeAll { $0 == kw }
        manager.setKeywords(keywords)
    }
}
