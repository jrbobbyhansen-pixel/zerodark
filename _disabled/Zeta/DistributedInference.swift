import Foundation
import MultipeerConnectivity
import Network

// MARK: - Distributed Inference

/// Split inference across multiple Apple devices
/// iPhone + iPad + Mac = One giant brain

public actor DistributedInference {
    
    public static let shared = DistributedInference()
    
    // MARK: - Cluster
    
    public struct DeviceNode: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let type: DeviceType
        public let ramGB: Int
        public let isConnected: Bool
        public let latencyMs: Int
        
        public enum DeviceType: String {
            case iPhone = "iPhone"
            case iPad = "iPad"
            case mac = "Mac"
            case vision = "Vision Pro"
        }
        
        /// Compute capacity score
        public var computeScore: Int {
            switch type {
            case .mac: return ramGB * 10
            case .vision: return ramGB * 8
            case .iPad: return ramGB * 5
            case .iPhone: return ramGB * 3
            }
        }
    }
    
    public struct Cluster {
        public var nodes: [DeviceNode]
        public var totalRAMGB: Int { nodes.reduce(0) { $0 + $1.ramGB } }
        public var totalComputeScore: Int { nodes.reduce(0) { $0 + $1.computeScore } }
        
        /// Maximum model size this cluster can run
        public var maxModelSizeGB: Int {
            // Can shard across devices
            Int(Double(totalRAMGB) * 0.7)
        }
    }
    
    // MARK: - State
    
    private var cluster = Cluster(nodes: [])
    private var peerSession: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    
    // MARK: - Discovery
    
    /// Start discovering nearby devices
    public func startDiscovery() {
        let peerId = MCPeerID(displayName: getDeviceName())
        
        peerSession = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        
        // Advertise ourselves
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerId,
            discoveryInfo: ["type": getDeviceType().rawValue, "ram": "\(getRAMGB())"],
            serviceType: "zerodark-mesh"
        )
        advertiser?.startAdvertisingPeer()
        
        // Browse for others
        browser = MCNearbyServiceBrowser(peer: peerId, serviceType: "zerodark-mesh")
        browser?.startBrowsingForPeers()
    }
    
    /// Stop discovery
    public func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
    }
    
    // MARK: - Model Sharding
    
    public struct ShardPlan {
        public let model: Model
        public let shards: [Shard]
        
        public struct Shard {
            public let layerRange: ClosedRange<Int>
            public let targetDevice: DeviceNode
            public let sizeMB: Int
        }
    }
    
    /// Plan how to shard a model across cluster
    public func planSharding(model: Model) -> ShardPlan {
        let totalLayers = model.layerCount
        let sortedNodes = cluster.nodes.sorted { $0.computeScore > $1.computeScore }
        
        var shards: [ShardPlan.Shard] = []
        var layerStart = 0
        
        // Distribute layers proportionally to compute score
        let totalScore = cluster.totalComputeScore
        
        for node in sortedNodes {
            let layerCount = (node.computeScore * totalLayers) / max(totalScore, 1)
            let layerEnd = min(layerStart + layerCount - 1, totalLayers - 1)
            
            if layerStart <= layerEnd {
                let sizeMB = (model.approximateSizeMB * layerCount) / totalLayers
                
                shards.append(ShardPlan.Shard(
                    layerRange: layerStart...layerEnd,
                    targetDevice: node,
                    sizeMB: sizeMB
                ))
                
                layerStart = layerEnd + 1
            }
        }
        
        return ShardPlan(model: model, shards: shards)
    }
    
    // MARK: - Distributed Generation
    
    /// Generate using distributed inference
    public func generate(
        prompt: String,
        model: Model,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let plan = planSharding(model: model)
        
        // If single device, run locally
        if plan.shards.count == 1 {
            let engine = try await BeastEngine(model: model)
            return try await engine.generate(prompt: prompt, onToken: onToken)
        }
        
        // Distributed inference
        return try await distributedGenerate(prompt: prompt, plan: plan, onToken: onToken)
    }
    
    private func distributedGenerate(
        prompt: String,
        plan: ShardPlan,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        // Pipeline parallelism:
        // 1. Send prompt to first device
        // 2. Each device processes its layers
        // 3. Passes activations to next device
        // 4. Last device generates token
        // 5. Repeat
        
        var fullResponse = ""
        
        // Simplified - real implementation would use MCSession for communication
        // and proper tensor serialization
        
        return fullResponse
    }
    
    // MARK: - Helpers
    
    private func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
    
    private func getDeviceType() -> DeviceNode.DeviceType {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPad
        }
        return .iPhone
        #elseif os(visionOS)
        return .vision
        #else
        return .mac
        #endif
    }
    
    private func getRAMGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
}

// MARK: - Model Layer Info

extension Model {
    var layerCount: Int {
        switch self {
        case .qwen3_0_6b, .gemma3_1b: return 16
        case .qwen3_1_7b, .llama3_2_1b: return 22
        case .llama3_2_3b, .phi3_5_mini: return 32
        case .qwen3_4b: return 40
        case .qwen3_8b, .llama3_1_8b, .qwen25_coder_7b: return 32
        case .qwen25_14b, .qwen3_14b: return 48
        default: return 32
        }
    }
}
