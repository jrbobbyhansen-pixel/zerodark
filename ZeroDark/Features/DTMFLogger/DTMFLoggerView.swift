import SwiftUI

struct DTMFLoggerView: View {
    @State private var detector = DTMFDetector()
    @State private var errorMessage: String?
    @State private var exportData: Data?
    @State private var showingExport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Large decoded character display
                ZStack {
                    Color(.systemGray6)
                    VStack(spacing: 4) {
                        Text(detector.recentEvents.first?.character ?? "·")
                            .font(.system(size: 96, weight: .bold, design: .monospaced))
                            .foregroundStyle(detector.isDetecting ? .primary : .tertiary)
                            .contentTransition(.numericText())
                            .animation(.spring(duration: 0.2), value: detector.recentEvents.first?.id)

                        if let event = detector.recentEvents.first {
                            HStack(spacing: 8) {
                                Label(String(format: "SNR %.1f", event.snr), systemImage: "waveform")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Circle()
                                    .fill(snrColor(event.snr))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .frame(height: 180)

                // Session sequence
                if !detector.sessionLog.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(detector.sessionLog) { event in
                                Text(event.character)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .background(snrColor(event.snr).opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                }

                Divider()

                // Event log
                List(detector.recentEvents) { event in
                    HStack {
                        Text(event.character)
                            .font(.system(.title2, design: .monospaced).bold())
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.timestamp, style: .time)
                                .font(.caption)
                            Text(String(format: "SNR: %.1fdB", event.snr))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(snrColor(event.snr))
                            .frame(width: 10, height: 10)
                    }
                }
                .listStyle(.plain)

                Divider()

                // Controls
                HStack(spacing: 16) {
                    Button(action: toggleDetecting) {
                        Label(detector.isDetecting ? "Stop" : "Start Detecting",
                              systemImage: detector.isDetecting ? "stop.circle.fill" : "ear.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(detector.isDetecting ? .red : .accentColor)

                    if !detector.sessionLog.isEmpty,
                       let data = try? JSONEncoder().encode(detector.sessionLog) {
                        ShareLink(item: String(data: data, encoding: .utf8) ?? "", preview: .init("DTMF Log")) {
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
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func toggleDetecting() {
        if detector.isDetecting {
            detector.stopDetecting()
        } else {
            do {
                try detector.startDetecting()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func snrColor(_ snr: Float) -> Color {
        switch snr {
        case ..<0.3: return .red
        case 0.3..<0.6: return .orange
        default: return .green
        }
    }
}
