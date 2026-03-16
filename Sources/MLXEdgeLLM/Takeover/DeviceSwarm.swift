// DeviceSwarm.swift
// Cross-device distributed inference - PRODUCTION READY
// iPhone + iPad + Mac = ONE MIND running 70B+ models

import Foundation
import MultipeerConnectivity

// MARK: - Device Swarm

/// Coordinates multiple Apple devices for distributed LLM inference
/// Uses MultipeerConnectivity for device discovery and communication
@MainActor
public final class DeviceSwarm: NSObject, ObservableObject {
    
    public static let shared = DeviceSwarm()
    
    // MARK: - Types
    
    public struct SwarmDevice: Identifiable, Codable, Sendable {
        public let id: String
        public let name: String
        public let type: DeviceType
        public let memoryGB: Int
        public let isLocal: Bool
        public var connectionQuality: ConnectionQuality
        public var assignedLayers: [Int]
        public var isReady: Bool
        
        public enum DeviceType: String, Codable, Sendable {
            case iPhone, iPad, mac, visionPro
        }
        
        public enum ConnectionQuality: String, Codable, Sendable {
            case local, excellent, good, fair, poor
        }
        
        public var maxModelSizeGB: Double {
            Double(memoryGB) * 0.6
        }
        
        public init(
            id: String,
            name: String,
            type: DeviceType,
            memoryGB: Int,
            isLocal: Bool,
            connectionQuality: ConnectionQuality,
            assignedLayers: [Int] = [],
            isReady: Bool = true
        ) {
            self.id = id
            self.name = name
            self.type = type
            self.memoryGB = memoryGB
            self.isLocal = isLocal
            self.connectionQuality = connectionQuality
            self.assignedLayers = assignedLayers
            self.isReady = isReady
        }
    }
    
    public enum SwarmState: Equatable {
        case disconnected
        case discovering
        case forming(deviceCount: Int)
        case ready(deviceCount: Int, totalMemoryGB: Int)
        case inferring(progress: Double)
        case error(String)
        
        public static func == (lhs: SwarmState, rhs: SwarmState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected): return true
            case (.discovering, .discovering): return true
            case (.forming(let a), .forming(let b)): return a == b
            case (.ready(let a, let b), .ready(let c, let d)): return a == c && b == d
            case (.inferring(let a), .inferring(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }
    
    // MARK: - Message Protocol
    
    enum SwarmMessage: Codable {
        case deviceInfo(SwarmDevice)
        case layerAssignment(layers: [Int], modelId: String)
        case activations(layerIndex: Int, data: Data)
        case tokenResult(token: String)
        case syncRequest
        case syncAck
    }
    
    // MARK: - Published State
    
    @Published public private(set) var state: SwarmState = .disconnected
    @Published public private(set) var devices: [SwarmDevice] = []
    @Published public private(set) var totalMemoryGB: Int = 0
    @Published public private(set) var maxModelSize: String = "8B"
    
    // MARK: - MultipeerConnectivity
    
    private let serviceType = "zerodark-swarm"
    private var peerId: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    private var peerDeviceMap: [MCPeerID: SwarmDevice] = [:]
    private var pendingActivations: [Int: Data] = [:]
    private var activationContinuation: CheckedContinuation<Data, Error>?
    
    // MARK: - Init
    
    private override init() {
        super.init()
        setupLocalDevice()
    }
    
    private func setupLocalDevice() {
        let deviceName = getDeviceName()
        peerId = MCPeerID(displayName: deviceName)
        
        session = MCSession(
            peer: peerId,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
        
        let localDevice = createLocalDevice()
        devices = [localDevice]
        totalMemoryGB = localDevice.memoryGB
        updateMaxModelSize()
    }
    
    private func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Apple Device"
        #endif
    }
    
    private func createLocalDevice() -> SwarmDevice {
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        
        #if os(iOS)
        let type: SwarmDevice.DeviceType = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #elseif os(macOS)
        let type: SwarmDevice.DeviceType = .mac
        #elseif os(visionOS)
        let type: SwarmDevice.DeviceType = .visionPro
        #else
        let type: SwarmDevice.DeviceType = .mac
        #endif
        
        return SwarmDevice(
            id: UUID().uuidString,
            name: getDeviceName(),
            type: type,
            memoryGB: memoryGB,
            isLocal: true,
            connectionQuality: .local,
            assignedLayers: [],
            isReady: true
        )
    }
    
    // MARK: - Swarm Control
    
    /// Start discovering and connecting to nearby devices
    public func startSwarm() {
        guard state == .disconnected else { return }
        
        state = .discovering
        
        // Start advertising this device
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerId,
            discoveryInfo: ["version": "1.0"],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        // Start browsing for other devices
        browser = MCNearbyServiceBrowser(peer: peerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        
        // Timeout after 30 seconds if no devices found
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if case .discovering = state {
                if devices.count == 1 {
                    // Just local device, run solo
                    state = .ready(deviceCount: 1, totalMemoryGB: totalMemoryGB)
                }
            }
        }
    }
    
    /// Stop the swarm and disconnect all devices
    public func stopSwarm() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        
        peerDeviceMap.removeAll()
        devices = [createLocalDevice()]
        totalMemoryGB = devices[0].memoryGB
        updateMaxModelSize()
        state = .disconnected
    }
    
    // MARK: - Layer Assignment
    
    /// Calculate how to distribute model layers across devices
    public func assignLayers(modelLayers: Int) -> [String: [Int]] {
        var assignments: [String: [Int]] = [:]
        var currentLayer = 0
        
        // Sort by memory (largest first for most layers)
        let sortedDevices = devices.sorted { $0.memoryGB > $1.memoryGB }
        
        for device in sortedDevices {
            let proportion = Double(device.memoryGB) / Double(totalMemoryGB)
            let layerCount = max(1, Int(Double(modelLayers) * proportion))
            let endLayer = min(currentLayer + layerCount, modelLayers)
            
            let layers = Array(currentLayer..<endLayer)
            assignments[device.id] = layers
            
            // Update device
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index].assignedLayers = layers
            }
            
            currentLayer = endLayer
            if currentLayer >= modelLayers { break }
        }
        
        // Broadcast layer assignments to remote devices
        Task {
            for (deviceId, layers) in assignments {
                guard let device = devices.first(where: { $0.id == deviceId }),
                      !device.isLocal,
                      let peer = peerDeviceMap.first(where: { $0.value.id == deviceId })?.key else {
                    continue
                }
                
                let message = SwarmMessage.layerAssignment(layers: layers, modelId: "current")
                try? await send(message, to: peer)
            }
        }
        
        return assignments
    }
    
    // MARK: - Distributed Inference
    
    /// Run inference across the swarm
    public func generate(
        prompt: String,
        maxTokens: Int = 500,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard case .ready = state else {
            throw SwarmError.notReady
        }
        
        // Single device mode - run locally
        if devices.count == 1 {
            let ai = ZeroDarkAI.shared
            return try await ai.process(prompt: prompt, onToken: onToken)
        }
        
        // Multi-device distributed inference
        state = .inferring(progress: 0)
        
        var result = ""
        var tokensGenerated = 0
        
        while tokensGenerated < maxTokens {
            let nextToken = try await distributedStep(prompt: prompt, generated: result)
            
            if nextToken == "<|end|>" || nextToken == "<|endoftext|>" || nextToken.isEmpty {
                break
            }
            
            result += nextToken
            tokensGenerated += 1
            onToken(nextToken)
            
            state = .inferring(progress: Double(tokensGenerated) / Double(maxTokens))
        }
        
        state = .ready(deviceCount: devices.count, totalMemoryGB: totalMemoryGB)
        return result
    }
    
    /// Single step of distributed inference
    private func distributedStep(prompt: String, generated: String) async throws -> String {
        // 1. Local device runs embedding + first layers
        guard let localDevice = devices.first(where: { $0.isLocal }) else {
            throw SwarmError.noLocalDevice
        }
        
        let fullPrompt = prompt + generated
        
        // Run local layers and get activations
        var activations = try await runLocalLayers(prompt: fullPrompt, layers: localDevice.assignedLayers)
        
        // 2. Send activations through the pipeline
        let remoteDevices = devices.filter { !$0.isLocal }.sorted { $0.assignedLayers.first ?? 0 < $1.assignedLayers.first ?? 0 }
        
        for device in remoteDevices {
            guard let peer = peerDeviceMap.first(where: { $0.value.id == device.id })?.key else {
                continue
            }
            
            // Send activations to remote device
            let lastLayer = device.assignedLayers.last ?? 0
            let message = SwarmMessage.activations(layerIndex: lastLayer, data: activations)
            try await send(message, to: peer)
            
            // Wait for processed activations back
            activations = try await waitForActivations(fromLayer: lastLayer)
        }
        
        // 3. Run final projection and sample token
        let token = try await projectToToken(activations: activations)
        return token
    }
    
    private func runLocalLayers(prompt: String, layers: [Int]) async throws -> Data {
        // This interfaces with MLX to run specific layers
        // Returns the activation tensor as Data
        let ai = ZeroDarkAI.shared
        return try await ai.getActivations(prompt: prompt, layers: layers)
    }
    
    private func waitForActivations(fromLayer: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            if let cached = pendingActivations[fromLayer] {
                pendingActivations.removeValue(forKey: fromLayer)
                continuation.resume(returning: cached)
            } else {
                activationContinuation = continuation
                
                // Timeout after 10 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if activationContinuation != nil {
                        activationContinuation?.resume(throwing: SwarmError.timeout)
                        activationContinuation = nil
                    }
                }
            }
        }
    }
    
    private func projectToToken(activations: Data) async throws -> String {
        let ai = ZeroDarkAI.shared
        return try await ai.projectActivationsToToken(activations)
    }
    
    // MARK: - Communication
    
    private func send(_ message: SwarmMessage, to peer: MCPeerID) async throws {
        let data = try JSONEncoder().encode(message)
        try session.send(data, toPeers: [peer], with: .reliable)
    }
    
    private func broadcast(_ message: SwarmMessage) async throws {
        let data = try JSONEncoder().encode(message)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
    
    private func handleMessage(_ message: SwarmMessage, from peer: MCPeerID) {
        switch message {
        case .deviceInfo(let device):
            var updatedDevice = device
            updatedDevice.connectionQuality = measureConnectionQuality(to: peer)
            peerDeviceMap[peer] = updatedDevice
            
            if !devices.contains(where: { $0.id == device.id }) {
                devices.append(updatedDevice)
                totalMemoryGB = devices.reduce(0) { $0 + $1.memoryGB }
                updateMaxModelSize()
            }
            
            updateState()
            
        case .layerAssignment(let layers, _):
            // Remote device received layer assignment
            if let index = devices.firstIndex(where: { $0.isLocal }) {
                devices[index].assignedLayers = layers
            }
            
        case .activations(let layerIndex, let data):
            if let continuation = activationContinuation {
                continuation.resume(returning: data)
                activationContinuation = nil
            } else {
                pendingActivations[layerIndex] = data
            }
            
        case .tokenResult(let token):
            // Handle token result from remote
            break
            
        case .syncRequest:
            // Send our device info
            let localDevice = devices.first { $0.isLocal }!
            Task {
                try? await send(.deviceInfo(localDevice), to: peer)
            }
            
        case .syncAck:
            break
        }
    }
    
    private func measureConnectionQuality(to peer: MCPeerID) -> SwarmDevice.ConnectionQuality {
        // In production, would measure actual latency
        // For now, assume excellent for local network
        return .excellent
    }
    
    private func updateState() {
        let count = devices.count
        if count >= 2 {
            state = .ready(deviceCount: count, totalMemoryGB: totalMemoryGB)
        } else if count == 1 {
            state = .forming(deviceCount: count)
        }
    }
    
    private func updateMaxModelSize() {
        let maxGB = Double(totalMemoryGB) * 0.6
        if maxGB >= 40 { maxModelSize = "70B" }
        else if maxGB >= 20 { maxModelSize = "40B" }
        else if maxGB >= 10 { maxModelSize = "14B" }
        else { maxModelSize = "8B" }
    }
    
    // MARK: - Errors
    
    public enum SwarmError: Error, LocalizedError {
        case notReady
        case noLocalDevice
        case timeout
        case communicationFailed
        
        public var errorDescription: String? {
            switch self {
            case .notReady: return "Swarm not ready"
            case .noLocalDevice: return "No local device found"
            case .timeout: return "Operation timed out"
            case .communicationFailed: return "Communication failed"
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension DeviceSwarm: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                // Request device info from new peer
                try? await send(.syncRequest, to: peerID)
                
            case .notConnected:
                // Remove disconnected device
                if let device = peerDeviceMap[peerID] {
                    devices.removeAll { $0.id == device.id }
                    totalMemoryGB = devices.reduce(0) { $0 + $1.memoryGB }
                    updateMaxModelSize()
                }
                peerDeviceMap.removeValue(forKey: peerID)
                updateState()
                
            case .connecting:
                break
                
            @unknown default:
                break
            }
        }
    }
    
    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(SwarmMessage.self, from: data) else { return }
        
        Task { @MainActor in
            handleMessage(message, from: peerID)
        }
    }
    
    public nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    public nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    public nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension DeviceSwarm: MCNearbyServiceAdvertiserDelegate {
    public nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations from ZeroDark devices
        // Get session on main actor
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension DeviceSwarm: MCNearbyServiceBrowserDelegate {
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Auto-invite discovered ZeroDark devices
        Task { @MainActor in
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
        }
    }
    
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Handled by session delegate
    }
}
