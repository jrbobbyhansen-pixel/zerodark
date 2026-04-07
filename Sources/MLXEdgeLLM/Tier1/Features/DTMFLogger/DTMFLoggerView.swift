import SwiftUI

struct DTMFLoggerView: View {
    @State private var detector = DTMFDetector()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Large decoded character display
                ZStack {
                    Color(.systemGray6)
                    VStack(spacing: 4) {
                        Text(detector.recentEvents.last?.character ?? "·")
                            .font(.system(size: 96, weight: .bold, design: .monospaced))
                            .foregroundStyle(detector.isDetecting ? .primary : .tertiary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.2), value: detector.recentEvents.last?.id)

                        if let event = detector.recentEvents.last {
                            HStack(spacing: 8) {
                                Label(String(format: "%.0f%% tone", event.toneFraction * 100),
                                      systemImage: "waveform")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Circle()
                                    .fill(qualityColor(event.toneFraction))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .frame(height: 180)

                // Session sequence — newest at right
                if !detector.sessionLog.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(detector.sessionLog) { event in
                                Text(event.character)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .background(qualityColor(event.toneFraction).opacity(0.2),
                                                in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                }

                Divider()

                // Event log (recentEvents is newest-last, reverse for display)
                List(detector.recentEvents.reversed()) { event in
                    HStack {
                        Text(event.character)
                            .font(.system(.title2, design: .monospaced).bold())
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.timestamp, style: .time)
                                .font(.caption)
                            Text(String(format: "Tone: %.0f%%", event.toneFraction * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(qualityColor(event.toneFraction))
                            .frame(width: 10, height: 10)
                    }
                }
                .listStyle(.plain)

                Divider()

                HStack(spacing: 16) {
                    Button(action: toggleDetecting) {
                        Label(detector.isDetecting ? "Stop" : "Start Detecting",
                              systemImage: detector.isDetecting ? "stop.circle.fill" : "ear.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(detector.isDetecting ? .red : .accentColor)

                    if !detector.sessionLog.isEmpty,
                       let data = try? JSONEncoder().encode(detector.sessionLog),
                       let str = String(data: data, encoding: .utf8) {
                        ShareLink(item: str, preview: .init("DTMF Log")) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("DTMF Logger")
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func toggleDetecting() {
        if detector.isDetecting {
            detector.stopDetecting()
        } else {
            do { try detector.startDetecting() } catch { errorMessage = error.localizedDescription }
        }
    }

    private func qualityColor(_ toneFraction: Float) -> Color {
        switch toneFraction {
        case ..<0.3: return .red
        case 0.3..<0.6: return .orange
        default: return .green
        }
    }
}
