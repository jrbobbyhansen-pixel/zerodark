// MultiAgent.swift
// Multiple specialist AIs working together
// ABSURD MODE

import Foundation

// MARK: - Multi-Agent System

public actor MultiAgentSystem {
    
    public static let shared = MultiAgentSystem()
    
    // MARK: - Types
    
    public struct Agent: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let role: AgentRole
        public let model: Model
        public let systemPrompt: String
        public let capabilities: Set<Capability>
        public let avatar: String
        
        public enum Capability: String, Sendable {
            case research
            case coding
            case writing
            case analysis
            case creativity
            case planning
            case execution
            case review
        }
    }
    
    public enum AgentRole: String, Sendable {
        case orchestrator = "Orchestrator"   // Coordinates other agents
        case researcher = "Researcher"       // Finds information
        case coder = "Coder"                 // Writes code
        case writer = "Writer"               // Creates content
        case analyst = "Analyst"             // Analyzes data
        case critic = "Critic"               // Reviews work
        case planner = "Planner"             // Creates plans
        case executor = "Executor"           // Executes actions
    }
    
    public struct AgentMessage: Identifiable, Sendable {
        public let id: UUID
        public let fromAgent: String
        public let toAgent: String?  // nil = broadcast
        public let content: String
        public let timestamp: Date
        
        public init(from: String, to: String? = nil, content: String) {
            self.id = UUID()
            self.fromAgent = from
            self.toAgent = to
            self.content = content
            self.timestamp = Date()
        }
    }
    
    public struct TeamResult: Sendable {
        public let task: String
        public let success: Bool
        public let finalOutput: String
        public let conversation: [AgentMessage]
        public let agentContributions: [String: String]
        public let totalTime: TimeInterval
    }
    
    // MARK: - Built-in Agents
    
    public static let orchestrator = Agent(
        id: "orchestrator",
        name: "Director",
        role: .orchestrator,
        model: .qwen3_8b,
        systemPrompt: """
        You are the Director, an orchestration agent. Your job is to:
        1. Understand complex tasks
        2. Break them into subtasks
        3. Assign subtasks to specialist agents
        4. Synthesize their outputs into a final result
        
        Available agents: Researcher, Coder, Writer, Analyst, Critic
        
        For each task, decide which agents to involve and in what order.
        """,
        capabilities: [.planning, .analysis],
        avatar: "👔"
    )
    
    public static let researcher = Agent(
        id: "researcher",
        name: "Scout",
        role: .researcher,
        model: .qwen3_4b,
        systemPrompt: """
        You are Scout, a research specialist. Your job is to:
        1. Find relevant information
        2. Summarize findings
        3. Cite sources
        4. Identify gaps in knowledge
        
        Be thorough but concise. Prioritize accuracy.
        """,
        capabilities: [.research, .analysis],
        avatar: "🔍"
    )
    
    public static let coder = Agent(
        id: "coder",
        name: "Pixel",
        role: .coder,
        model: .qwen3_4b,
        systemPrompt: """
        You are Pixel, a coding specialist. Your job is to:
        1. Write clean, efficient code
        2. Debug issues
        3. Explain technical concepts
        4. Follow best practices
        
        Languages: Swift, Python, TypeScript, Rust
        Always include comments and error handling.
        """,
        capabilities: [.coding, .analysis],
        avatar: "💻"
    )
    
    public static let writer = Agent(
        id: "writer",
        name: "Quill",
        role: .writer,
        model: .qwen3_4b,
        systemPrompt: """
        You are Quill, a writing specialist. Your job is to:
        1. Create compelling content
        2. Edit and refine text
        3. Match tone and style
        4. Structure information clearly
        
        Adapt your style to the audience and purpose.
        """,
        capabilities: [.writing, .creativity],
        avatar: "✍️"
    )
    
    public static let analyst = Agent(
        id: "analyst",
        name: "Prism",
        role: .analyst,
        model: .qwen3_4b,
        systemPrompt: """
        You are Prism, an analysis specialist. Your job is to:
        1. Analyze data and information
        2. Identify patterns and insights
        3. Create summaries and reports
        4. Make recommendations
        
        Be objective and data-driven.
        """,
        capabilities: [.analysis, .planning],
        avatar: "📊"
    )
    
    public static let critic = Agent(
        id: "critic",
        name: "Judge",
        role: .critic,
        model: .qwen3_4b,
        systemPrompt: """
        You are Judge, a quality critic. Your job is to:
        1. Review work from other agents
        2. Identify issues and improvements
        3. Ensure quality standards
        4. Provide constructive feedback
        
        Be fair but thorough. Quality matters.
        """,
        capabilities: [.review, .analysis],
        avatar: "⚖️"
    )
    
    // MARK: - State
    
    private var agents: [String: Agent] = [:]
    private var activeConversation: [AgentMessage] = []
    
    private init() {
        // Register built-in agents
        agents[Self.orchestrator.id] = Self.orchestrator
        agents[Self.researcher.id] = Self.researcher
        agents[Self.coder.id] = Self.coder
        agents[Self.writer.id] = Self.writer
        agents[Self.analyst.id] = Self.analyst
        agents[Self.critic.id] = Self.critic
    }
    
    // MARK: - Team Execution
    
    /// Execute a complex task using multiple agents
    public func executeAsTeam(
        task: String,
        onMessage: @escaping (AgentMessage) -> Void
    ) async throws -> TeamResult {
        let startTime = Date()
        activeConversation = []
        var contributions: [String: String] = [:]
        
        // 1. Orchestrator analyzes the task
        let orchestratorResponse = await runAgent(
            Self.orchestrator,
            input: "Analyze this task and create an execution plan: \(task)"
        )
        let orchestratorMessage = AgentMessage(from: "Director", content: orchestratorResponse)
        activeConversation.append(orchestratorMessage)
        onMessage(orchestratorMessage)
        contributions["Director"] = orchestratorResponse
        
        // 2. Parse which agents to involve (simplified)
        let involvedAgents = determineAgents(for: task, plan: orchestratorResponse)
        
        // 3. Run each agent
        for agent in involvedAgents {
            let context = activeConversation.map { "[\($0.fromAgent)]: \($0.content)" }.joined(separator: "\n")
            let prompt = """
            Task: \(task)
            
            Previous discussion:
            \(context)
            
            As \(agent.name) (\(agent.role.rawValue)), provide your contribution.
            """
            
            let response = await runAgent(agent, input: prompt)
            let message = AgentMessage(from: agent.name, content: response)
            activeConversation.append(message)
            onMessage(message)
            contributions[agent.name] = response
        }
        
        // 4. Critic reviews
        let criticContext = contributions.map { "[\($0.key)]: \($0.value)" }.joined(separator: "\n\n")
        let criticResponse = await runAgent(
            Self.critic,
            input: "Review this team output and provide feedback:\n\n\(criticContext)"
        )
        let criticMessage = AgentMessage(from: "Judge", content: criticResponse)
        activeConversation.append(criticMessage)
        onMessage(criticMessage)
        contributions["Judge"] = criticResponse
        
        // 5. Orchestrator synthesizes final output
        let finalPrompt = """
        Original task: \(task)
        
        Team contributions:
        \(contributions.map { "[\($0.key)]: \($0.value)" }.joined(separator: "\n\n"))
        
        Synthesize these into a final, cohesive response for the user.
        """
        
        let finalResponse = await runAgent(Self.orchestrator, input: finalPrompt)
        let finalMessage = AgentMessage(from: "Director", content: "FINAL OUTPUT:\n\(finalResponse)")
        activeConversation.append(finalMessage)
        onMessage(finalMessage)
        
        let totalTime = Date().timeIntervalSince(startTime)
        
        return TeamResult(
            task: task,
            success: true,
            finalOutput: finalResponse,
            conversation: activeConversation,
            agentContributions: contributions,
            totalTime: totalTime
        )
    }
    
    private func determineAgents(for task: String, plan: String) -> [Agent] {
        var result: [Agent] = []
        let taskLower = task.lowercased()
        
        // Simple keyword matching
        if taskLower.contains("research") || taskLower.contains("find") || taskLower.contains("search") {
            result.append(Self.researcher)
        }
        if taskLower.contains("code") || taskLower.contains("program") || taskLower.contains("script") {
            result.append(Self.coder)
        }
        if taskLower.contains("write") || taskLower.contains("create") || taskLower.contains("draft") {
            result.append(Self.writer)
        }
        if taskLower.contains("analyze") || taskLower.contains("data") || taskLower.contains("report") {
            result.append(Self.analyst)
        }
        
        // Default: at least researcher and writer
        if result.isEmpty {
            result = [Self.researcher, Self.writer]
        }
        
        return result
    }
    
    private func runAgent(_ agent: Agent, input: String) async -> String {
        let ai = await ZeroDarkAI.shared
        let prompt = """
        \(agent.systemPrompt)
        
        USER REQUEST:
        \(input)
        """
        
        do {
            return try await ai.process(prompt: prompt, onToken: { _ in })
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Agent Management
    
    public func getAgent(_ id: String) -> Agent? {
        return agents[id]
    }
    
    public func getAllAgents() -> [Agent] {
        return Array(agents.values)
    }
    
    public func registerAgent(_ agent: Agent) async {
        agents[agent.id] = agent
    }
}
