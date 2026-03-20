// ThreatAnalyzer.swift — AI-Powered Threat Assessment System
// Integrates with LiDAR, environmental sensors, and mesh network intel

import Foundation
import CoreML
import CoreLocation
import Combine
import simd

// MARK: - Threat Level

enum ThreatLevel: Int, Comparable, Codable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    static func < (lhs: ThreatLevel, rhs: ThreatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var color: String {
        switch self {
        case .none: return "green"
        case .low: return "blue"
        case .medium: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
    
    var description: String {
        switch self {
        case .none: return "Clear"
        case .low: return "Low Risk"
        case .medium: return "Elevated"
        case .high: return "High Risk"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Threat Types

enum ThreatCategory {
    case environmental   // Weather, terrain hazards
    case structural      // Building/infrastructure risks
    case human           // Personnel threats
    case electronic      // RF/signal threats
    case biological      // Wildlife, contamination
    case temporal        // Time-based risks (darkness, tides)
}

struct Threat: Identifiable {
    let id = UUID()
    let category: ThreatCategory
    let level: ThreatLevel
    let description: String
    let location: CLLocationCoordinate2D?
    let position3D: SIMD3<Float>?
    let confidence: Float
    let timestamp: Date
    let expiresAt: Date?
    let mitigation: [String]
    let source: ThreatSource
    
    enum ThreatSource {
        case lidarAnalysis
        case meshNetwork
        case environmentalSensor
        case rfDetection
        case userReport
        case predictiveModel
    }
}

// MARK: - Assessment Result

struct ThreatAssessment {
    let timestamp: Date
    let location: CLLocationCoordinate2D?
    let overallLevel: ThreatLevel
    let threats: [Threat]
    let safeZones: [SafeZone]
    let recommendations: [Recommendation]
    let environmentalConditions: EnvironmentalConditions
    let confidence: Float
    
    struct SafeZone {
        let center: SIMD3<Float>
        let radius: Float
        let protection: Float
        let egress: [SIMD3<Float>]
    }
    
    struct Recommendation {
        let priority: Int
        let action: String
        let reason: String
        let urgency: ThreatLevel
    }
}

struct EnvironmentalConditions {
    var visibility: Float  // 0-1
    var precipitation: Float
    var windSpeed: Float
    var temperature: Float
    var humidity: Float
    var lightLevel: Float  // 0-1
    var noiseLevel: Float  // dB
}

// MARK: - Threat Analyzer

@MainActor
final class ThreatAnalyzer: ObservableObject {
    static let shared = ThreatAnalyzer()
    
    // Published state
    @Published var currentAssessment: ThreatAssessment?
    @Published var isAnalyzing = false
    @Published var threatLevel: ThreatLevel = .none
    @Published var activeThreats: [Threat] = []
    @Published var alertMessage: String?
    
    // Data sources
    private var lidarEngine: LiDARCaptureEngine { LiDARCaptureEngine.shared }
    private var meshService: MeshService { MeshService.shared }
    
    // Analysis state
    private var threatHistory: [Threat] = []
    private var environmentalHistory: [EnvironmentalConditions] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Thresholds
    private let threatExpirationInterval: TimeInterval = 300  // 5 minutes
    private let reassessmentInterval: TimeInterval = 30  // 30 seconds
    
    private init() {
        setupSubscriptions()
        startPeriodicAssessment()
    }
    
    // MARK: - Setup
    
    private func setupSubscriptions() {
        // Subscribe to LiDAR updates
        lidarEngine.$lastScanResult
            .compactMap { $0 }
            .sink { [weak self] result in
                Task { @MainActor in
                    await self?.processLiDARResult(result)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to mesh network messages
        meshService.$messages
            .sink { [weak self] messages in
                Task { @MainActor in
                    self?.processMeshMessages(messages)
                }
            }
            .store(in: &cancellables)
    }
    
    private func startPeriodicAssessment() {
        Timer.publish(every: reassessmentInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.performAssessment()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Threat Injection

    func processNewThreat(_ threat: Threat) {
        // Allow external systems (like MeshAnomalyDetector) to inject threats
        activeThreats.append(threat)
        threatLevel = calculateOverallThreatLevel(activeThreats)

        // Trigger re-evaluation
        Task {
            await performAssessment()
        }
    }

    // MARK: - Assessment

    func performAssessment() async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        // Gather all threat data
        var threats: [Threat] = []
        
        // 1. Environmental threats
        let envConditions = gatherEnvironmentalConditions()
        threats.append(contentsOf: assessEnvironmentalThreats(envConditions))
        
        // 2. Structural threats (from LiDAR)
        if let lidarResult = lidarEngine.lastScanResult,
           let tacticalAnalysis = lidarResult.tacticalAnalysis {
            threats.append(contentsOf: assessStructuralThreats(tacticalAnalysis))
        }
        
        // 3. Network-reported threats
        threats.append(contentsOf: getNetworkReportedThreats())
        
        // 4. Predictive threats
        threats.append(contentsOf: predictThreats())
        
        // Remove expired threats
        let now = Date()
        activeThreats = threats.filter { threat in
            if let expires = threat.expiresAt {
                return expires > now
            }
            return true
        }
        
        // Calculate overall threat level
        threatLevel = calculateOverallThreatLevel(activeThreats)
        
        // Find safe zones
        let safeZones = identifySafeZones()
        
        // Generate recommendations
        let recommendations = generateRecommendations(threats: activeThreats, safeZones: safeZones)
        
        // Create assessment
        currentAssessment = ThreatAssessment(
            timestamp: now,
            location: nil,  // Would get from location manager
            overallLevel: threatLevel,
            threats: activeThreats,
            safeZones: safeZones,
            recommendations: recommendations,
            environmentalConditions: envConditions,
            confidence: calculateConfidence(threats: activeThreats)
        )
        
        // Check for alerts
        checkAlerts()
        
        // Store in history
        threatHistory.append(contentsOf: activeThreats)
        environmentalHistory.append(envConditions)
        
        // Trim history
        if threatHistory.count > 1000 {
            threatHistory.removeFirst(500)
        }
        if environmentalHistory.count > 100 {
            environmentalHistory.removeFirst(50)
        }
    }
    
    // MARK: - Data Gathering
    
    private func gatherEnvironmentalConditions() -> EnvironmentalConditions {
        // Gather data from available sensors and systems
        var conditions = EnvironmentalConditions(
            visibility: 0.8,
            precipitation: 0.0,
            windSpeed: 5.0,
            temperature: 22.0,
            humidity: 0.45,
            lightLevel: 0.9,
            noiseLevel: 40.0
        )

        // Terrain visibility from LiDAR
        if let lastScan = lidarEngine.lastScanResult,
           let terrain = lastScan.terrainAnalysis {
            // Compute average slope from slope regions
            let avgSlope = terrain.slope.isEmpty ? 0 : terrain.slope.map { $0.averageSlope }.reduce(0, +) / Float(terrain.slope.count)
            // Steeper terrain = lower visibility (more obstructions)
            conditions.visibility = Float(max(0.3, 1.0 - (avgSlope / 45.0)))
        }

        // Mesh network health affects communication visibility
        let meshPeerCount = Float(meshService.peers.count)
        let meshConnection: Float = meshService.peers.count > 0 ? 0.9 : 0.5
        // More peers = better situational awareness
        conditions.lightLevel = min(1.0, meshConnection + (meshPeerCount / 20.0))

        // Anomaly detector provides signal/noise info
        let anomalyAlerts = MeshAnomalyDetector.shared.alerts
        if !anomalyAlerts.isEmpty {
            // High alert count = noisy environment
            let alertCount = Float(anomalyAlerts.count)
            conditions.noiseLevel = min(100.0, 40.0 + (alertCount * 5.0))
        }

        // Check for critical mesh anomalies affecting environmental assessment
        for alert in anomalyAlerts {
            switch alert.type {
            case .floodDetected:
                // Flood detection indicates network stress
                conditions.noiseLevel = min(100.0, conditions.noiseLevel + 10.0)
            case .highEntropy:
                // High entropy suggests jamming or interference
                conditions.visibility = min(conditions.visibility - 0.1, 0.3)
            case .rapidJoinLeave:
                // Instability suggests dynamic threats
                conditions.precipitation += 0.1  // Metaphorical "noise"
            default:
                break
            }
        }

        return conditions
    }
    
    private func processLiDARResult(_ result: LiDARScanResult) async {
        // Trigger reassessment when new LiDAR data arrives
        await performAssessment()
    }
    
    private func processMeshMessages(_ messages: [MeshService.DecryptedMessage]) {
        for message in messages {
            if message.type == .sos {
                // Immediate threat from SOS
                let threat = Threat(
                    category: .human,
                    level: .critical,
                    description: "SOS signal received from \(message.senderName)",
                    location: nil,
                    position3D: nil,
                    confidence: 1.0,
                    timestamp: message.timestamp,
                    expiresAt: message.timestamp.addingTimeInterval(600),
                    mitigation: ["Respond to SOS", "Establish communication", "Assess situation"],
                    source: .meshNetwork
                )
                activeThreats.append(threat)
                alertMessage = "SOS RECEIVED: \(message.senderName)"
            }
            
            if message.type == .intel {
                // Parse intel for threat indicators
                parseIntelMessage(message)
            }
        }
    }
    
    private func parseIntelMessage(_ message: MeshService.DecryptedMessage) {
        let content = message.content.lowercased()
        
        // Simple keyword detection
        let threatKeywords = ["threat", "danger", "hostile", "warning", "alert", "caution"]
        
        if threatKeywords.contains(where: { content.contains($0) }) {
            let threat = Threat(
                category: .human,
                level: .medium,
                description: "Intel report: \(message.content)",
                location: nil,
                position3D: nil,
                confidence: 0.6,
                timestamp: message.timestamp,
                expiresAt: message.timestamp.addingTimeInterval(300),
                mitigation: ["Monitor situation", "Maintain awareness"],
                source: .meshNetwork
            )
            activeThreats.append(threat)
        }
    }
    
    // MARK: - Threat Assessment
    
    private func assessEnvironmentalThreats(_ conditions: EnvironmentalConditions) -> [Threat] {
        var threats: [Threat] = []
        
        // Low visibility
        if conditions.visibility < 0.3 {
            threats.append(Threat(
                category: .environmental,
                level: conditions.visibility < 0.1 ? .high : .medium,
                description: "Reduced visibility: \(Int(conditions.visibility * 100))%",
                location: nil,
                position3D: nil,
                confidence: 0.9,
                timestamp: Date(),
                expiresAt: Date().addingTimeInterval(300),
                mitigation: ["Use alternative navigation", "Reduce speed", "Increase spacing"],
                source: .environmentalSensor
            ))
        }
        
        // High wind
        if conditions.windSpeed > 30 {
            threats.append(Threat(
                category: .environmental,
                level: conditions.windSpeed > 50 ? .high : .medium,
                description: "High wind: \(Int(conditions.windSpeed)) m/s",
                location: nil,
                position3D: nil,
                confidence: 0.9,
                timestamp: Date(),
                expiresAt: Date().addingTimeInterval(300),
                mitigation: ["Seek shelter", "Secure equipment", "Avoid exposed areas"],
                source: .environmentalSensor
            ))
        }
        
        // Low light
        if conditions.lightLevel < 0.2 {
            threats.append(Threat(
                category: .temporal,
                level: .low,
                description: "Low light conditions",
                location: nil,
                position3D: nil,
                confidence: 0.95,
                timestamp: Date(),
                expiresAt: Date().addingTimeInterval(3600),
                mitigation: ["Use night vision aids", "Move cautiously", "Mark position"],
                source: .environmentalSensor
            ))
        }
        
        return threats
    }
    
    private func assessStructuralThreats(_ analysis: TacticalAnalysis) -> [Threat] {
        var threats: [Threat] = []
        
        // Threat vectors from tactical analysis
        for vector in analysis.threatVectors {
            let level: ThreatLevel
            switch vector.probability {
            case 0..<0.3: level = .low
            case 0.3..<0.6: level = .medium
            case 0.6..<0.8: level = .high
            default: level = .critical
            }
            
            threats.append(Threat(
                category: .structural,
                level: level,
                description: "Threat vector identified: \(vector.type)",
                location: nil,
                position3D: vector.origin,
                confidence: vector.probability,
                timestamp: Date(),
                expiresAt: Date().addingTimeInterval(600),
                mitigation: ["Avoid exposure", "Use cover", "Monitor direction"],
                source: .lidarAnalysis
            ))
        }
        
        // High risk areas
        if analysis.riskScore > 0.7 {
            threats.append(Threat(
                category: .structural,
                level: .high,
                description: "High risk area detected (score: \(Int(analysis.riskScore * 100))%)",
                location: nil,
                position3D: nil,
                confidence: analysis.riskScore,
                timestamp: Date(),
                expiresAt: Date().addingTimeInterval(600),
                mitigation: [
                    "Consider alternative route",
                    "Increase security posture",
                    "Maintain cover"
                ],
                source: .lidarAnalysis
            ))
        }
        
        return threats
    }
    
    private func getNetworkReportedThreats() -> [Threat] {
        // Get threats reported by mesh network peers
        // Would be populated from mesh messages
        return []
    }
    
    private func predictThreats() -> [Threat] {
        var predictions: [Threat] = []
        
        // Time-based predictions
        let hour = Calendar.current.component(.hour, from: Date())
        
        if hour >= 18 || hour < 6 {
            // Night time
            predictions.append(Threat(
                category: .temporal,
                level: .low,
                description: "Night operations - reduced visibility expected",
                location: nil,
                position3D: nil,
                confidence: 0.8,
                timestamp: Date(),
                expiresAt: nil,
                mitigation: ["Plan for limited visibility", "Use night aids"],
                source: .predictiveModel
            ))
        }
        
        // Pattern-based predictions from history
        if threatHistory.filter({ $0.category == .human }).count > 5 {
            let recentHumanThreats = threatHistory.filter {
                $0.category == .human && $0.timestamp > Date().addingTimeInterval(-3600)
            }
            
            if recentHumanThreats.count >= 3 {
                predictions.append(Threat(
                    category: .human,
                    level: .medium,
                    description: "Pattern detected: Increased activity in area",
                    location: nil,
                    position3D: nil,
                    confidence: 0.6,
                    timestamp: Date(),
                    expiresAt: Date().addingTimeInterval(1800),
                    mitigation: ["Increase vigilance", "Consider repositioning"],
                    source: .predictiveModel
                ))
            }
        }
        
        return predictions
    }
    
    // MARK: - Analysis
    
    private func calculateOverallThreatLevel(_ threats: [Threat]) -> ThreatLevel {
        guard !threats.isEmpty else { return .none }
        
        // Use highest threat level, weighted by confidence
        var maxLevel: ThreatLevel = .none
        
        for threat in threats {
            if threat.level > maxLevel && threat.confidence > 0.5 {
                maxLevel = threat.level
            }
        }
        
        // Elevate if multiple medium threats
        let mediumCount = threats.filter { $0.level == .medium }.count
        if mediumCount >= 3 && maxLevel == .medium {
            maxLevel = .high
        }
        
        return maxLevel
    }
    
    private func identifySafeZones() -> [ThreatAssessment.SafeZone] {
        var safeZones: [ThreatAssessment.SafeZone] = []
        
        // Get cover positions from LiDAR analysis
        if let lidarResult = lidarEngine.lastScanResult,
           let terrainAnalysis = lidarResult.terrainAnalysis {
            
            for cover in terrainAnalysis.coverPositions where cover.protection > 0.6 {
                safeZones.append(ThreatAssessment.SafeZone(
                    center: cover.center,
                    radius: 2.0,
                    protection: cover.protection,
                    egress: cover.exposedDirections.map { -$0 * 5 + cover.center }
                ))
            }
        }
        
        return safeZones
    }
    
    private func generateRecommendations(threats: [Threat], safeZones: [ThreatAssessment.SafeZone]) -> [ThreatAssessment.Recommendation] {
        var recommendations: [ThreatAssessment.Recommendation] = []
        
        // Critical threat responses
        let criticalThreats = threats.filter { $0.level == .critical }
        if !criticalThreats.isEmpty {
            recommendations.append(ThreatAssessment.Recommendation(
                priority: 1,
                action: "Immediate action required",
                reason: "Critical threat level detected",
                urgency: .critical
            ))
            
            if !safeZones.isEmpty {
                recommendations.append(ThreatAssessment.Recommendation(
                    priority: 2,
                    action: "Move to nearest safe zone",
                    reason: "\(safeZones.count) protected positions identified",
                    urgency: .high
                ))
            }
        }
        
        // High threat responses
        let highThreats = threats.filter { $0.level == .high }
        if !highThreats.isEmpty {
            recommendations.append(ThreatAssessment.Recommendation(
                priority: 3,
                action: "Increase security posture",
                reason: "\(highThreats.count) high-level threats detected",
                urgency: .high
            ))
        }
        
        // Environmental recommendations
        let envThreats = threats.filter { $0.category == .environmental }
        for threat in envThreats {
            for mitigation in threat.mitigation.prefix(2) {
                recommendations.append(ThreatAssessment.Recommendation(
                    priority: 4,
                    action: mitigation,
                    reason: threat.description,
                    urgency: threat.level
                ))
            }
        }
        
        // General recommendations
        if recommendations.isEmpty {
            recommendations.append(ThreatAssessment.Recommendation(
                priority: 10,
                action: "Maintain situational awareness",
                reason: "No significant threats detected",
                urgency: .low
            ))
        }
        
        return recommendations.sorted { $0.priority < $1.priority }
    }
    
    private func calculateConfidence(threats: [Threat]) -> Float {
        guard !threats.isEmpty else { return 1.0 }
        
        let avgConfidence = threats.reduce(0.0) { $0 + $1.confidence } / Float(threats.count)
        return avgConfidence
    }
    
    private func checkAlerts() {
        // Check for alert conditions
        if threatLevel >= .high {
            let highThreats = activeThreats.filter { $0.level >= .high }
            if let mostSerious = highThreats.first {
                alertMessage = mostSerious.description
            }
        } else {
            alertMessage = nil
        }
    }
    
    // MARK: - Public Interface
    
    func reportThreat(category: ThreatCategory, level: ThreatLevel, description: String, position: SIMD3<Float>? = nil) {
        let threat = Threat(
            category: category,
            level: level,
            description: description,
            location: nil,
            position3D: position,
            confidence: 0.9,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(600),
            mitigation: ["User reported threat - assess situation"],
            source: .userReport
        )
        
        activeThreats.append(threat)
        
        // Share with mesh network
        meshService.shareIntel("THREAT: \(level.description) - \(description)")
        
        // Trigger reassessment
        Task {
            await performAssessment()
        }
    }
    
    func clearThreat(_ id: UUID) {
        activeThreats.removeAll { $0.id == id }
        
        // Recalculate threat level
        threatLevel = calculateOverallThreatLevel(activeThreats)
    }
    
    func getThreatsNear(position: SIMD3<Float>, radius: Float) -> [Threat] {
        return activeThreats.filter { threat in
            guard let threatPos = threat.position3D else { return false }
            return length(threatPos - position) <= radius
        }
    }
}
