// MeshAnomalyDetector.swift — Mesh Traffic Anomaly Detection
// Detects suspicious patterns: floods, entropy spikes, rapid join/leave

import Foundation
import Combine

// MARK: - Anomaly Detection Types

enum MeshAlertType: String, Codable {
    case floodDetected = "Flood Detection"
    case unknownPeer = "Unknown Peer"
    case highEntropy = "High Entropy"
    case rapidJoinLeave = "Rapid Join/Leave"
    case signatureMismatch = "Signature Mismatch"
    case staleData = "Stale Data"
}

struct MeshAlert: Identifiable, Codable {
    let id: UUID
    let type: MeshAlertType
    let peerId: String
    let description: String
    let timestamp: Date
    let severityLevel: Int  // 0-4 matching ThreatLevel raw values
    
    var severity: ThreatLevel {
        ThreatLevel(rawValue: severityLevel) ?? .medium
    }
    
    init(type: MeshAlertType, peerId: String, description: String, severity: ThreatLevel) {
        self.id = UUID()
        self.type = type
        self.peerId = peerId
        self.description = description
        self.timestamp = Date()
        self.severityLevel = severity.rawValue
    }
}

@MainActor
final class MeshAnomalyDetector: ObservableObject {
    static let shared = MeshAnomalyDetector()
    
    @Published var alerts: [MeshAlert] = []
    @Published var suspiciousPeers: Set<String> = []
    @Published var isMonitoring = false
    
    private var messageCountByPeer: [String: (count: Int, windowStart: Date)] = [:]
    private var peerFirstSeen: [String: Date] = [:]
    private var peerLastSeen: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Thresholds
    private let floodThreshold = 10  // messages per second
    private let entropyThreshold: Double = 7.9  // bits per byte (max is 8)
    private let rapidJoinLeaveWindow: TimeInterval = 30
    private let maxAlerts = 100
    
    private init() {}
    
    // MARK: - Public API
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Subscribe to MeshService messages
        MeshService.shared.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.analyzeMessages(messages)
            }
            .store(in: &cancellables)
        
        // Subscribe to peer changes
        MeshService.shared.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.analyzePeerChanges(peers)
            }
            .store(in: &cancellables)
    }
    
    func stopMonitoring() {
        isMonitoring = false
        cancellables.removeAll()
    }
    
    func clearAlerts() {
        alerts.removeAll()
        suspiciousPeers.removeAll()
    }
    
    // MARK: - Analysis
    
    private func analyzeMessages(_ messages: [MeshService.DecryptedMessage]) {
        guard let latest = messages.last else { return }
        
        let senderId = latest.senderId
        let now = Date()
        
        // Flood detection
        var peerData = messageCountByPeer[senderId] ?? (count: 0, windowStart: now)
        
        if now.timeIntervalSince(peerData.windowStart) > 1.0 {
            // New window
            peerData = (count: 1, windowStart: now)
        } else {
            peerData.count += 1
        }
        
        messageCountByPeer[senderId] = peerData
        
        if peerData.count > floodThreshold {
            addAlert(MeshAlert(
                type: .floodDetected,
                peerId: senderId,
                description: "\(peerData.count) messages in 1 second",
                severity: .high
            ))
            suspiciousPeers.insert(senderId)
        }
        
        // Entropy analysis (detect encrypted/compressed/random data)
        let entropy = calculateEntropy(latest.content.data(using: .utf8) ?? Data())
        if entropy > entropyThreshold {
            addAlert(MeshAlert(
                type: .highEntropy,
                peerId: senderId,
                description: String(format: "Entropy %.2f bits/byte", entropy),
                severity: .medium
            ))
        }
    }
    
    private func analyzePeerChanges(_ peers: [ZDPeer]) {
        let now = Date()
        let currentPeerIds = Set(peers.map { $0.id })
        let knownPeerIds = Set(peerFirstSeen.keys)
        
        // New peers
        for peer in peers where !knownPeerIds.contains(peer.id) {
            peerFirstSeen[peer.id] = now
            
            // Check if this peer rapidly rejoined
            if let lastSeen = peerLastSeen[peer.id],
               now.timeIntervalSince(lastSeen) < rapidJoinLeaveWindow {
                addAlert(MeshAlert(
                    type: .rapidJoinLeave,
                    peerId: peer.id,
                    description: "Rejoined within \(Int(rapidJoinLeaveWindow))s",
                    severity: .low
                ))
            }
        }
        
        // Departed peers
        for knownId in knownPeerIds where !currentPeerIds.contains(knownId) {
            peerLastSeen[knownId] = now
        }
    }
    
    private func addAlert(_ alert: MeshAlert) {
        alerts.insert(alert, at: 0)
        
        // Trim old alerts
        if alerts.count > maxAlerts {
            alerts = Array(alerts.prefix(maxAlerts))
        }
    }
    
    // MARK: - Entropy Calculation
    
    private func calculateEntropy(_ data: Data) -> Double {
        guard !data.isEmpty else { return 0 }
        
        var frequency = [UInt8: Int]()
        for byte in data {
            frequency[byte, default: 0] += 1
        }
        
        let total = Double(data.count)
        var entropy: Double = 0
        
        for count in frequency.values {
            let p = Double(count) / total
            if p > 0 {
                entropy -= p * log2(p)
            }
        }
        
        return entropy
    }
    
    // MARK: - Status
    
    var floodDetectionCount: Int {
        alerts.filter { $0.type == .floodDetected }.count
    }
    
    var entropyAlertCount: Int {
        alerts.filter { $0.type == .highEntropy }.count
    }
    
    var joinLeaveAlertCount: Int {
        alerts.filter { $0.type == .rapidJoinLeave }.count
    }
}
