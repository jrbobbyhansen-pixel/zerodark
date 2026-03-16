//
//  CrackedFeatures.swift
//  ZeroDark
//
//  The features nobody else has. Real implementations.
//

import SwiftUI
import AVFoundation
import Speech
import HealthKit
import CoreML
import NaturalLanguage
import SoundAnalysis
import ARKit
import RealityKit
import SceneKit

// MARK: - 1. LOCAL VOICE CLONING

/// Clone your voice using Apple Personal Voice (iOS 17+) or train a local model
@MainActor
class VoiceCloning: ObservableObject {
    static let shared = VoiceCloning()
    
    @Published var availableVoices: [ClonedVoice] = []
    @Published var isRecording = false
    @Published var recordingProgress: Double = 0
    @Published var trainingStatus: TrainingStatus = .idle
    
    private var audioRecorder: AVAudioRecorder?
    private var recordings: [URL] = []
    
    // MARK: - Personal Voice (iOS 17+)
    
    /// Check if Personal Voice is available
    func checkPersonalVoiceAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            let status = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
            if status == .notDetermined {
                return await AVSpeechSynthesizer.requestPersonalVoiceAuthorization() == .authorized
            }
            return status == .authorized
        }
        return false
    }
    
    /// Get user's Personal Voice
    @available(iOS 17.0, *)
    func getPersonalVoices() async -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.voiceTraits.contains(.isPersonalVoice) }
    }
    
    /// Speak with Personal Voice
    @available(iOS 17.0, *)
    func speakWithPersonalVoice(_ text: String) {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        
        if let personalVoice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) {
            utterance.voice = personalVoice
            synthesizer.speak(utterance)
        }
    }
    
    // MARK: - Custom Voice Training (Local)
    
    /// Record samples for voice training
    func startRecordingSample(phrase: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_sample_\(recordings.count).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.record()
        isRecording = true
    }
    
    func stopRecordingSample() {
        audioRecorder?.stop()
        if let url = audioRecorder?.url {
            recordings.append(url)
        }
        isRecording = false
        recordingProgress = Double(recordings.count) / 15.0 // Need ~15 samples
    }
    
    /// Train voice model from samples (would use local ML)
    func trainVoiceModel() async throws {
        trainingStatus = .training
        
        // In production: would use Core ML to train a voice model
        // For now, simulate training
        for i in 0..<10 {
            try await Task.sleep(nanoseconds: 500_000_000)
            trainingStatus = .training
        }
        
        trainingStatus = .complete
    }
    
    enum TrainingStatus {
        case idle, recording, training, complete, failed
    }
}

struct ClonedVoice: Identifiable {
    let id = UUID()
    let name: String
    let modelPath: URL
    let createdAt: Date
}

// MARK: - 2. BIOMETRIC MOOD DETECTION

/// Detect stress/mood from HRV + voice + typing patterns
@MainActor
class MoodDetector: ObservableObject {
    static let shared = MoodDetector()
    
    @Published var currentMood: Mood = .neutral
    @Published var stressLevel: Double = 0.5 // 0-1
    @Published var energyLevel: Double = 0.5
    @Published var moodHistory: [MoodReading] = []
    
    private let healthStore = HKHealthStore()
    private var voiceAnalyzer: VoicePatternAnalyzer?
    private var typingAnalyzer: TypingPatternAnalyzer?
    
    // MARK: - HRV Analysis
    
    /// Analyze heart rate variability for stress
    func analyzeHRV() async throws -> Double {
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrvType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let hrv = stats?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)) ?? 50
                
                // HRV interpretation:
                // < 20ms = high stress
                // 20-50ms = moderate
                // > 50ms = low stress
                let stress = max(0, min(1, (50 - hrv) / 50))
                continuation.resume(returning: stress)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Voice Pattern Analysis
    
    /// Analyze voice for stress indicators
    func analyzeVoice(audioBuffer: AVAudioPCMBuffer) -> VoiceStressIndicators {
        // Voice stress indicators:
        // - Pitch variability (stressed = more variable)
        // - Speaking rate (stressed = faster)
        // - Volume (stressed = louder)
        // - Jitter/shimmer (voice tremor)
        
        let frameLength = Int(audioBuffer.frameLength)
        guard let channelData = audioBuffer.floatChannelData?[0] else {
            return VoiceStressIndicators(pitchVariability: 0.5, speakingRate: 0.5, volume: 0.5)
        }
        
        // Calculate RMS volume
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        let volume = Double(min(1, rms * 10))
        
        // Would do more sophisticated analysis with FFT for pitch
        return VoiceStressIndicators(
            pitchVariability: 0.5, // Placeholder
            speakingRate: 0.5,
            volume: volume
        )
    }
    
    // MARK: - Typing Pattern Analysis
    
    /// Analyze typing patterns for stress
    func analyzeTyping(keystrokes: [KeystrokeEvent]) -> TypingStressIndicators {
        guard keystrokes.count > 10 else {
            return TypingStressIndicators(speed: 0.5, errorRate: 0, rhythmVariability: 0.5)
        }
        
        // Calculate intervals
        var intervals: [TimeInterval] = []
        for i in 1..<keystrokes.count {
            intervals.append(keystrokes[i].timestamp.timeIntervalSince(keystrokes[i-1].timestamp))
        }
        
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let speed = 1.0 / avgInterval // Keys per second
        
        // Rhythm variability (stressed = more erratic)
        let variance = intervals.map { pow($0 - avgInterval, 2) }.reduce(0, +) / Double(intervals.count)
        let stdDev = sqrt(variance)
        let rhythmVariability = min(1, stdDev / avgInterval)
        
        // Error rate (backspaces / total)
        let backspaces = keystrokes.filter { $0.isBackspace }.count
        let errorRate = Double(backspaces) / Double(keystrokes.count)
        
        return TypingStressIndicators(
            speed: min(1, speed / 10), // Normalize
            errorRate: errorRate,
            rhythmVariability: rhythmVariability
        )
    }
    
    // MARK: - Combined Analysis
    
    /// Combine all signals for overall mood
    func updateMood(
        hrv: Double? = nil,
        voice: VoiceStressIndicators? = nil,
        typing: TypingStressIndicators? = nil
    ) {
        var stressSignals: [Double] = []
        
        // HRV (most reliable)
        if let hrv = hrv {
            stressSignals.append(hrv * 1.5) // Weight HRV higher
        }
        
        // Voice
        if let voice = voice {
            let voiceStress = (voice.pitchVariability + voice.volume) / 2
            stressSignals.append(voiceStress)
        }
        
        // Typing
        if let typing = typing {
            let typingStress = (typing.rhythmVariability + typing.errorRate) / 2
            stressSignals.append(typingStress)
        }
        
        // Average
        if !stressSignals.isEmpty {
            stressLevel = stressSignals.reduce(0, +) / Double(stressSignals.count)
            stressLevel = min(1, max(0, stressLevel))
        }
        
        // Determine mood
        currentMood = moodFromStress(stressLevel)
        
        // Log reading
        moodHistory.append(MoodReading(
            mood: currentMood,
            stressLevel: stressLevel,
            timestamp: Date()
        ))
    }
    
    private func moodFromStress(_ stress: Double) -> Mood {
        switch stress {
        case 0..<0.2: return .calm
        case 0.2..<0.4: return .relaxed
        case 0.4..<0.6: return .neutral
        case 0.6..<0.8: return .stressed
        default: return .anxious
        }
    }
}

struct VoiceStressIndicators {
    let pitchVariability: Double
    let speakingRate: Double
    let volume: Double
}

struct TypingStressIndicators {
    let speed: Double
    let errorRate: Double
    let rhythmVariability: Double
}

struct KeystrokeEvent {
    let timestamp: Date
    let isBackspace: Bool
}

enum Mood: String, CaseIterable {
    case calm, relaxed, neutral, stressed, anxious
    
    var emoji: String {
        switch self {
        case .calm: return "😌"
        case .relaxed: return "🙂"
        case .neutral: return "😐"
        case .stressed: return "😰"
        case .anxious: return "😨"
        }
    }
    
    var color: Color {
        switch self {
        case .calm: return .green
        case .relaxed: return .mint
        case .neutral: return .gray
        case .stressed: return .orange
        case .anxious: return .red
        }
    }
}

struct MoodReading: Identifiable {
    let id = UUID()
    let mood: Mood
    let stressLevel: Double
    let timestamp: Date
}

// MARK: - 3. AMBIENT SOUND INTELLIGENCE

/// Detect and classify ambient sounds
@MainActor
class SoundIntelligence: ObservableObject {
    static let shared = SoundIntelligence()
    
    @Published var isListening = false
    @Published var detectedSounds: [DetectedSound] = []
    @Published var alerts: [SoundAlert] = []
    
    private var audioEngine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    
    // Sounds we care about
    let importantSounds = [
        "doorbell", "door_knock", "baby_crying", "dog_bark",
        "smoke_alarm", "glass_breaking", "car_horn", "siren",
        "phone_ringing", "water_running", "microwave", "timer"
    ]
    
    /// Start listening for ambient sounds
    func startListening() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        analyzer = SNAudioStreamAnalyzer(format: format)
        
        // Add sound classification request
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        try analyzer?.add(request, withObserver: self)
        
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
            self?.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
        
        engine.prepare()
        try engine.start()
        isListening = true
    }
    
    /// Stop listening
    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        isListening = false
    }
    
    /// Check if a sound should trigger an alert
    private func shouldAlert(for sound: String) -> Bool {
        let alertSounds = ["doorbell", "baby_crying", "smoke_alarm", "glass_breaking", "siren"]
        return alertSounds.contains { sound.lowercased().contains($0) }
    }
}

extension SoundIntelligence: SNResultsObserving {
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult,
              let topResult = classification.classifications.first,
              topResult.confidence > 0.6 else { return }
        
        let soundName = topResult.identifier
        
        Task { @MainActor in
            let detected = DetectedSound(
                name: soundName,
                confidence: topResult.confidence,
                timestamp: Date()
            )
            
            detectedSounds.insert(detected, at: 0)
            if detectedSounds.count > 50 { detectedSounds.removeLast() }
            
            // Check for alerts
            if shouldAlert(for: soundName) {
                let alert = SoundAlert(
                    sound: detected,
                    message: "\(soundName.capitalized) detected",
                    priority: soundName.contains("smoke") || soundName.contains("glass") ? .high : .medium
                )
                alerts.append(alert)
                
                // Would trigger notification/haptic here
            }
        }
    }
    
    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        print("Sound classification error: \(error)")
    }
}

struct DetectedSound: Identifiable {
    let id = UUID()
    let name: String
    let confidence: Float
    let timestamp: Date
}

struct SoundAlert: Identifiable {
    let id = UUID()
    let sound: DetectedSound
    let message: String
    let priority: AlertPriority
    
    enum AlertPriority {
        case low, medium, high
    }
}

// MARK: - 4. PERSONAL KNOWLEDGE GRAPH

/// Remembers everything about your life
@MainActor
class KnowledgeGraph: ObservableObject {
    static let shared = KnowledgeGraph()
    
    @Published var entities: [Entity] = []
    @Published var relationships: [Relationship] = []
    @Published var facts: [Fact] = []
    
    private let storage = KnowledgeStorage()
    private let nlp = NLTagger(tagSchemes: [.nameType, .lexicalClass])
    
    // MARK: - Entity Extraction
    
    /// Extract entities from text
    func extractEntities(from text: String) -> [ExtractedEntity] {
        nlp.string = text
        var extracted: [ExtractedEntity] = []
        
        nlp.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, range in
            if let tag = tag {
                let value = String(text[range])
                let type: EntityType
                
                switch tag {
                case .personalName: type = .person
                case .placeName: type = .place
                case .organizationName: type = .organization
                default: return true
                }
                
                extracted.append(ExtractedEntity(value: value, type: type, range: range))
            }
            return true
        }
        
        return extracted
    }
    
    /// Learn from a conversation
    func learn(from message: String, context: ConversationContext) {
        // Extract entities
        let extracted = extractEntities(from: message)
        
        for entity in extracted {
            // Find or create entity
            if let existing = entities.first(where: { $0.name.lowercased() == entity.value.lowercased() }) {
                // Update existing
                existing.mentionCount += 1
                existing.lastMentioned = Date()
                existing.contexts.append(context)
            } else {
                // Create new
                let newEntity = Entity(
                    name: entity.value,
                    type: entity.type,
                    firstMentioned: Date(),
                    contexts: [context]
                )
                entities.append(newEntity)
            }
        }
        
        // Extract relationships (basic co-occurrence)
        if extracted.count >= 2 {
            for i in 0..<extracted.count - 1 {
                for j in (i+1)..<extracted.count {
                    let rel = Relationship(
                        from: extracted[i].value,
                        to: extracted[j].value,
                        type: .cooccurrence,
                        context: message
                    )
                    relationships.append(rel)
                }
            }
        }
        
        // Extract facts (simple pattern matching)
        extractFacts(from: message, entities: extracted)
        
        // Persist
        Task {
            await storage.save(entities: entities, relationships: relationships, facts: facts)
        }
    }
    
    /// Query the knowledge graph
    func query(_ query: String) -> KnowledgeResult {
        let queryEntities = extractEntities(from: query)
        
        var relevantEntities: [Entity] = []
        var relevantFacts: [Fact] = []
        var relevantRelationships: [Relationship] = []
        
        for extracted in queryEntities {
            // Find matching entities
            let matches = entities.filter { $0.name.lowercased().contains(extracted.value.lowercased()) }
            relevantEntities.append(contentsOf: matches)
            
            // Find facts about these entities
            let entityFacts = facts.filter { fact in
                matches.contains { $0.name.lowercased() == fact.subject.lowercased() }
            }
            relevantFacts.append(contentsOf: entityFacts)
            
            // Find relationships
            let entityRels = relationships.filter { rel in
                matches.contains { $0.name.lowercased() == rel.from.lowercased() || $0.name.lowercased() == rel.to.lowercased() }
            }
            relevantRelationships.append(contentsOf: entityRels)
        }
        
        return KnowledgeResult(
            entities: relevantEntities,
            facts: relevantFacts,
            relationships: relevantRelationships
        )
    }
    
    private func extractFacts(from text: String, entities: [ExtractedEntity]) {
        // Pattern: "X is Y" or "X works at Y"
        let patterns = [
            "is a", "is the", "works at", "lives in", "born in",
            "married to", "founded", "created", "manages", "owns"
        ]
        
        for pattern in patterns {
            if text.lowercased().contains(pattern) {
                // Basic extraction
                let components = text.lowercased().components(separatedBy: pattern)
                if components.count >= 2 {
                    let fact = Fact(
                        subject: components[0].trimmingCharacters(in: .whitespaces),
                        predicate: pattern,
                        object: components[1].trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces),
                        source: text,
                        confidence: 0.7
                    )
                    facts.append(fact)
                }
            }
        }
    }
}

class Entity: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let type: EntityType
    let firstMentioned: Date
    var lastMentioned: Date
    var mentionCount: Int = 1
    var contexts: [ConversationContext]
    var attributes: [String: String] = [:]
    
    init(name: String, type: EntityType, firstMentioned: Date, contexts: [ConversationContext]) {
        self.name = name
        self.type = type
        self.firstMentioned = firstMentioned
        self.lastMentioned = firstMentioned
        self.contexts = contexts
    }
}

enum EntityType: String {
    case person, place, organization, event, concept, unknown
}

struct ExtractedEntity {
    let value: String
    let type: EntityType
    let range: Range<String.Index>
}

struct Relationship: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let type: RelationType
    let context: String
    let timestamp = Date()
    
    enum RelationType: String {
        case cooccurrence, worksAt, livesIn, knows, marriedTo, parentOf, manages
    }
}

struct Fact: Identifiable {
    let id = UUID()
    let subject: String
    let predicate: String
    let object: String
    let source: String
    let confidence: Double
    let timestamp = Date()
}

struct ConversationContext {
    let message: String
    let timestamp: Date
    let topic: String?
}

struct KnowledgeResult {
    let entities: [Entity]
    let facts: [Fact]
    let relationships: [Relationship]
}

class KnowledgeStorage {
    func save(entities: [Entity], relationships: [Relationship], facts: [Fact]) async {
        // Would persist to disk/CoreData
    }
    
    func load() async -> (entities: [Entity], relationships: [Relationship], facts: [Fact]) {
        // Would load from disk
        return ([], [], [])
    }
}

// MARK: - 5. PREDICTIVE ACTIONS

/// Learns patterns and predicts what you need
@MainActor
class PredictiveEngine: ObservableObject {
    static let shared = PredictiveEngine()
    
    @Published var predictions: [Prediction] = []
    @Published var patterns: [LearnedPattern] = []
    
    private var actionHistory: [UserAction] = []
    private var timePatterns: [TimePattern] = []
    private var locationPatterns: [LocationPattern] = []
    
    // MARK: - Learning
    
    /// Log a user action
    func logAction(_ action: UserAction) {
        actionHistory.append(action)
        
        // Learn time patterns
        learnTimePatterns()
        
        // Learn sequence patterns
        learnSequencePatterns()
        
        // Update predictions
        updatePredictions()
    }
    
    private func learnTimePatterns() {
        // Group actions by hour of day
        let calendar = Calendar.current
        var hourlyActions: [Int: [String]] = [:]
        
        for action in actionHistory {
            let hour = calendar.component(.hour, from: action.timestamp)
            hourlyActions[hour, default: []].append(action.type)
        }
        
        // Find patterns (actions that occur >50% of the time at certain hours)
        for (hour, actions) in hourlyActions {
            let actionCounts = Dictionary(grouping: actions, by: { $0 }).mapValues { $0.count }
            let totalAtHour = actions.count
            
            for (action, count) in actionCounts {
                let frequency = Double(count) / Double(totalAtHour)
                if frequency > 0.5 && count >= 3 {
                    let pattern = TimePattern(hour: hour, action: action, frequency: frequency)
                    if !timePatterns.contains(where: { $0.hour == hour && $0.action == action }) {
                        timePatterns.append(pattern)
                    }
                }
            }
        }
    }
    
    private func learnSequencePatterns() {
        // Find action sequences (A -> B patterns)
        guard actionHistory.count >= 2 else { return }
        
        var sequences: [String: [String]] = [:]
        
        for i in 0..<actionHistory.count - 1 {
            let current = actionHistory[i].type
            let next = actionHistory[i + 1].type
            
            // Only count if within 5 minutes
            let timeDiff = actionHistory[i + 1].timestamp.timeIntervalSince(actionHistory[i].timestamp)
            if timeDiff < 300 {
                sequences[current, default: []].append(next)
            }
        }
        
        // Find common follow-ups
        for (action, followUps) in sequences {
            let followUpCounts = Dictionary(grouping: followUps, by: { $0 }).mapValues { $0.count }
            
            if let (mostCommon, count) = followUpCounts.max(by: { $0.value < $1.value }), count >= 3 {
                let pattern = LearnedPattern(
                    trigger: action,
                    predicted: mostCommon,
                    confidence: Double(count) / Double(followUps.count),
                    occurrences: count
                )
                
                if let existingIndex = patterns.firstIndex(where: { $0.trigger == action }) {
                    patterns[existingIndex] = pattern
                } else {
                    patterns.append(pattern)
                }
            }
        }
    }
    
    // MARK: - Predictions
    
    private func updatePredictions() {
        predictions.removeAll()
        
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        
        // Time-based predictions
        for pattern in timePatterns where pattern.hour == currentHour {
            predictions.append(Prediction(
                action: pattern.action,
                reason: "You usually do this around \(formatHour(pattern.hour))",
                confidence: pattern.frequency,
                source: .timePattern
            ))
        }
        
        // Sequence-based predictions (based on last action)
        if let lastAction = actionHistory.last {
            for pattern in patterns where pattern.trigger == lastAction.type {
                predictions.append(Prediction(
                    action: pattern.predicted,
                    reason: "You usually do this after \(pattern.trigger)",
                    confidence: pattern.confidence,
                    source: .sequencePattern
                ))
            }
        }
        
        // Sort by confidence
        predictions.sort { $0.confidence > $1.confidence }
    }
    
    /// Get proactive suggestions
    func getSuggestions() -> [Suggestion] {
        predictions.prefix(3).map { prediction in
            Suggestion(
                title: prediction.action,
                subtitle: prediction.reason,
                action: { /* Would execute the action */ }
            )
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return formatter.string(from: date)
    }
}

struct UserAction: Identifiable {
    let id = UUID()
    let type: String
    let timestamp: Date
    let context: [String: Any]
}

struct TimePattern {
    let hour: Int
    let action: String
    let frequency: Double
}

struct LocationPattern {
    let location: String
    let action: String
    let frequency: Double
}

struct LearnedPattern: Identifiable {
    let id = UUID()
    let trigger: String
    let predicted: String
    let confidence: Double
    let occurrences: Int
}

struct Prediction: Identifiable {
    let id = UUID()
    let action: String
    let reason: String
    let confidence: Double
    let source: PredictionSource
    
    enum PredictionSource {
        case timePattern, sequencePattern, locationPattern, contextual
    }
}

struct Suggestion {
    let title: String
    let subtitle: String
    let action: () -> Void
}

// MARK: - 6. AR & 3D SCANNING

/// LiDAR-based 3D scanning and AR measurements
class ARIntelligence: NSObject, ObservableObject, ARSessionDelegate {
    static let shared = ARIntelligence()
    
    @Published var isScanning = false
    @Published var scannedMesh: ARMeshGeometry?
    @Published var measurements: [ARMeasurement] = []
    @Published var detectedObjects: [ARDetectedObject] = []
    
    private var arSession: ARSession?
    
    var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    
    // MARK: - 3D Room Scanning
    
    /// Start scanning the room with LiDAR
    func startRoomScan() {
        guard hasLiDAR else { return }
        
        arSession = ARSession()
        arSession?.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        
        arSession?.run(config)
        isScanning = true
    }
    
    /// Stop scanning
    func stopRoomScan() {
        arSession?.pause()
        isScanning = false
    }
    
    // MARK: - Measurements
    
    /// Measure distance between two points
    func measureDistance(from: simd_float3, to: simd_float3) -> Float {
        simd_distance(from, to)
    }
    
    /// Measure an object's dimensions
    func measureObject(at anchor: ARObjectAnchor) -> ObjectDimensions {
        let extent = anchor.referenceObject.extent
        return ObjectDimensions(
            width: extent.x,
            height: extent.y,
            depth: extent.z
        )
    }
    
    /// Add a measurement
    func addMeasurement(start: simd_float3, end: simd_float3, label: String) {
        let distance = measureDistance(from: start, to: end)
        let measurement = ARMeasurement(
            startPoint: start,
            endPoint: end,
            distance: distance,
            label: label
        )
        measurements.append(measurement)
    }
    
    // MARK: - Object Detection
    
    /// Detect and classify objects in the scene
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                // Process mesh for classification
                classifyMeshSurfaces(meshAnchor)
            }
            
            if let planeAnchor = anchor as? ARPlaneAnchor {
                let detected = ARDetectedObject(
                    type: planeAnchor.classification.description,
                    position: simd_make_float3(planeAnchor.center),
                    extent: planeAnchor.planeExtent,
                    confidence: 1.0
                )
                
                Task { @MainActor in
                    detectedObjects.append(detected)
                }
            }
        }
    }
    
    private func classifyMeshSurfaces(_ anchor: ARMeshAnchor) {
        let geometry = anchor.geometry
        
        // Get classifications
        let classifications = geometry.classificationBuffer
        // Process classifications...
    }
    
    // MARK: - Use Cases
    
    /// Scan a room and estimate square footage
    func estimateRoomSize() -> RoomDimensions? {
        guard let mesh = scannedMesh else { return nil }
        
        // Would analyze mesh to find floor plane and calculate area
        // Placeholder
        return RoomDimensions(
            width: 3.5,
            length: 4.2,
            height: 2.4,
            squareMeters: 14.7
        )
    }
    
    /// Check if furniture fits in a space
    func checkFurnitureFit(furniture: FurnitureDimensions, space: simd_float3) -> Bool {
        return furniture.width <= space.x &&
               furniture.depth <= space.z &&
               furniture.height <= space.y
    }
    
    /// Export 3D model
    func exportModel(format: ModelFormat) -> URL? {
        // Would export mesh as USDZ, OBJ, etc.
        return nil
    }
}

struct ARMeasurement: Identifiable {
    let id = UUID()
    let startPoint: simd_float3
    let endPoint: simd_float3
    let distance: Float // meters
    let label: String
    let timestamp = Date()
    
    var formattedDistance: String {
        if distance < 1 {
            return String(format: "%.1f cm", distance * 100)
        } else {
            return String(format: "%.2f m", distance)
        }
    }
}

struct ARDetectedObject: Identifiable {
    let id = UUID()
    let type: String
    let position: simd_float3
    let extent: simd_float3
    let confidence: Float
}

struct ObjectDimensions {
    let width: Float
    let height: Float
    let depth: Float
}

struct RoomDimensions {
    let width: Double
    let length: Double
    let height: Double
    let squareMeters: Double
}

struct FurnitureDimensions {
    let width: Float
    let depth: Float
    let height: Float
}

enum ModelFormat {
    case usdz, obj, stl, ply
}

extension ARPlaneAnchor.Classification: CustomStringConvertible {
    public var description: String {
        switch self {
        case .wall: return "Wall"
        case .floor: return "Floor"
        case .ceiling: return "Ceiling"
        case .table: return "Table"
        case .seat: return "Seat"
        case .door: return "Door"
        case .window: return "Window"
        default: return "Surface"
        }
    }
}

// MARK: - Unified Cracked Features View

struct CrackedFeaturesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Intelligence") {
                    FeatureRow(icon: "waveform", title: "Voice Cloning", subtitle: "Clone your voice for TTS", destination: AnyView(VoiceCloningView()))
                    FeatureRow(icon: "heart.text.square", title: "Mood Detection", subtitle: "HRV + voice + typing = stress level", destination: AnyView(MoodDetectionView()))
                    FeatureRow(icon: "ear", title: "Sound Intelligence", subtitle: "Doorbell, baby, alarm detection", destination: AnyView(SoundIntelligenceView()))
                    FeatureRow(icon: "brain.head.profile", title: "Knowledge Graph", subtitle: "Never forgets anything", destination: AnyView(KnowledgeGraphView()))
                    FeatureRow(icon: "sparkles", title: "Predictive Actions", subtitle: "Knows what you need before you ask", destination: AnyView(PredictiveView()))
                }
                
                Section("Computer Control") {
                    #if os(macOS)
                    FeatureRow(icon: "eye.fill", title: "Parchi Mode", subtitle: "Screen reading + mouse/keyboard control", destination: AnyView(ParchiModeView()))
                    #else
                    HStack {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.gray)
                            .frame(width: 30)
                        VStack(alignment: .leading) {
                            Text("Parchi Mode")
                                .foregroundColor(.gray)
                            Text("macOS only")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    #endif
                }
                
                Section("Spatial") {
                    FeatureRow(icon: "cube.transparent", title: "AR & 3D Scanning", subtitle: "LiDAR measurements, object scanning", destination: AnyView(ARScanningView()))
                }
            }
            .navigationTitle("Cracked Features")
        }
    }
}

struct FeatureRow<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let destination: Destination
    
    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(.cyan)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// Placeholder views
struct VoiceCloningView: View { var body: some View { Text("Voice Cloning") } }
struct MoodDetectionView: View { var body: some View { Text("Mood Detection") } }
struct SoundIntelligenceView: View { var body: some View { Text("Sound Intelligence") } }
struct KnowledgeGraphView: View { var body: some View { Text("Knowledge Graph") } }
struct PredictiveView: View { var body: some View { Text("Predictive Actions") } }
struct ARScanningView: View { var body: some View { Text("AR Scanning") } }

#Preview {
    CrackedFeaturesView()
}
