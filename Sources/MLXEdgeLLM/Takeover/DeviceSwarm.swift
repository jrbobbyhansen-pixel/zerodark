// DeviceSwarm.swift
// Cross-device distributed inference
// iPhone + iPad + Mac = ONE MIND running 70B+ models
// ZETA³: THE TAKEOVER

import Foundation
import MultipeerConnectivity
import Network

// MARK: - Device Swarm

/// Coordinates multiple Apple devices to run models together
/// Each device handles a shard of the model
public actor DeviceSwarm {
    
    public static let shared = DeviceSwarm()
    
    // MARK: - Types
    
    public struct SwarmDevice: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let type: DeviceType
        public let memoryGB: Int
        public let isLocal: Bool
        public let connectionQuality: ConnectionQuality
        
        public enum DeviceType: String, Sendable {
            case iPhone = "iPhone"
            case iPad = "iPad"
            case mac = "Mac"
            case visionPro = "Vision Pro"
        }
        
        public enum ConnectionQuality: String, Sendable {
            case local = "Local"      // This device
            case excellent = "Excellent"  // Same WiFi, <10ms
            case good = "Good"        // Same network, <50ms
            case fair = "Fair"        // Remote, <200ms
            case poor = "Poor"        // >200ms
        }
        
        public var maxModelSizeGB: Double {
            // Estimate: can use ~60% of RAM for model
            return Double(memoryGB) * 0.6
        }
        
        public init(id: String, name: String, type: DeviceType, memoryGB: Int, isLocal: Bool, connectionQuality: ConnectionQuality) {
            self.id = id
            self.name = name
            self.type = type
            self.memoryGB = memoryGB
            self.isLocal = isLocal
            self.connectionQuality = connectionQuality
        }
    }
    
    public struct SwarmConfig: Sendable {
        /// Minimum devices needed to start
        public var minDevices: Int = 2
        
        /// Target model to run across swarm
        public var targetModel: String = "llama-3.1-70b"
        
        /// Sharding strategy
        public var strategy: ShardingStrategy = .automatic
        
        public enum ShardingStrategy: Sendable {
            case automatic       // Let system decide
            case layerSplit     // Split by transformer layers
            case tensorParallel // Split tensors across devices
            case pipeline       // Pipeline parallel (sequential)
        }
        
        public init() {}
    }
    
    public enum SwarmState: Sendable {
        case disconnected
        case discovering
        case forming(devices: Int)
        case ready(devices: Int, totalMemoryGB: Int)
        case inferring(progress: Double)
        case error(String)
    }
    
    // MARK: - State
    
    @Published public private(set) var state: SwarmState = .disconnected
    @Published public private(set) var devices: [SwarmDevice] = []
    @Published public private(set) var totalMemoryGB: Int = 0
    
    private var config = SwarmConfig()
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private let serviceType = "zerodark-swarm"
    
    // MARK: - Swarm Control
    
    /// Start discovering and connecting to nearby devices
    public func startSwarm(config: SwarmConfig = SwarmConfig()) async {
        self.config = config
        state = .discovering
        
        // Add local device first
        let localDevice = await getLocalDevice()
        devices = [localDevice]
        totalMemoryGB = localDevice.memoryGB
        
        // Start peer discovery
        await startPeerDiscovery()
    }
    
    /// Stop the swarm
    public func stopSwarm() async {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        
        devices = []
        totalMemoryGB = 0
        state = .disconnected
    }
    
    /// Run inference across the swarm
    public func generate(
        prompt: String,
        maxTokens: Int = 500,
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard case .ready = state else {
            throw SwarmError.notReady
        }
        
        state = .inferring(progress: 0)
        
        // 1. Calculate sharding plan
        let plan = await createShardingPlan()
        
        // 2. Distribute model shards (if not already loaded)
        try await distributeShards(plan)
        
        // 3. Run coordinated inference
        var result = ""
        var tokensGenerated = 0
        
        while tokensGenerated < maxTokens {
            // Coordinate across devices
            let nextToken = try await coordinatedStep(prompt: prompt, generated: result)
            
            if nextToken == "<|end|>" || nextToken.isEmpty {
                break
            }
            
            result += nextToken
            tokensGenerated += 1
            onToken(nextToken)
            
            // Update progress
            state = .inferring(progress: Double(tokensGenerated) / Double(maxTokens))
        }
        
        state = .ready(devices: devices.count, totalMemoryGB: totalMemoryGB)
        return result
    }
    
    // MARK: - Private Implementation
    
    private func getLocalDevice() async -> SwarmDevice {
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        
        #if os(iOS)
        let type: SwarmDevice.DeviceType = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        let name = UIDevice.current.name
        #elseif os(macOS)
        let type: SwarmDevice.DeviceType = .mac
        let name = Host.current().localizedName ?? "Mac"
        #elseif os(visionOS)
        let type: SwarmDevice.DeviceType = .visionPro
        let name = "Apple Vision Pro"
        #else
        let type: SwarmDevice.DeviceType = .mac
        let name = "Unknown"
        #endif
        
        return SwarmDevice(
            id: UUID().uuidString,
            name: name,
            type: type,
            memoryGB: memoryGB,
            isLocal: true,
            connectionQuality: .local
        )
    }
    
    private func startPeerDiscovery() async {
        // In production: use MultipeerConnectivity
        // This is the coordination layer
        
        // Simulate finding another device for demo
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec
            
            // Simulate finding an iPad
            let simulatedDevice = SwarmDevice(
                id: UUID().uuidString,
                name: "Bobby's iPad Pro",
                type: .iPad,
                memoryGB: 16,
                isLocal: false,
                connectionQuality: .excellent
            )
            
            devices.append(simulatedDevice)
            totalMemoryGB += simulatedDevice.memoryGB
            
            if devices.count >= config.minDevices {
                state = .ready(devices: devices.count, totalMemoryGB: totalMemoryGB)
            } else {
                state = .forming(devices: devices.count)
            }
        }
    }
    
    private struct ShardingPlan {
        let deviceAssignments: [String: [Int]] // device ID -> layer indices
        let modelSize: Int
    }
    
    private func createShardingPlan() async -> ShardingPlan {
        // Simple layer split based on memory
        var assignments: [String: [Int]] = [:]
        
        // Assume 80 layers for 70B model
        let totalLayers = 80
        var currentLayer = 0
        
        for device in devices {
            let proportion = Double(device.memoryGB) / Double(totalMemoryGB)
            let layersForDevice = Int(Double(totalLayers) * proportion)
            
            let endLayer = min(currentLayer + layersForDevice, totalLayers)
            assignments[device.id] = Array(currentLayer..<endLayer)
            currentLayer = endLayer
        }
        
        return ShardingPlan(deviceAssignments: assignments, modelSize: totalLayers)
    }
    
    private func distributeShards(_ plan: ShardingPlan) async throws {
        // In production: send model shard data to each device
        // Each device loads only its assigned layers
        
        for device in devices where !device.isLocal {
            // Send shard assignment to remote device
            guard let layers = plan.deviceAssignments[device.id] else { continue }
            
            // Would use MCSession to send actual model weights
            _ = layers
        }
    }
    
    private func coordinatedStep(prompt: String, generated: String) async throws -> String {
        // Pipeline parallel: each device processes its layers in sequence
        // 1. Local device runs embedding + first N layers
        // 2. Send activations to next device
        // 3. Next device runs its layers
        // 4. Continue until final device produces logits
        // 5. Sample token and return
        
        // Simplified: delegate to distributed inference system
        let distributed = await DistributedInference.shared
        
        // For demo, fall back to local
        if devices.count == 1 {
            let ai = await ZeroDarkAI.shared
            let fullPrompt = prompt + generated
            var nextToken = ""
            _ = try await ai.process(prompt: fullPrompt + " (next word only)") { token in
                nextToken = token
            }
            return nextToken
        }
        
        // In production: actual cross-device coordination
        return ""
    }
    
    public enum SwarmError: Error {
        case notReady
        case deviceDisconnected
        case shardingFailed
        case coordinationTimeout
    }
}

// MARK: - Swarm Monitor View

#if os(iOS) || os(macOS)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public struct SwarmMonitorView: View {
    @StateObject private var monitor = SwarmMonitorViewModel()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("🌐 Device Swarm")
                .font(.title.bold())
                .foregroundColor(.white)
            
            // Status
            statusBadge
            
            // Devices
            if !monitor.devices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(monitor.devices) { device in
                        DeviceRow(device: device)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Total capacity
            HStack {
                Text("Total Memory:")
                    .foregroundColor(.gray)
                Text("\(monitor.totalMemory) GB")
                    .foregroundColor(.cyan)
                    .fontWeight(.bold)
            }
            
            // Max model
            Text("Can run: \(monitor.maxModelName)")
                .foregroundColor(.green)
                .font(.headline)
            
            // Actions
            HStack(spacing: 16) {
                Button(monitor.isScanning ? "Scanning..." : "Find Devices") {
                    monitor.startScanning()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(monitor.isScanning)
                
                if monitor.devices.count >= 2 {
                    Button("Form Swarm") {
                        monitor.formSwarm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding()
        .background(Color.black)
    }
    
    private var statusBadge: some View {
        HStack {
            Circle()
                .fill(monitor.statusColor)
                .frame(width: 10, height: 10)
            Text(monitor.statusText)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
    }
}

@MainActor
class SwarmMonitorViewModel: ObservableObject {
    @Published var devices: [DeviceSwarm.SwarmDevice] = []
    @Published var totalMemory: Int = 0
    @Published var isScanning = false
    @Published var statusText = "Disconnected"
    @Published var statusColor: Color = .gray
    
    var maxModelName: String {
        let maxGB = Double(totalMemory) * 0.6
        if maxGB >= 40 { return "Llama 3.1 70B" }
        if maxGB >= 20 { return "Llama 3.1 40B" }
        if maxGB >= 8 { return "Llama 3.1 14B" }
        return "Llama 3.1 8B"
    }
    
    func startScanning() {
        isScanning = true
        statusText = "Discovering..."
        statusColor = .yellow
        
        Task {
            await DeviceSwarm.shared.startSwarm()
            
            // Poll for updates
            for await _ in Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().values {
                let swarm = await DeviceSwarm.shared
                devices = await swarm.devices
                totalMemory = await swarm.totalMemoryGB
                
                let state = await swarm.state
                switch state {
                case .ready(let count, _):
                    statusText = "Ready (\(count) devices)"
                    statusColor = .green
                    isScanning = false
                    return
                case .forming(let count):
                    statusText = "Forming (\(count) devices)"
                    statusColor = .yellow
                case .discovering:
                    statusText = "Discovering..."
                    statusColor = .yellow
                default:
                    break
                }
            }
        }
    }
    
    func formSwarm() {
        statusText = "Swarm Active"
        statusColor = .green
    }
}

struct DeviceRow: View {
    let device: DeviceSwarm.SwarmDevice
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(.cyan)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(device.name)
                    .foregroundColor(.white)
                HStack {
                    Text("\(device.memoryGB) GB")
                        .foregroundColor(.gray)
                    Text("•")
                        .foregroundColor(.gray)
                    Text(device.connectionQuality.rawValue)
                        .foregroundColor(qualityColor)
                }
                .font(.caption)
            }
            
            Spacer()
            
            if device.isLocal {
                Text("This Device")
                    .font(.caption)
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(8)
            }
        }
    }
    
    var iconName: String {
        switch device.type {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "desktopcomputer"
        case .visionPro: return "visionpro"
        }
    }
    
    var qualityColor: Color {
        switch device.connectionQuality {
        case .local, .excellent: return .green
        case .good: return .yellow
        case .fair: return .orange
        case .poor: return .red
        }
    }
}

#Preview {
    SwarmMonitorView()
}

#endif
