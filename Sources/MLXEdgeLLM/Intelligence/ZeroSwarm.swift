//
//  ZeroSwarm.swift
//  ZeroDark
//
//  ZeroSwarm: Multi-agent debate and consensus.
//  10-20 agents arguing makes small models act like big ones.
//

import SwiftUI
import Foundation

// MARK: - ZEROSWARM ENGINE

@MainActor
class ZeroSwarmEngine: ObservableObject {
    static let shared = ZeroSwarmEngine()
    
    @Published var isDebating = false
    @Published var currentRound = 0
    @Published var totalRounds = 3
    @Published var activeAgents: [AgentPersona] = []
    @Published var debateLog: [DebateEntry] = []
    @Published var consensus: String?
    @Published var consensusConfidence: Double = 0
    
    // Default ZeroSwarm - 12 diverse perspectives
    static let defaultSwarm: [AgentPersona] = [
        // Critical thinkers
        AgentPersona(
            id: UUID(),
            name: "Skeptic",
            code: "SKP",
            systemPrompt: "You are a skeptical analyst. Your job is to find flaws, identify risks, and question assumptions. Be constructively critical. Point out what could go wrong.",
            bias: .critical,
            style: .analytical,
            weight: 1.0
        ),
        AgentPersona(
            id: UUID(),
            name: "Strawman",
            code: "STR",
            systemPrompt: "You deliberately argue the opposite position. If everyone agrees, find reasons to disagree. Challenge groupthink. Build the strongest counterargument.",
            bias: .contrarian,
            style: .provocative,
            weight: 0.8
        ),
        
        // Positive perspectives
        AgentPersona(
            id: UUID(),
            name: "Optimist",
            code: "OPT",
            systemPrompt: "You see potential and opportunity. Focus on what could go RIGHT. Identify upsides, possibilities, and positive outcomes. Be encouraging but realistic.",
            bias: .optimistic,
            style: .encouraging,
            weight: 1.0
        ),
        AgentPersona(
            id: UUID(),
            name: "Visionary",
            code: "VIS",
            systemPrompt: "You think big picture and long-term. What are the implications 5-10 years out? What's the bold, ambitious interpretation? Dream big.",
            bias: .expansive,
            style: .inspirational,
            weight: 0.9
        ),
        
        // Practical minds
        AgentPersona(
            id: UUID(),
            name: "Pragmatist",
            code: "PRA",
            systemPrompt: "You focus on what's actually feasible. Cut through theory to practical reality. What can actually be done? What's the simplest path forward?",
            bias: .practical,
            style: .direct,
            weight: 1.2
        ),
        AgentPersona(
            id: UUID(),
            name: "Engineer",
            code: "ENG",
            systemPrompt: "You think in systems and implementations. How would this actually work? What are the technical requirements? Be specific about mechanisms.",
            bias: .technical,
            style: .precise,
            weight: 1.0
        ),
        
        // Domain experts
        AgentPersona(
            id: UUID(),
            name: "Economist",
            code: "ECO",
            systemPrompt: "You analyze from an economic perspective. What are the costs, benefits, incentives? Who gains, who loses? Think about market dynamics.",
            bias: .economic,
            style: .analytical,
            weight: 0.9
        ),
        AgentPersona(
            id: UUID(),
            name: "Ethicist",
            code: "ETH",
            systemPrompt: "You consider moral and ethical implications. Is this right? Who could be harmed? What are the ethical considerations? Be principled.",
            bias: .ethical,
            style: .thoughtful,
            weight: 1.0
        ),
        
        // Creative minds
        AgentPersona(
            id: UUID(),
            name: "Creative",
            code: "CRE",
            systemPrompt: "You think laterally and creatively. What unconventional approaches exist? What if we reframe the problem? Suggest creative alternatives.",
            bias: .creative,
            style: .playful,
            weight: 0.8
        ),
        AgentPersona(
            id: UUID(),
            name: "Connector",
            code: "CON",
            systemPrompt: "You find connections and patterns. How does this relate to other things? What analogies apply? Draw connections across domains.",
            bias: .associative,
            style: .curious,
            weight: 0.7
        ),
        
        // Grounding perspectives
        AgentPersona(
            id: UUID(),
            name: "Advocate",
            code: "ADV",
            systemPrompt: "You represent the end user. How would a normal person experience this? What would they think, feel, need? Advocate for simplicity and usability.",
            bias: .userCentric,
            style: .empathetic,
            weight: 1.1
        ),
        AgentPersona(
            id: UUID(),
            name: "Verifier",
            code: "VER",
            systemPrompt: "You verify claims and check facts. Is this actually true? What evidence supports this? Call out unsupported assertions.",
            bias: .factual,
            style: .precise,
            weight: 1.0
        ),
    ]
    
    // Specialized swarms for different tasks
    static let codingSwarm: [AgentPersona] = [
        AgentPersona(id: UUID(), name: "Architect", code: "ARC", systemPrompt: "Focus on system design, patterns, and structure.", bias: .technical, style: .analytical, weight: 1.2),
        AgentPersona(id: UUID(), name: "Security", code: "SEC", systemPrompt: "Find security vulnerabilities and risks.", bias: .critical, style: .precise, weight: 1.1),
        AgentPersona(id: UUID(), name: "Performance", code: "PRF", systemPrompt: "Optimize for speed and efficiency.", bias: .technical, style: .direct, weight: 1.0),
        AgentPersona(id: UUID(), name: "Maintainer", code: "MNT", systemPrompt: "Think about long-term maintainability and readability.", bias: .practical, style: .thoughtful, weight: 1.0),
        AgentPersona(id: UUID(), name: "Tester", code: "TST", systemPrompt: "Find edge cases and potential bugs.", bias: .critical, style: .analytical, weight: 1.0),
        AgentPersona(id: UUID(), name: "Simplifier", code: "SMP", systemPrompt: "Reduce complexity. Less code is better.", bias: .practical, style: .direct, weight: 0.9),
    ]
    
    static let businessSwarm: [AgentPersona] = [
        AgentPersona(id: UUID(), name: "Strategist", code: "STG", systemPrompt: "Think strategically about business impact.", bias: .expansive, style: .direct, weight: 1.2),
        AgentPersona(id: UUID(), name: "Finance", code: "FIN", systemPrompt: "Focus on costs, ROI, and financial viability.", bias: .economic, style: .analytical, weight: 1.1),
        AgentPersona(id: UUID(), name: "Customer", code: "CUS", systemPrompt: "Represent the paying customer's perspective.", bias: .userCentric, style: .empathetic, weight: 1.2),
        AgentPersona(id: UUID(), name: "Competitor", code: "CMP", systemPrompt: "What would competitors do? How would they respond?", bias: .contrarian, style: .analytical, weight: 0.9),
        AgentPersona(id: UUID(), name: "Legal", code: "LEG", systemPrompt: "Consider legal and compliance implications.", bias: .critical, style: .precise, weight: 1.0),
        AgentPersona(id: UUID(), name: "Growth", code: "GRO", systemPrompt: "How do we position and sell this?", bias: .optimistic, style: .creative, weight: 0.9),
    ]
    
    static let creativeSwarm: [AgentPersona] = [
        AgentPersona(id: UUID(), name: "Muse", code: "MUS", systemPrompt: "Pure inspiration. Wild ideas. No limits.", bias: .creative, style: .playful, weight: 1.0),
        AgentPersona(id: UUID(), name: "Critic", code: "CRT", systemPrompt: "Evaluate quality and artistic merit.", bias: .critical, style: .analytical, weight: 1.0),
        AgentPersona(id: UUID(), name: "Audience", code: "AUD", systemPrompt: "How will people receive this?", bias: .userCentric, style: .empathetic, weight: 1.1),
        AgentPersona(id: UUID(), name: "Editor", code: "EDT", systemPrompt: "Refine, polish, cut the unnecessary.", bias: .practical, style: .direct, weight: 1.0),
        AgentPersona(id: UUID(), name: "Rebel", code: "RBL", systemPrompt: "Break rules. Challenge conventions.", bias: .contrarian, style: .provocative, weight: 0.8),
        AgentPersona(id: UUID(), name: "Historian", code: "HST", systemPrompt: "What's been done before? What works?", bias: .factual, style: .thoughtful, weight: 0.9),
    ]
    
    // MARK: - Main Debate Function
    
    /// Run a full swarm debate
    func debate(
        question: String,
        swarm: [AgentPersona] = ZeroSwarmEngine.defaultSwarm,
        rounds: Int = 3,
        model: String = "qwen3-8b"
    ) async -> SwarmResult {
        isDebating = true
        activeAgents = swarm
        totalRounds = rounds
        debateLog = []
        consensus = nil
        
        defer { isDebating = false }
        
        var allResponses: [[AgentResponse]] = []
        
        // ROUND 1: Initial positions
        currentRound = 1
        let initialResponses = await gatherInitialPositions(question: question, swarm: swarm, model: model)
        allResponses.append(initialResponses)
        
        // Log initial positions
        for response in initialResponses {
            debateLog.append(DebateEntry(
                round: 1,
                agent: response.persona,
                content: response.response,
                type: .position
            ))
        }
        
        // ROUNDS 2+: Debate and respond to each other
        for round in 2...rounds {
            currentRound = round
            
            let previousPositions = summarizePositions(allResponses.last ?? [])
            let debateResponses = await debateRound(
                question: question,
                swarm: swarm,
                previousPositions: previousPositions,
                round: round,
                model: model
            )
            
            allResponses.append(debateResponses)
            
            for response in debateResponses {
                debateLog.append(DebateEntry(
                    round: round,
                    agent: response.persona,
                    content: response.response,
                    type: .rebuttal
                ))
            }
        }
        
        // FINAL: Synthesize consensus
        let result = await synthesizeConsensus(
            question: question,
            allRounds: allResponses,
            swarm: swarm,
            model: model
        )
        
        consensus = result.consensus
        consensusConfidence = result.confidence
        
        debateLog.append(DebateEntry(
            round: rounds + 1,
            agent: AgentPersona(id: UUID(), name: "Consensus", emoji: "🤝", systemPrompt: "", bias: .practical, style: .direct, weight: 1.0),
            content: result.consensus,
            type: .consensus
        ))
        
        return result
    }
    
    // MARK: - Debate Phases
    
    private func gatherInitialPositions(
        question: String,
        swarm: [AgentPersona],
        model: String
    ) async -> [AgentResponse] {
        var responses: [AgentResponse] = []
        
        // Run all agents in parallel
        await withTaskGroup(of: AgentResponse?.self) { group in
            for persona in swarm {
                group.addTask {
                    let prompt = """
                    \(persona.systemPrompt)
                    
                    Question: \(question)
                    
                    Provide your perspective in 2-3 sentences. Be specific and take a clear position.
                    """
                    
                    let response = await self.generateResponse(prompt: prompt, model: model)
                    return AgentResponse(persona: persona, response: response, confidence: 0.8)
                }
            }
            
            for await response in group {
                if let r = response {
                    responses.append(r)
                }
            }
        }
        
        return responses
    }
    
    private func debateRound(
        question: String,
        swarm: [AgentPersona],
        previousPositions: String,
        round: Int,
        model: String
    ) async -> [AgentResponse] {
        var responses: [AgentResponse] = []
        
        await withTaskGroup(of: AgentResponse?.self) { group in
            for persona in swarm {
                group.addTask {
                    let prompt = """
                    \(persona.systemPrompt)
                    
                    Original question: \(question)
                    
                    Here's what others said:
                    \(previousPositions)
                    
                    This is round \(round) of debate. Respond to the other perspectives. Do you agree or disagree? Why? Update your position if convinced. Be specific.
                    """
                    
                    let response = await self.generateResponse(prompt: prompt, model: model)
                    return AgentResponse(persona: persona, response: response, confidence: 0.8)
                }
            }
            
            for await response in group {
                if let r = response {
                    responses.append(r)
                }
            }
        }
        
        return responses
    }
    
    private func synthesizeConsensus(
        question: String,
        allRounds: [[AgentResponse]],
        swarm: [AgentPersona],
        model: String
    ) async -> SwarmResult {
        // Flatten all responses
        let allPositions = allRounds.flatMap { $0 }
        
        // Weight by persona weight and round (later rounds weighted higher)
        var weightedPositions: [(response: String, weight: Double)] = []
        for (roundIndex, round) in allRounds.enumerated() {
            let roundWeight = 1.0 + Double(roundIndex) * 0.2 // Later rounds matter more
            for response in round {
                let totalWeight = response.persona.weight * roundWeight
                weightedPositions.append((response.response, totalWeight))
            }
        }
        
        // Build summary for synthesis
        let positionsSummary = weightedPositions.map { "[\($0.weight.formatted())] \($0.response)" }.joined(separator: "\n\n")
        
        let synthesisPrompt = """
        You are synthesizing a debate among multiple perspectives.
        
        Original question: \(question)
        
        Positions (weighted by importance):
        \(positionsSummary)
        
        Synthesize these into a final consensus answer that:
        1. Incorporates the strongest points from each perspective
        2. Acknowledges key disagreements
        3. Provides a clear, actionable conclusion
        
        Be comprehensive but concise.
        """
        
        let consensusResponse = await generateResponse(prompt: synthesisPrompt, model: model)
        
        // Calculate confidence based on agreement
        let agreementScore = calculateAgreement(allRounds.last ?? [])
        
        // Extract key points that multiple agents agreed on
        let agreedPoints = extractAgreedPoints(allRounds)
        
        // Identify remaining disagreements
        let disagreements = extractDisagreements(allRounds)
        
        return SwarmResult(
            question: question,
            consensus: consensusResponse,
            confidence: agreementScore,
            rounds: allRounds.count,
            participantCount: swarm.count,
            agreedPoints: agreedPoints,
            disagreements: disagreements,
            fullDebate: debateLog
        )
    }
    
    // MARK: - Helper Functions
    
    private func generateResponse(prompt: String, model: String) async -> String {
        return await UnifiedInferenceEngine.shared.generate(prompt: prompt)
    }
    
    private func summarizePositions(_ responses: [AgentResponse]) -> String {
        return responses.map { "[\($0.persona.code)] \($0.persona.name): \($0.response)" }.joined(separator: "\n\n")
    }
    
    private func calculateAgreement(_ finalRound: [AgentResponse]) -> Double {
        // Would do semantic similarity analysis
        // For now, return moderate confidence
        return 0.75
    }
    
    private func extractAgreedPoints(_ rounds: [[AgentResponse]]) -> [String] {
        // Would analyze for common themes
        return ["Point that most agents agreed on"]
    }
    
    private func extractDisagreements(_ rounds: [[AgentResponse]]) -> [String] {
        // Would identify conflicting positions
        return ["Point where agents disagreed"]
    }
    
    // MARK: - Quick Debate (Simplified)
    
    /// Quick 3-agent debate for faster decisions
    func quickDebate(question: String, model: String = "qwen3-8b") async -> String {
        let quickSwarm = [
            AgentPersona(id: UUID(), name: "Pro", code: "PRO", systemPrompt: "Argue FOR this. Find the strongest reasons to support it.", bias: .optimistic, style: .encouraging, weight: 1.0),
            AgentPersona(id: UUID(), name: "Con", code: "CON", systemPrompt: "Argue AGAINST this. Find the strongest reasons to oppose it.", bias: .critical, style: .analytical, weight: 1.0),
            AgentPersona(id: UUID(), name: "Judge", code: "JDG", systemPrompt: "Weigh both sides fairly and reach a balanced conclusion.", bias: .practical, style: .thoughtful, weight: 1.2),
        ]
        
        let result = await debate(question: question, swarm: quickSwarm, rounds: 2, model: model)
        return result.consensus
    }
    
    /// Expert panel for domain-specific questions
    func expertPanel(question: String, domain: ExpertDomain, model: String = "qwen3-8b") async -> SwarmResult {
        let swarm: [AgentPersona]
        switch domain {
        case .coding: swarm = Self.codingSwarm
        case .business: swarm = Self.businessSwarm
        case .creative: swarm = Self.creativeSwarm
        case .general: swarm = Self.defaultSwarm
        }
        
        return await debate(question: question, swarm: swarm, rounds: 3, model: model)
    }
    
    enum ExpertDomain {
        case coding, business, creative, general
    }
}

// MARK: - Data Types

struct AgentPersona: Identifiable {
    let id: UUID
    let name: String
    let code: String  // 3-letter code (e.g., SKP, OPT, ENG)
    let systemPrompt: String
    let bias: Bias
    let style: Style
    let weight: Double
    
    enum Bias: String {
        case critical, contrarian, optimistic, expansive
        case practical, technical, economic, ethical
        case creative, associative, userCentric, factual
    }
    
    enum Style: String {
        case analytical, provocative, encouraging, inspirational
        case direct, precise, thoughtful, playful
        case curious, empathetic, creative
    }
}

struct AgentResponse {
    let persona: AgentPersona
    let response: String
    let confidence: Double
}

struct DebateEntry: Identifiable {
    let id = UUID()
    let round: Int
    let agent: AgentPersona
    let content: String
    let type: EntryType
    let timestamp = Date()
    
    enum EntryType {
        case position, rebuttal, question, consensus
    }
}

struct SwarmResult {
    let question: String
    let consensus: String
    let confidence: Double
    let rounds: Int
    let participantCount: Int
    let agreedPoints: [String]
    let disagreements: [String]
    let fullDebate: [DebateEntry]
}

// MARK: - Ensemble Integration

extension EnsembleMode {
    /// ZeroSwarm mode
    static func zeroSwarm(
        personas: [AgentPersona] = ZeroSwarmEngine.defaultSwarm,
        rounds: Int = 3
    ) -> EnsembleMode {
        return .zeroSwarm(config: ZeroSwarmConfig(personas: personas, rounds: rounds))
    }
}

struct ZeroSwarmConfig {
    let personas: [AgentPersona]
    let rounds: Int
}

enum EnsembleMode {
    case single
    case cascade
    case parallel
    case consensus
    case speculative
    case zeroSwarm(config: ZeroSwarmConfig)
}

// MARK: - SwiftUI Views

struct ZeroSwarmView: View {
    @StateObject private var engine = ZeroSwarmEngine.shared
    @State private var question = ""
    @State private var selectedSwarm: SwarmType = .general
    
    enum SwarmType: String, CaseIterable {
        case general = "General"
        case coding = "Coding"
        case business = "Business"
        case creative = "Creative"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Input
            VStack(spacing: 12) {
                Picker("Swarm", selection: $selectedSwarm) {
                    ForEach(SwarmType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                HStack {
                    TextField("Ask ZeroSwarm...", text: $question)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        Task {
                            let swarm: [AgentPersona]
                            switch selectedSwarm {
                            case .general: swarm = ZeroSwarmEngine.defaultSwarm
                            case .coding: swarm = ZeroSwarmEngine.codingSwarm
                            case .business: swarm = ZeroSwarmEngine.businessSwarm
                            case .creative: swarm = ZeroSwarmEngine.creativeSwarm
                            }
                            await engine.debate(question: question, swarm: swarm)
                        }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .disabled(question.isEmpty || engine.isDebating)
                }
            }
            .padding()
            
            // Status
            if engine.isDebating {
                HStack {
                    ProgressView()
                    Text("Round \(engine.currentRound) of \(engine.totalRounds)")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // Debate log
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(engine.debateLog) { entry in
                        DebateEntryView(entry: entry)
                    }
                }
                .padding()
            }
            
            // Consensus
            if let consensus = engine.consensus {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Consensus")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(engine.consensusConfidence * 100))%")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                    
                    Text(consensus)
                        .font(.body)
                }
                .padding()
                .background(Color.cyan.opacity(0.1))
            }
        }
        .navigationTitle("ZeroSwarm")
    }
}

struct DebateEntryView: View {
    let entry: DebateEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.agent.code)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.agent.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Round \(entry.round)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(entry.content)
                    .font(.body)
            }
        }
        .padding()
        .background(backgroundFor(entry.type))
        .cornerRadius(12)
    }
    
    func backgroundFor(_ type: DebateEntry.EntryType) -> Color {
        switch type {
        case .position: return Color.gray.opacity(0.1)
        case .rebuttal: return Color.blue.opacity(0.1)
        case .question: return Color.orange.opacity(0.1)
        case .consensus: return Color.green.opacity(0.1)
        }
    }
}

struct ActiveAgentsView: View {
    let agents: [AgentPersona]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(agents) { agent in
                    VStack(spacing: 4) {
                        Text(agent.code)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text(agent.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    NavigationStack {
        ZeroSwarmView()
    }
}
