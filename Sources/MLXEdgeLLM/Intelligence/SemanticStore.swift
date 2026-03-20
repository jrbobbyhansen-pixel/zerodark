// SemanticStore.swift — RDF-like Triple Store with Inference
// Semantic knowledge base for entity relationships and capability matching

import Foundation
import NaturalLanguage
import Combine

struct SemanticTriple: Identifiable, Codable, Equatable {
    let id: UUID
    let subject: String                     // entity id or label
    let predicate: String                   // relationship type
    let object: String                      // target entity, literal value, or CoT uid
    let context: String                     // named graph / operation context
    let timestamp: Date
    var isDeleted: Bool = false              // soft-delete (Parliament pattern)
    var isInferred: Bool = false             // true = rule-derived, not user-entered

    init(id: UUID = UUID(), subject: String, predicate: String, object: String,
         context: String = "default", timestamp: Date = Date(), isDeleted: Bool = false, isInferred: Bool = false) {
        self.id = id
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.context = context
        self.timestamp = timestamp
        self.isDeleted = isDeleted
        self.isInferred = isInferred
    }

    static func == (lhs: SemanticTriple, rhs: SemanticTriple) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Inference Rules

enum InferenceRule {
    case transitive(predicate: String)                          // If A -p-> B and B -p-> C then A -p-> C
    case domain(subject: String, predicate: String, object: String)  // If A -p-> B then B -isA-> Domain
    case capability(subject: String)                            // If A -canDo-> X and A -isA-> Role then Role -canDo-> X
    case derived(condition: (SemanticTriple) -> Bool, action: (SemanticTriple) -> SemanticTriple)
}

@MainActor
final class SemanticStore: ObservableObject {
    static let shared = SemanticStore()

    @Published var triples: [SemanticTriple] = []
    @Published var lastError: String?
    @Published var inferredCount: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private var inferenceRules: [InferenceRule] = []

    private init() {
        setupDefaultRules()
        subscribeToExternalUpdates()
    }

    // MARK: - Core Operations

    func add(subject: String, predicate: String, object: String, context: String = "default", isInferred: Bool = false) -> SemanticTriple {
        let triple = SemanticTriple(
            subject: subject,
            predicate: predicate,
            object: object,
            context: context,
            isInferred: isInferred
        )

        triples.append(triple)
        triggerInferencePass()
        return triple
    }

    func delete(id: UUID) {
        if let index = triples.firstIndex(where: { $0.id == id }) {
            triples[index].isDeleted = true
        }
    }

    func query(subject: String? = nil, predicate: String? = nil, object: String? = nil, context: String? = nil) -> [SemanticTriple] {
        triples.filter { triple in
            !triple.isDeleted && (
                (subject == nil || triple.subject == subject) &&
                (predicate == nil || triple.predicate == predicate) &&
                (object == nil || triple.object == object) &&
                (context == nil || triple.context == context)
            )
        }
    }

    func activeTriples() -> [SemanticTriple] {
        triples.filter { !$0.isDeleted }
    }

    // MARK: - Search & Vector Operations

    func search(text: String, maxResults: Int = 10) -> [SemanticTriple] {
        guard !text.isEmpty else { return [] }

        let embedding = wordEmbedding(for: text)
        var scored: [(SemanticTriple, Double)] = []

        for triple in activeTriples() {
            let subjectScore = cosineSimilarity(embedding, wordEmbedding(for: triple.subject))
            let objectScore = cosineSimilarity(embedding, wordEmbedding(for: triple.object))
            let predicateScore = cosineSimilarity(embedding, wordEmbedding(for: triple.predicate))

            let maxScore = max(subjectScore, objectScore, predicateScore)
            if maxScore > 0.3 {
                scored.append((triple, maxScore))
            }
        }

        return scored.sorted { $0.1 > $1.1 }
            .prefix(maxResults)
            .map { $0.0 }
    }

    // MARK: - Inference Engine

    func inferredTriples() -> [SemanticTriple] {
        triples.filter { $0.isInferred && !$0.isDeleted }
    }

    private func triggerInferencePass() {
        var newTriples: [SemanticTriple] = []

        for rule in inferenceRules {
            let inferred = applyRule(rule)
            newTriples.append(contentsOf: inferred)
        }

        // Check for duplicates before adding
        for newTriple in newTriples {
            let exists = triples.contains { triple in
                !triple.isDeleted &&
                triple.subject == newTriple.subject &&
                triple.predicate == newTriple.predicate &&
                triple.object == newTriple.object &&
                triple.context == newTriple.context
            }
            if !exists {
                triples.append(newTriple)
            }
        }

        inferredCount = triples.filter { $0.isInferred }.count
    }

    private func applyRule(_ rule: InferenceRule) -> [SemanticTriple] {
        var result: [SemanticTriple] = []

        switch rule {
        case .transitive(let predicate):
            // If A -p-> B and B -p-> C then A -p-> C
            let aPB = query(predicate: predicate)
            for triple1 in aPB {
                let bPC = query(subject: triple1.object, predicate: predicate)
                for triple2 in bPC {
                    let inferred = SemanticTriple(
                        subject: triple1.subject,
                        predicate: predicate,
                        object: triple2.object,
                        context: triple1.context,
                        isInferred: true
                    )
                    result.append(inferred)
                }
            }

        case .domain(let subject, let predicate, let object):
            // If subject exists with predicate then object is derived
            let matching = query(subject: subject, predicate: predicate)
            if !matching.isEmpty {
                let inferred = SemanticTriple(
                    subject: object,
                    predicate: "inDomain",
                    object: subject,
                    isInferred: true
                )
                result.append(inferred)
            }

        case .capability(let subject):
            // If A -canDo-> X and A -isA-> Role then infer role-based capabilities
            let canDo = query(subject: subject, predicate: "canDo")
            let isA = query(subject: subject, predicate: "isA")

            for capability in canDo {
                for roleTriple in isA {
                    let inferred = SemanticTriple(
                        subject: roleTriple.object,
                        predicate: "canDo",
                        object: capability.object,
                        isInferred: true
                    )
                    result.append(inferred)
                }
            }

        case .derived(let condition, let action):
            for triple in activeTriples() {
                if condition(triple) {
                    let inferred = action(triple)
                    result.append(inferred)
                }
            }
        }

        return result
    }

    private func setupDefaultRules() {
        inferenceRules = [
            .transitive(predicate: "isA"),
            .transitive(predicate: "canDo"),
            .transitive(predicate: "owns"),
            .capability(subject: "any")
        ]
    }

    // MARK: - Serialization

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(activeTriples()),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    func importJSON(_ json: String) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = json.data(using: .utf8) {
            let imported = try decoder.decode([SemanticTriple].self, from: data)
            triples.append(contentsOf: imported)
            triggerInferencePass()
        }
    }

    // MARK: - External Data Integration

    private func subscribeToExternalUpdates() {
        // Subscribe to incident store for context triples
        IncidentStore.shared.$incidents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] incidents in
                self?.updateFromIncidents(incidents)
            }
            .store(in: &cancellables)

        // Subscribe to mesh peers for unit triples
        MeshService.shared.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.updateFromMeshPeers(peers)
            }
            .store(in: &cancellables)

        // Subscribe to TAK peers for tactical triples
        FreeTAKConnector.shared.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] takPeers in
                self?.updateFromTAKPeers(takPeers)
            }
            .store(in: &cancellables)
    }

    private func updateFromIncidents(_ incidents: [Incident]) {
        for incident in incidents {
            // Add incident entity triples
            _ = add(subject: incident.uid, predicate: "type", object: "Incident")
            _ = add(subject: incident.uid, predicate: "title", object: incident.title)
            _ = add(subject: incident.uid, predicate: "priority", object: incident.priority.rawValue)
            _ = add(subject: incident.uid, predicate: "status", object: incident.status.rawValue)
            _ = add(subject: incident.uid, predicate: "reporter", object: incident.reporter)

            // Add assignment triples
            for assignment in incident.assignments {
                _ = add(subject: assignment.unitId.uuidString, predicate: "assignedTo", object: incident.uid)
            }
        }
    }

    private func updateFromMeshPeers(_ peers: [ZDPeer]) {
        for peer in peers {
            _ = add(subject: peer.name, predicate: "type", object: "MeshUnit")
            _ = add(subject: peer.name, predicate: "meshId", object: peer.id)
            _ = add(subject: peer.name, predicate: "batteryLevel", object: "\(peer.batteryLevel ?? 0)")
        }
    }

    private func updateFromTAKPeers(_ takPeers: [CoTEvent]) {
        for peer in takPeers {
            let callsign = peer.detail?.contact?.callsign ?? peer.uid
            _ = add(subject: callsign, predicate: "type", object: "TAKUnit")
            _ = add(subject: callsign, predicate: "cotType", object: peer.type)
            if let battery = peer.detail?.status?.battery {
                _ = add(subject: callsign, predicate: "battery", object: "\(battery)")
            }
        }
    }
}

// MARK: - Vector Operations

private func wordEmbedding(for text: String) -> [Float] {
    let components = text.lowercased().split(separator: " ")
    var vector = [Float](repeating: 0, count: 10)

    // Simple hash-based embedding (deterministic, fast)
    for component in components {
        let hash = abs(component.hashValue)
        for i in 0..<vector.count {
            let charIndex = Int(component.count) % (vector.count)
            vector[i] += Float(hash & (i ^ charIndex)) / Float(UInt32.max)
        }
    }

    // Normalize
    let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
    if magnitude > 0 {
        vector = vector.map { $0 / magnitude }
    }

    return vector
}

private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count, a.count > 0 else { return 0 }

    let dotProduct = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    let magnitudeA = sqrt(a.reduce(0) { $0 + $1 * $1 })
    let magnitudeB = sqrt(b.reduce(0) { $0 + $1 * $1 })

    if magnitudeA == 0 || magnitudeB == 0 { return 0 }
    return Double(dotProduct / (magnitudeA * magnitudeB))
}
