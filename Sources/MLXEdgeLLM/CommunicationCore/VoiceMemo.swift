// VoiceMemo.swift — Voice memo recorder with GPS auto-tag, compression, and DTN queue relay
// Records AAC-LD audio, saves to Documents/VoiceMemos/, queues compressed data for mesh relay.

import Foundation
import SwiftUI
import AVFoundation

// MARK: - VoiceMemo

struct VoiceMemo: Identifiable, Codable {
    var id: UUID = UUID()
    var filename: String          // Filename in Documents/VoiceMemos/
    var timestamp: Date = Date()
    var latitude: Double
    var longitude: Double
    var durationSeconds: Double
    var title: String             // Auto-generated from timestamp, editable

    var fileURL: URL {
        VoiceMemoManager.memoDir.appendingPathComponent(filename)
    }

    var locationString: String {
        guard latitude != 0 || longitude != 0 else { return "Unknown" }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }

    var durationFormatted: String {
        let m = Int(durationSeconds) / 60
        let s = Int(durationSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - VoiceMemoManager

@MainActor
final class VoiceMemoManager: NSObject, ObservableObject {
    static let shared = VoiceMemoManager()

    @Published var memos: [VoiceMemo] = []
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var isPlaying = false
    @Published var playingID: UUID? = nil

    static let memoDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceMemos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voice_memo_index.json")
    }()

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var currentRecordURL: URL?

    private override init() {
        super.init()
        load()
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }

        let filename = "\(UUID().uuidString).m4a"
        let url = VoiceMemoManager.memoDir.appendingPathComponent(filename)
        currentRecordURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 11025,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32000
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.record()
            isRecording = true
            recordingTime = 0

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordingTime = self?.recorder?.currentTime ?? 0
                }
            }
        } catch { }
    }

    func stopRecording() {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil

        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = currentRecordURL, FileManager.default.fileExists(atPath: url.path) else { return }
        let filename = url.lastPathComponent
        let loc = LocationManager.shared.currentLocation
        let memo = VoiceMemo(
            filename: filename,
            latitude: loc?.latitude ?? 0,
            longitude: loc?.longitude ?? 0,
            durationSeconds: duration,
            title: "Memo \(Date().formatted(date: .abbreviated, time: .shortened))"
        )
        memos.insert(memo, at: 0)
        save()

        // Queue for DTN mesh relay (compressed)
        Task { await queueForRelay(memo) }
    }

    func delete(_ memo: VoiceMemo) {
        try? FileManager.default.removeItem(at: memo.fileURL)
        memos.removeAll { $0.id == memo.id }
        save()
    }

    // MARK: - Playback

    func play(_ memo: VoiceMemo) {
        stopPlayback()
        guard FileManager.default.fileExists(atPath: memo.fileURL.path) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: memo.fileURL)
            player?.delegate = self
            player?.play()
            isPlaying = true
            playingID = memo.id
        } catch { }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - DTN Relay

    private func queueForRelay(_ memo: VoiceMemo) async {
        guard let rawData = try? Data(contentsOf: memo.fileURL) else { return }

        // Compress with LZFSE
        let compressed = (try? (rawData as NSData).compressed(using: .lzfse) as Data) ?? rawData

        // Build payload: JSON header + compressed audio
        let header: [String: Any] = [
            "type": "voice_memo",
            "id": memo.id.uuidString,
            "timestamp": memo.timestamp.timeIntervalSince1970,
            "lat": memo.latitude,
            "lon": memo.longitude,
            "duration": memo.durationSeconds,
            "title": memo.title,
            "compressedBytes": compressed.count
        ]
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let separator = "\n---\n".data(using: .utf8) else { return }

        var payload = headerData
        payload.append(separator)
        payload.append(compressed)

        let bundle = DTNBundle(
            destination: "all",
            payload: payload,
            priority: .normal,
            ttl: 3600 * 24   // 24-hour relay window
        )
        try? await DTNBuffer.shared.store(bundle)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(memos) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let loaded = try? JSONDecoder().decode([VoiceMemo].self, from: data) else { return }
        // Filter out memos whose file no longer exists
        memos = loaded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceMemoManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.isRecording = false
                self.timer?.invalidate()
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceMemoManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.playingID = nil
        }
    }
}

// MARK: - VoiceMemoView

struct VoiceMemoView: View {
    @ObservedObject private var manager = VoiceMemoManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    recordButton
                    memoList
                }
            }
            .navigationTitle("Voice Memos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Record Button

    private var recordButton: some View {
        VStack(spacing: 12) {
            ZStack {
                // Pulsing ring while recording
                if manager.isRecording {
                    Circle()
                        .stroke(ZDDesign.signalRed.opacity(0.3), lineWidth: 4)
                        .frame(width: 96, height: 96)
                        .scaleEffect(manager.isRecording ? 1.15 : 1)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: manager.isRecording)
                }

                Circle()
                    .fill(manager.isRecording ? ZDDesign.signalRed : ZDDesign.darkCard)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(manager.isRecording ? ZDDesign.signalRed : ZDDesign.cyanAccent, lineWidth: 2))

                Image(systemName: manager.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(manager.isRecording ? ZDDesign.pureWhite : ZDDesign.cyanAccent)
            }
            .onTapGesture {
                if manager.isRecording {
                    manager.stopRecording()
                } else {
                    manager.startRecording()
                }
            }

            if manager.isRecording {
                Text(formatTime(manager.recordingTime))
                    .font(.title3.monospaced().bold())
                    .foregroundColor(ZDDesign.signalRed)
                Text("Tap to stop")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Text("Tap to record")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(ZDDesign.darkCard)
    }

    // MARK: - Memo List

    private var memoList: some View {
        Group {
            if manager.memos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "mic.slash").font(.system(size: 36)).foregroundColor(.secondary)
                    Text("No Memos").font(.headline)
                    Text("Tap the mic to record.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(manager.memos) { memo in
                        MemoRow(memo: memo)
                            .listRowBackground(ZDDesign.darkCard)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    manager.delete(memo)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Memo Row

struct MemoRow: View {
    let memo: VoiceMemo
    @ObservedObject private var manager = VoiceMemoManager.shared

    private var isPlaying: Bool { manager.playingID == memo.id }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if isPlaying { manager.stopPlayback() } else { manager.play(memo) }
            } label: {
                ZStack {
                    Circle().fill(isPlaying ? ZDDesign.cyanAccent : ZDDesign.cyanAccent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.caption.bold())
                        .foregroundColor(isPlaying ? .black : ZDDesign.cyanAccent)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(memo.title).font(.subheadline.bold()).foregroundColor(ZDDesign.pureWhite).lineLimit(1)
                HStack(spacing: 8) {
                    Label(memo.timestamp.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption2).foregroundColor(.secondary)
                    Label(memo.durationFormatted, systemImage: "waveform")
                        .font(.caption2).foregroundColor(.secondary)
                }
                if memo.latitude != 0 || memo.longitude != 0 {
                    Label(memo.locationString, systemImage: "location")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            Spacer()

            // Playing waveform indicator
            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundColor(ZDDesign.cyanAccent)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
