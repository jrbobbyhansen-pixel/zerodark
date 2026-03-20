// IncidentStore.swift — Incident & Unit Coordination Store
// In-memory incident, unit, and assignment tracking with CoT broadcast

import Foundation
import CoreLocation
import Combine

enum IncidentStatus: String, Codable, CaseIterable {
    case active = "Active"
    case contained = "Contained"
    case resolved = "Resolved"
    case cancelled = "Cancelled"
}

enum IncidentPriority: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
}

enum UnitRole: String, Codable, CaseIterable {
    case medic = "Medic"
    case rescue = "Rescue"
    case recon = "Recon"
    case logistics = "Logistics"
    case comms = "Comms"
    case command = "Command"
}

enum UnitStatus: String, Codable, CaseIterable {
    case available = "Available"
    case assigned = "Assigned"
    case enroute = "En Route"
    case onScene = "On Scene"
    case offline = "Offline"
}

struct Incident: Identifiable, Codable {
    var id: UUID = UUID()
    var uid: String                          // CoT uid for mesh broadcast
    var title: String
    var summary: String
    var coordinate: CLLocationCoordinate2D
    var timestamp: Date = Date()
    var staleTime: Date                      // when incident auto-expires (default +2h)
    var status: IncidentStatus = .active
    var priority: IncidentPriority = .medium
    var assignments: [Assignment] = []
    var reporter: String

    enum CodingKeys: String, CodingKey {
        case id, uid, title, summary, coordinate, timestamp, staleTime, status, priority, assignments, reporter
    }

    init(id: UUID = UUID(), uid: String = UUID().uuidString, title: String, summary: String,
         coordinate: CLLocationCoordinate2D, reporter: String, priority: IncidentPriority = .medium,
         staleTime: Date? = nil) {
        self.id = id
        self.uid = uid
        self.title = title
        self.summary = summary
        self.coordinate = coordinate
        self.reporter = reporter
        self.priority = priority
        self.staleTime = staleTime ?? Date(timeIntervalSinceNow: 7200)  // 2 hours default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(uid, forKey: .uid)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode("\(coordinate.latitude),\(coordinate.longitude)", forKey: .coordinate)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(staleTime, forKey: .staleTime)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(priority.rawValue, forKey: .priority)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(reporter, forKey: .reporter)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        uid = try container.decode(String.self, forKey: .uid)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        let statusRaw = try container.decode(String.self, forKey: .status)
        status = IncidentStatus(rawValue: statusRaw) ?? .active
        let priorityRaw = try container.decode(String.self, forKey: .priority)
        priority = IncidentPriority(rawValue: priorityRaw) ?? .medium
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        staleTime = try container.decode(Date.self, forKey: .staleTime)
        assignments = try container.decode([Assignment].self, forKey: .assignments)
        reporter = try container.decode(String.self, forKey: .reporter)
        let coordString = try container.decodeIfPresent(String.self, forKey: .coordinate) ?? "0,0"
        let parts = coordString.split(separator: ",").compactMap { Double($0) }
        coordinate = CLLocationCoordinate2D(
            latitude: parts.count > 0 ? parts[0] : 0,
            longitude: parts.count > 1 ? parts[1] : 0
        )
    }
}

struct Unit: Identifiable, Codable {
    var id: UUID = UUID()
    var callsign: String
    var role: UnitRole = .rescue
    var status: UnitStatus = .available
    var location: CLLocationCoordinate2D?
    var lastCheckin: Date = Date()
    var capabilities: [String] = []
    var battery: Int = 100
    
    enum CodingKeys: String, CodingKey {
        case id, callsign, role, status, location, lastCheckin, capabilities, battery
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(callsign, forKey: .callsign)
        try container.encode(role.rawValue, forKey: .role)
        try container.encode(status.rawValue, forKey: .status)
        if let loc = location {
            try container.encode("\(loc.latitude),\(loc.longitude)", forKey: .location)
        }
        try container.encode(lastCheckin, forKey: .lastCheckin)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(battery, forKey: .battery)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        callsign = try container.decode(String.self, forKey: .callsign)
        let roleRaw = try container.decode(String.self, forKey: .role)
        role = UnitRole(rawValue: roleRaw) ?? .rescue
        let statusRaw = try container.decode(String.self, forKey: .status)
        status = UnitStatus(rawValue: statusRaw) ?? .available
        if let locString = try container.decodeIfPresent(String.self, forKey: .location) {
            let parts = locString.split(separator: ",").compactMap { Double($0) }
            if parts.count >= 2 {
                location = CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
            }
        }
        lastCheckin = try container.decode(Date.self, forKey: .lastCheckin)
        capabilities = try container.decode([String].self, forKey: .capabilities)
        battery = try container.decode(Int.self, forKey: .battery)
    }
    
    init(id: UUID = UUID(), callsign: String, role: UnitRole = .rescue, status: UnitStatus = .available, location: CLLocationCoordinate2D? = nil, lastCheckin: Date = Date(), capabilities: [String] = [], battery: Int = 100) {
        self.id = id
        self.callsign = callsign
        self.role = role
        self.status = status
        self.location = location
        self.lastCheckin = lastCheckin
        self.capabilities = capabilities
        self.battery = battery
    }
}

struct Assignment: Identifiable, Codable {
    var id: UUID = UUID()
    var unitId: UUID
    var incidentId: UUID
    var assignedAt: Date = Date()
    var eta: Date?
    var note: String = ""
}

@MainActor
final class IncidentStore: ObservableObject {
    static let shared = IncidentStore()

    @Published var incidents: [Incident] = []
    @Published var units: [Unit] = []
    @Published var assignments: [Assignment] = []
    @Published var lastError: String?

    private var cancellables = Set<AnyCancellable>()
    private var staleCheckTimer: Timer?

    private init() {
        setupSubscriptions()
        startStaleCheck()
    }

    private func setupSubscriptions() {
        // Subscribe to mesh peers and populate units
        MeshService.shared.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.updateUnitsFromMeshPeers(peers)
            }
            .store(in: &cancellables)

        // Subscribe to TAK peers and populate units
        FreeTAKConnector.shared.$peers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] takPeers in
                self?.updateUnitsFromTAKPeers(takPeers)
            }
            .store(in: &cancellables)
    }

    func createIncident(title: String, summary: String, coordinate: CLLocationCoordinate2D,
                       priority: IncidentPriority = .medium, reporter: String = AppConfig.deviceCallsign) {
        let incident = Incident(
            uid: UUID().uuidString,
            title: title,
            summary: summary,
            coordinate: coordinate,
            reporter: reporter,
            priority: priority
        )

        incidents.append(incident)

        // Broadcast as CoT emergency marker
        broadcastIncidentAsCoT(incident)
    }

    func assignUnit(_ unitId: UUID, to incidentId: UUID, eta: Date? = nil, note: String = "") {
        guard let incidentIndex = incidents.firstIndex(where: { $0.id == incidentId }) else { return }
        guard let unitIndex = units.firstIndex(where: { $0.id == unitId }) else { return }

        let assignment = Assignment(
            unitId: unitId,
            incidentId: incidentId,
            eta: eta,
            note: note
        )

        assignments.append(assignment)
        incidents[incidentIndex].assignments.append(assignment)
        units[unitIndex].status = .assigned
    }

    func resolveIncident(_ id: UUID) {
        if let index = incidents.firstIndex(where: { $0.id == id }) {
            incidents[index].status = .resolved

            // Clear assignments for this incident
            assignments.removeAll { $0.incidentId == id }
            for i in incidents[index].assignments.indices {
                incidents[index].assignments[i].id = UUID()  // Mark for cleanup
            }
        }
    }

    func checkInUnit(callsign: String, coordinate: CLLocationCoordinate2D, battery: Int = 100) {
        if let index = units.firstIndex(where: { $0.callsign == callsign }) {
            units[index].location = coordinate
            units[index].lastCheckin = Date()
            units[index].battery = battery
            units[index].status = .onScene
        } else {
            let unit = Unit(
                callsign: callsign,
                location: coordinate,
                battery: battery
            )
            units.append(unit)
        }
    }

    private func updateUnitsFromMeshPeers(_ peers: [ZDPeer]) {
        for peer in peers {
            if let index = units.firstIndex(where: { $0.callsign == peer.name }) {
                units[index].location = peer.location
                units[index].lastCheckin = Date()
                units[index].status = .available
            } else {
                let unit = Unit(
                    callsign: peer.name,
                    location: peer.location,
                    lastCheckin: Date(),
                    battery: peer.batteryLevel ?? 100
                )
                units.append(unit)
            }
        }
    }

    private func updateUnitsFromTAKPeers(_ takPeers: [CoTEvent]) {
        for peer in takPeers {
            let callsign = peer.detail?.contact?.callsign ?? "TAK-\(peer.uid.prefix(8))"
            if let index = units.firstIndex(where: { $0.callsign == callsign }) {
                units[index].location = CLLocationCoordinate2D(latitude: peer.lat, longitude: peer.lon)
                units[index].lastCheckin = Date()
                units[index].status = .available
                if let battery = peer.detail?.status?.battery {
                    units[index].battery = battery
                }
            } else {
                let unit = Unit(
                    callsign: callsign,
                    location: CLLocationCoordinate2D(latitude: peer.lat, longitude: peer.lon),
                    lastCheckin: Date(),
                    battery: peer.detail?.status?.battery ?? 100
                )
                units.append(unit)
            }
        }
    }

    private func broadcastIncidentAsCoT(_ incident: Incident) {
        // Only broadcast SOS for critical incidents
        if incident.priority == .critical {
            FreeTAKConnector.shared.sendSOS(
                coordinate: incident.coordinate,
                callsign: incident.reporter
            )
            MeshService.shared.broadcastSOS()
        } else {
            // For other priorities, send standard presence/location marker
            // This notifies the network of the incident without emergency activation
            // PLACEHOLDER: would send CoT location marker (b-m-p-s-p-i) via FreeTAKConnector
        }
    }

    private func startStaleCheck() {
        staleCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.removeStaleIncidents()
        }
    }

    private func removeStaleIncidents() {
        let now = Date()
        incidents.removeAll { $0.staleTime < now }
    }

    deinit {
        staleCheckTimer?.invalidate()
    }
}
