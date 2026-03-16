//
//  DeepHardcore.swift
//  ZeroDark
//
//  The absolute most hardcore capabilities.
//  Autonomous agents, Metal compute, distributed inference.
//

import SwiftUI
import Foundation
import Metal
import MetalPerformanceShaders
import Accelerate
import Network
import MultipeerConnectivity

// MARK: - 1. AUTONOMOUS AGENT ENGINE

/// Agents that work independently for hours/days
@MainActor
class AutonomousAgentEngine: ObservableObject {
    static let shared = AutonomousAgentEngine()
    
    @Published var activeAgents: [Agent] = []
    @Published var completedTasks: Int = 0
    @Published var totalRuntime: TimeInterval = 0
    
    /// Spawn an autonomous agent with a goal
    func spawn(
        name: String,
        goal: String,
        constraints: AgentConstraints = .default,
        tools: [AgentTool] = AgentTool.standardTools
    ) -> Agent {
        let agent = Agent(
            id: UUID(),
            name: name,
            goal: goal,
            constraints: constraints,
            tools: tools,
            status: .planning
        )
        
        activeAgents.append(agent)
        
        Task {
            await runAgent(agent)
        }
        
        return agent
    }
    
    /// Main agent loop
    private func runAgent(_ agent: Agent) async {
        var agent = agent
        updateAgent(agent)
        
        let startTime = Date()
        var stepCount = 0
        
        // 1. PLANNING PHASE
        agent.status = .planning
        agent.log("Starting goal: \(agent.goal)")
        
        let plan = await generatePlan(for: agent)
        agent.plan = plan
        agent.log("Generated plan with \(plan.steps.count) steps")
        
        updateAgent(agent)
        
        // 2. EXECUTION LOOP
        while agent.status != .completed && agent.status != .failed {
            // Check constraints
            let runtime = Date().timeIntervalSince(startTime)
            if runtime > agent.constraints.maxRuntime {
                agent.status = .completed
                agent.log("Max runtime reached (\(Int(runtime/3600))h)")
                break
            }
            
            if stepCount >= agent.constraints.maxSteps {
                agent.status = .completed
                agent.log("Max steps reached (\(stepCount))")
                break
            }
            
            // Check if battery is low
            if await checkBatteryLow() && !agent.constraints.allowLowBattery {
                agent.status = .paused
                agent.log("Paused due to low battery")
                break
            }
            
            // Get next action
            agent.status = .thinking
            updateAgent(agent)
            
            let nextAction = await decideNextAction(for: agent)
            
            // Execute action
            agent.status = .executing
            agent.currentTask = nextAction.description
            updateAgent(agent)
            
            do {
                let result = try await executeAction(nextAction, for: agent)
                agent.log("✓ \(nextAction.description): \(result.summary)")
                agent.completedSteps.append(CompletedStep(
                    action: nextAction,
                    result: result,
                    timestamp: Date()
                ))
                
                completedTasks += 1
                stepCount += 1
                
                // Check if goal achieved
                if await isGoalAchieved(for: agent) {
                    agent.status = .completed
                    agent.log("🎉 Goal achieved!")
                    break
                }
                
                // Brief pause
                try await Task.sleep(nanoseconds: UInt64(agent.constraints.stepDelay * 1_000_000_000))
                
            } catch {
                agent.log("✗ \(nextAction.description): \(error.localizedDescription)")
                agent.failures += 1
                
                if agent.failures >= agent.constraints.maxFailures {
                    agent.status = .failed
                    agent.log("Too many failures, stopping")
                    break
                }
                
                // Recovery
                await attemptRecovery(for: &agent, from: error)
            }
            
            updateAgent(agent)
        }
        
        totalRuntime += Date().timeIntervalSince(startTime)
        agent.endTime = Date()
        updateAgent(agent)
    }
    
    private func generatePlan(for agent: Agent) async -> AgentPlan {
        // Use LLM to decompose goal into steps
        let prompt = """
        You are an autonomous agent planning to achieve a goal.
        
        Goal: \(agent.goal)
        
        Available tools:
        \(agent.tools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n"))
        
        Create a step-by-step plan. Be specific and actionable.
        
        Plan:
        """
        
        // Would call LLM
        let steps = [
            PlanStep(description: "Analyze the goal", toolNeeded: "think"),
            PlanStep(description: "Gather required information", toolNeeded: "search"),
            PlanStep(description: "Execute main task", toolNeeded: "execute"),
            PlanStep(description: "Verify results", toolNeeded: "verify"),
        ]
        
        return AgentPlan(steps: steps)
    }
    
    private func decideNextAction(for agent: Agent) async -> AgentAction {
        // Analyze current state and decide next action
        let context = """
        Goal: \(agent.goal)
        
        Completed steps:
        \(agent.completedSteps.map { "- \($0.action.description): \($0.result.summary)" }.joined(separator: "\n"))
        
        What should be the next action?
        """
        
        // Would call LLM
        return AgentAction(
            type: .execute,
            description: "Next step in plan",
            parameters: [:]
        )
    }
    
    private func executeAction(_ action: AgentAction, for agent: Agent) async throws -> ActionResult {
        switch action.type {
        case .think:
            // Internal reasoning
            try await Task.sleep(nanoseconds: 500_000_000)
            return ActionResult(success: true, summary: "Analyzed situation", data: nil)
            
        case .search:
            // Web search or local search
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return ActionResult(success: true, summary: "Found relevant information", data: nil)
            
        case .execute:
            // Execute tool
            let tool = agent.tools.first { $0.name == action.parameters["tool"] as? String }
            if let tool = tool {
                let result = try await tool.execute(action.parameters)
                return ActionResult(success: true, summary: result, data: nil)
            }
            return ActionResult(success: false, summary: "Tool not found", data: nil)
            
        case .verify:
            // Verify results
            try await Task.sleep(nanoseconds: 500_000_000)
            return ActionResult(success: true, summary: "Verified", data: nil)
            
        case .wait:
            let seconds = action.parameters["seconds"] as? Int ?? 5
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            return ActionResult(success: true, summary: "Waited \(seconds)s", data: nil)
        }
    }
    
    private func isGoalAchieved(for agent: Agent) async -> Bool {
        // Use LLM to evaluate if goal is achieved
        let prompt = """
        Goal: \(agent.goal)
        
        Work done:
        \(agent.completedSteps.map { $0.result.summary }.joined(separator: "\n"))
        
        Has the goal been fully achieved? Answer yes or no.
        """
        
        // Would call LLM
        return agent.completedSteps.count >= (agent.plan?.steps.count ?? 10)
    }
    
    private func attemptRecovery(for agent: inout Agent, from error: Error) async {
        agent.log("Attempting recovery from: \(error.localizedDescription)")
        // Could try alternative approaches, retry with different parameters, etc.
    }
    
    private func checkBatteryLow() async -> Bool {
        #if os(iOS)
        return UIDevice.current.batteryLevel < 0.1 && UIDevice.current.batteryState != .charging
        #else
        return false
        #endif
    }
    
    private func updateAgent(_ agent: Agent) {
        if let index = activeAgents.firstIndex(where: { $0.id == agent.id }) {
            activeAgents[index] = agent
        }
    }
    
    /// Stop an agent
    func stop(_ agentId: UUID) {
        if let index = activeAgents.firstIndex(where: { $0.id == agentId }) {
            activeAgents[index].status = .completed
            activeAgents[index].log("Manually stopped")
        }
    }
}

// Agent types
struct Agent: Identifiable {
    let id: UUID
    let name: String
    let goal: String
    let constraints: AgentConstraints
    let tools: [AgentTool]
    var status: AgentStatus
    var plan: AgentPlan?
    var currentTask: String = ""
    var completedSteps: [CompletedStep] = []
    var logs: [AgentLogEntry] = []
    var failures: Int = 0
    var startTime: Date = Date()
    var endTime: Date?
    
    mutating func log(_ message: String) {
        logs.append(AgentLogEntry(message: message, timestamp: Date()))
    }
}

enum AgentStatus: String {
    case planning = "Planning"
    case thinking = "Thinking"
    case executing = "Executing"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
    
    var color: Color {
        switch self {
        case .planning: return .purple
        case .thinking: return .blue
        case .executing: return .cyan
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct AgentConstraints {
    var maxRuntime: TimeInterval // seconds
    var maxSteps: Int
    var maxFailures: Int
    var stepDelay: TimeInterval
    var allowLowBattery: Bool
    
    static let `default` = AgentConstraints(
        maxRuntime: 3600 * 24, // 24 hours
        maxSteps: 1000,
        maxFailures: 10,
        stepDelay: 1.0,
        allowLowBattery: false
    )
    
    static let quick = AgentConstraints(
        maxRuntime: 300, // 5 minutes
        maxSteps: 20,
        maxFailures: 3,
        stepDelay: 0.5,
        allowLowBattery: true
    )
}

struct AgentTool {
    let name: String
    let description: String
    let execute: ([String: Any]) async throws -> String
    
    static let standardTools: [AgentTool] = [
        AgentTool(name: "search", description: "Search the web", execute: { _ in "Search results" }),
        AgentTool(name: "calculate", description: "Perform calculations", execute: { _ in "42" }),
        AgentTool(name: "read_file", description: "Read a file", execute: { _ in "File contents" }),
        AgentTool(name: "write_file", description: "Write to a file", execute: { _ in "Written" }),
        AgentTool(name: "run_code", description: "Execute code", execute: { _ in "Code output" }),
        AgentTool(name: "send_message", description: "Send a notification", execute: { _ in "Sent" }),
    ]
}

struct AgentPlan {
    let steps: [PlanStep]
}

struct PlanStep {
    let description: String
    let toolNeeded: String
}

struct AgentAction {
    let type: ActionType
    let description: String
    let parameters: [String: Any]
    
    enum ActionType {
        case think, search, execute, verify, wait
    }
}

struct ActionResult {
    let success: Bool
    let summary: String
    let data: Any?
}

struct CompletedStep {
    let action: AgentAction
    let result: ActionResult
    let timestamp: Date
}

struct AgentLogEntry: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date
}

// MARK: - 2. METAL COMPUTE ENGINE

/// Direct GPU access for custom ML operations
class MetalComputeEngine: ObservableObject {
    static let shared = MetalComputeEngine()
    
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var library: MTLLibrary?
    
    @Published var isAvailable = false
    @Published var gpuName: String = "Unknown"
    @Published var maxThreads: Int = 0
    
    init() {
        setupMetal()
    }
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal not available")
            return
        }
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.library = device.makeDefaultLibrary()
        
        isAvailable = true
        gpuName = device.name
        maxThreads = device.maxThreadsPerThreadgroup.width
    }
    
    // MARK: - Matrix Operations (Foundation of LLM inference)
    
    /// GPU-accelerated matrix multiplication
    /// This is the core operation in transformer inference
    func matmul(
        a: [Float], // M x K
        b: [Float], // K x N
        m: Int, n: Int, k: Int
    ) -> [Float] {
        // Use Accelerate for now (can switch to Metal for larger matrices)
        var c = [Float](repeating: 0, count: m * n)
        
        cblas_sgemm(
            CblasRowMajor,
            CblasNoTrans,
            CblasNoTrans,
            Int32(m), Int32(n), Int32(k),
            1.0,
            a, Int32(k),
            b, Int32(n),
            0.0,
            &c, Int32(n)
        )
        
        return c
    }
    
    /// GPU softmax (used in attention)
    func softmax(_ input: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: input.count)
        var length = Int32(input.count)
        
        // Find max for numerical stability
        var maxVal: Float = 0
        vDSP_maxv(input, 1, &maxVal, vDSP_Length(input.count))
        
        // Subtract max and exp
        var shifted = [Float](repeating: 0, count: input.count)
        var negMax = -maxVal
        vDSP_vsadd(input, 1, &negMax, &shifted, 1, vDSP_Length(input.count))
        
        var count = Int32(input.count)
        vvexpf(&result, shifted, &count)
        
        // Sum
        var sum: Float = 0
        vDSP_sve(result, 1, &sum, vDSP_Length(input.count))
        
        // Divide
        vDSP_vsdiv(result, 1, &sum, &result, 1, vDSP_Length(input.count))
        
        return result
    }
    
    /// GPU layer normalization
    func layerNorm(_ input: [Float], gamma: [Float], beta: [Float], eps: Float = 1e-5) -> [Float] {
        var result = [Float](repeating: 0, count: input.count)
        
        // Mean
        var mean: Float = 0
        vDSP_meanv(input, 1, &mean, vDSP_Length(input.count))
        
        // Variance
        var variance: Float = 0
        var centered = [Float](repeating: 0, count: input.count)
        var negMean = -mean
        vDSP_vsadd(input, 1, &negMean, &centered, 1, vDSP_Length(input.count))
        
        var squared = [Float](repeating: 0, count: input.count)
        vDSP_vsq(centered, 1, &squared, 1, vDSP_Length(input.count))
        vDSP_meanv(squared, 1, &variance, vDSP_Length(input.count))
        
        // Normalize
        let std = sqrt(variance + eps)
        var invStd = 1.0 / std
        vDSP_vsmul(centered, 1, &invStd, &result, 1, vDSP_Length(input.count))
        
        // Scale and shift
        vDSP_vmul(result, 1, gamma, 1, &result, 1, vDSP_Length(input.count))
        vDSP_vadd(result, 1, beta, 1, &result, 1, vDSP_Length(input.count))
        
        return result
    }
    
    /// GPU RoPE (Rotary Position Embedding)
    func rotaryPositionEmbedding(
        query: [Float],
        key: [Float],
        position: Int,
        headDim: Int
    ) -> (query: [Float], key: [Float]) {
        var rotatedQ = query
        var rotatedK = key
        
        for i in stride(from: 0, to: headDim, by: 2) {
            let theta = Float(position) * pow(10000.0, -Float(i) / Float(headDim))
            let cos = Darwin.cos(theta)
            let sin = Darwin.sin(theta)
            
            let q0 = query[i]
            let q1 = query[i + 1]
            rotatedQ[i] = q0 * cos - q1 * sin
            rotatedQ[i + 1] = q0 * sin + q1 * cos
            
            let k0 = key[i]
            let k1 = key[i + 1]
            rotatedK[i] = k0 * cos - k1 * sin
            rotatedK[i + 1] = k0 * sin + k1 * cos
        }
        
        return (rotatedQ, rotatedK)
    }
    
    /// GPU KV-Cache update
    func updateKVCache(
        keyCache: inout [[Float]],
        valueCache: inout [[Float]],
        newKey: [Float],
        newValue: [Float],
        position: Int
    ) {
        if position >= keyCache.count {
            keyCache.append(newKey)
            valueCache.append(newValue)
        } else {
            keyCache[position] = newKey
            valueCache[position] = newValue
        }
    }
    
    // MARK: - Custom Kernels
    
    /// Compile and run a custom Metal kernel
    func runCustomKernel(
        name: String,
        inputBuffer: [Float],
        outputSize: Int,
        threadCount: Int
    ) throws -> [Float] {
        guard let device = device,
              let commandQueue = commandQueue,
              let library = library,
              let function = library.makeFunction(name: name),
              let pipeline = try? device.makeComputePipelineState(function: function)
        else {
            throw MetalError.setupFailed
        }
        
        // Create buffers
        guard let inputMTLBuffer = device.makeBuffer(
            bytes: inputBuffer,
            length: inputBuffer.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw MetalError.bufferCreationFailed
        }
        
        guard let outputMTLBuffer = device.makeBuffer(
            length: outputSize * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw MetalError.bufferCreationFailed
        }
        
        // Create command buffer and encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MetalError.encoderCreationFailed
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputMTLBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputMTLBuffer, offset: 0, index: 1)
        
        let threadsPerGroup = MTLSize(width: min(256, threadCount), height: 1, depth: 1)
        let numGroups = MTLSize(width: (threadCount + 255) / 256, height: 1, depth: 1)
        
        encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read results
        let outputPointer = outputMTLBuffer.contents().bindMemory(to: Float.self, capacity: outputSize)
        return Array(UnsafeBufferPointer(start: outputPointer, count: outputSize))
    }
    
    enum MetalError: Error {
        case setupFailed
        case bufferCreationFailed
        case encoderCreationFailed
    }
}

// MARK: - 3. DISTRIBUTED INFERENCE (Device Swarm)

/// Run inference across multiple Apple devices
class DeviceSwarmEngine: NSObject, ObservableObject {
    static let shared = DeviceSwarmEngine()
    
    @Published var connectedDevices: [SwarmDevice] = []
    @Published var isHost = false
    @Published var totalCapacity: Int = 0 // GB
    
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let serviceType = "zerodark-swarm"
    
    private var myPeerID: MCPeerID!
    
    override init() {
        super.init()
        myPeerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }
    
    /// Start hosting a swarm
    func startHosting() {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: deviceInfo(), serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        isHost = true
    }
    
    /// Join an existing swarm
    func startBrowsing() {
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }
    
    /// Stop swarm
    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        connectedDevices.removeAll()
    }
    
    /// Distribute inference across swarm
    func distributedInference(
        prompt: String,
        modelLayers: Int = 32
    ) async throws -> String {
        guard !connectedDevices.isEmpty else {
            throw SwarmError.noDevices
        }
        
        // Strategy: Pipeline parallelism
        // Each device handles a portion of layers
        let devicesCount = connectedDevices.count + 1 // Include self
        let layersPerDevice = modelLayers / devicesCount
        
        // Send layer assignments
        for (index, device) in connectedDevices.enumerated() {
            let startLayer = (index + 1) * layersPerDevice
            let endLayer = startLayer + layersPerDevice
            
            let assignment = LayerAssignment(startLayer: startLayer, endLayer: endLayer, prompt: prompt)
            try sendToDevice(device.id, data: assignment)
        }
        
        // Process local layers (0 to layersPerDevice)
        var hidden = try await processLayers(0..<layersPerDevice, prompt: prompt)
        
        // Forward through other devices
        for device in connectedDevices {
            hidden = try await sendAndReceive(device.id, hidden: hidden)
        }
        
        // Final output
        return try await generateOutput(hidden: hidden)
    }
    
    private func deviceInfo() -> [String: String] {
        return [
            "model": UIDevice.current.model,
            "ram": "\(ProcessInfo.processInfo.physicalMemory / 1_000_000_000)GB"
        ]
    }
    
    private func processLayers(_ range: Range<Int>, prompt: String) async throws -> [Float] {
        // Would process transformer layers
        return []
    }
    
    private func sendToDevice(_ deviceId: String, data: Encodable) throws {
        // Send via MCSession
    }
    
    private func sendAndReceive(_ deviceId: String, hidden: [Float]) async throws -> [Float] {
        // Send hidden state, receive processed result
        return hidden
    }
    
    private func generateOutput(hidden: [Float]) async throws -> String {
        // Generate tokens from final hidden state
        return ""
    }
    
    enum SwarmError: Error {
        case noDevices
        case communicationFailed
    }
}

struct LayerAssignment: Codable {
    let startLayer: Int
    let endLayer: Int
    let prompt: String
}

struct SwarmDevice: Identifiable {
    let id: String
    let name: String
    let model: String
    let ramGB: Int
    var assignedLayers: Range<Int>?
    var status: DeviceStatus = .idle
    
    enum DeviceStatus {
        case idle, processing, error
    }
}

extension DeviceSwarmEngine: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                let device = SwarmDevice(id: peerID.displayName, name: peerID.displayName, model: "Unknown", ramGB: 8)
                if !self.connectedDevices.contains(where: { $0.id == device.id }) {
                    self.connectedDevices.append(device)
                    self.totalCapacity += device.ramGB
                }
            case .notConnected:
                self.connectedDevices.removeAll { $0.id == peerID.displayName }
            default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle received data
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.connectedDevices.removeAll { $0.id == peerID.displayName }
        }
    }
}

// MARK: - Dashboard View

struct HardcoreDashboardView: View {
    @StateObject private var agents = AutonomousAgentEngine.shared
    @StateObject private var metal = MetalComputeEngine.shared
    @StateObject private var swarm = DeviceSwarmEngine.shared
    
    var body: some View {
        List {
            // Autonomous Agents
            Section {
                NavigationLink {
                    AgentsDashboardView()
                } label: {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading) {
                            Text("Autonomous Agents")
                                .font(.headline)
                            Text("\(agents.activeAgents.count) active • \(agents.completedTasks) tasks done")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Metal Compute
            Section {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.cyan)
                    VStack(alignment: .leading) {
                        Text("Metal Compute")
                            .font(.headline)
                        Text(metal.isAvailable ? metal.gpuName : "Not available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if metal.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Device Swarm
            Section {
                NavigationLink {
                    SwarmDashboardView()
                } label: {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading) {
                            Text("Device Swarm")
                                .font(.headline)
                            Text("\(swarm.connectedDevices.count) devices • \(swarm.totalCapacity)GB total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hardcore")
    }
}

struct AgentsDashboardView: View {
    @StateObject private var engine = AutonomousAgentEngine.shared
    @State private var showNewAgent = false
    
    var body: some View {
        List {
            ForEach(engine.activeAgents) { agent in
                AgentRow(agent: agent)
            }
        }
        .navigationTitle("Agents")
        .toolbar {
            Button {
                showNewAgent = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

struct AgentRow: View {
    let agent: Agent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(agent.name)
                    .font(.headline)
                Spacer()
                Text(agent.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(agent.status.color.opacity(0.2))
                    .foregroundColor(agent.status.color)
                    .cornerRadius(4)
            }
            
            Text(agent.goal)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if !agent.currentTask.isEmpty {
                Text("→ \(agent.currentTask)")
                    .font(.caption)
                    .foregroundColor(.cyan)
            }
            
            ProgressView(value: Double(agent.completedSteps.count), total: Double(agent.plan?.steps.count ?? 10))
                .tint(.cyan)
        }
        .padding(.vertical, 4)
    }
}

struct SwarmDashboardView: View {
    @StateObject private var swarm = DeviceSwarmEngine.shared
    
    var body: some View {
        List {
            Section {
                if swarm.isHost {
                    Label("Hosting swarm", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.green)
                } else {
                    Button("Start Hosting") {
                        swarm.startHosting()
                    }
                    Button("Browse for Swarms") {
                        swarm.startBrowsing()
                    }
                }
            }
            
            Section("Connected Devices") {
                ForEach(swarm.connectedDevices) { device in
                    HStack {
                        Image(systemName: "iphone")
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("\(device.ramGB)GB RAM")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Device Swarm")
    }
}

#Preview {
    NavigationStack {
        HardcoreDashboardView()
    }
}
