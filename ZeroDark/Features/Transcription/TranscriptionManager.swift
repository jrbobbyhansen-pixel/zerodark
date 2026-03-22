import Foundation
import AVFoundation
import Speech
import UserNotifications
import UIKit
import Observation

@Observable
final class TranscriptionManager: NSObject, SFSpeechRecognizerDelegate {
    var isListening = false
    var currentTranscript = ""
    var alertCount = 0
    var sessionFilename: String?

    private var keywords: [String] = []
    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var fullTranscript = ""
    private let vault = VaultManager.shared
    private var sessionStart: Date?

    override init() {
        super.init()
        loadKeywords()
        SFSpeechRecognizer.requestAuthorization { _ in }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Public API

    func setKeywords(_ words: [String]) {
        keywords = words.map { $0.lowercased() }
        UserDefaults.standard.set(words, forKey: "ZD_Keywords")
    }

    func startListening() throws {
        guard !isListening else { return }
        try configureAudioSession()
        recognizer = SFSpeechRecognizer(locale: .current)
        recognizer?.delegate = self
        guard recognizer?.isAvailable == true else { throw TranscriptionError.recognizerUnavailable }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { throw TranscriptionError.requestFailed }
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        sessionStart = Date()
        sessionFilename = nil
        fullTranscript = ""
        currentTranscript = ""

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.currentTranscript = text
                    self.fullTranscript = text
                    self.checkKeywords(in: text)
                }
            }
            if error != nil || result?.isFinal == true {
                self.stopListening()
            }
        }
        isListening = true
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        saveTranscript()
    }

    // MARK: - Private

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func loadKeywords() {
        if let saved = UserDefaults.standard.array(forKey: "ZD_Keywords") as? [String] {
            keywords = saved.map { $0.lowercased() }
        }
    }

    private var lastAlertedText = ""
    private func checkKeywords(in text: String) {
        guard text != lastAlertedText else { return }
        let lower = text.lowercased()
        for kw in keywords where lower.contains(kw) {
            lastAlertedText = text
            alertCount += 1
            triggerAlert(keyword: kw)
            break
        }
    }

    private func triggerAlert(keyword: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let content = UNMutableNotificationContent()
        content.title = "ZeroDark Alert"
        content.body = "Keyword detected: \"\(keyword)\""
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func saveTranscript() {
        guard !fullTranscript.isEmpty, let start = sessionStart else { return }
        let formatter = ISO8601DateFormatter()
        let filename = "transcript_\(formatter.string(from: start)).txt"
        let header = "ZeroDark Transcript\nSession: \(formatter.string(from: start))\nKeywords: \(keywords.joined(separator: ", "))\nAlerts: \(alertCount)\n\n"
        let content = header + fullTranscript
        try? vault.save(data: Data(content.utf8), filename: filename)
        sessionFilename = filename
    }
}

enum TranscriptionError: Error, LocalizedError {
    case recognizerUnavailable
    case requestFailed
    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer unavailable — check iOS Settings > Privacy > Speech Recognition"
        case .requestFailed: return "Failed to create recognition request"
        }
    }
}
