// SwiftDataModels.swift — @Model classes for Ops/Coordination/AAR persistence
//
// V1 P0 #5: Persistence migration target. These @Model classes mirror the existing
// Codable structs in TeamRoster.swift, AarBuilder.swift, and IncidentStore.swift.
//
// MIGRATION STATUS: SCAFFOLDED + WIRING READY.
// To activate:
//   1. Add this file to ZeroDark.xcodeproj via Xcode Project Navigator (drag & drop, target ZeroDark)
//   2. In ZeroDarkApp.swift, attach the modifier:
//        WindowGroup { ContentView() }
//          .modelContainer(ZeroDarkModelContainer.shared)
//   3. On first launch, ZeroDarkMigration.migrateLegacyJSONIfNeeded(into:) auto-imports
//      the existing JSON files (team_roster.json, aar_reports.json) into SwiftData.
//
// Why this design: existing managers (TeamRosterManager, AARManager, IncidentStore)
// have ~700+ lines of working logic — CRUD, mesh sync, PDF export, CoT broadcast.
// Cutting them over wholesale risks regressing v1. This file gives us a SwiftData
// foundation alongside the JSON-backed managers; subsequent PRs migrate one manager
// at a time, each shippable on its own.

import Foundation
import SwiftData
import CoreLocation

// MARK: - TeamMember

@Model
final class TeamMemberModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var callsign: String
    var roleRaw: String        // TeamMember.TeamRole.rawValue
    var radioChannel: Int
    var bloodTypeRaw: String   // TeamMember.BloodType.rawValue
    var allergies: [String]
    var emergencyContact: String
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        callsign: String,
        roleRaw: String,
        radioChannel: Int,
        bloodTypeRaw: String,
        allergies: [String] = [],
        emergencyContact: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.callsign = callsign
        self.roleRaw = roleRaw
        self.radioChannel = radioChannel
        self.bloodTypeRaw = bloodTypeRaw
        self.allergies = allergies
        self.emergencyContact = emergencyContact
        self.notes = notes
    }
}

// MARK: - After Action Report

@Model
final class AfterActionReportModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var missionDate: Date
    var location: String
    var participants: [String]      // callsigns
    var createdAt: Date
    var createdBy: String

    @Relationship(deleteRule: .cascade, inverse: \AAREntryModel.report)
    var entries: [AAREntryModel] = []

    init(
        id: UUID = UUID(),
        title: String,
        missionDate: Date,
        location: String,
        participants: [String] = [],
        createdAt: Date = Date(),
        createdBy: String
    ) {
        self.id = id
        self.title = title
        self.missionDate = missionDate
        self.location = location
        self.participants = participants
        self.createdAt = createdAt
        self.createdBy = createdBy
    }
}

@Model
final class AAREntryModel {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var sectionRaw: String          // AARSection.rawValue
    var content: String
    var addedBy: String
    var sourceRaw: String           // AAREntrySource.rawValue ("Auto" | "Manual")
    var latitude: Double?
    var longitude: Double?

    var report: AfterActionReportModel?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sectionRaw: String,
        content: String,
        addedBy: String,
        sourceRaw: String = "Manual",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sectionRaw = sectionRaw
        self.content = content
        self.addedBy = addedBy
        self.sourceRaw = sourceRaw
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Incident / Unit / Assignment

@Model
final class IncidentModel {
    @Attribute(.unique) var id: UUID
    var uid: String                 // CoT uid for mesh broadcast
    var title: String
    var summary: String
    var latitude: Double            // CLLocationCoordinate2D split into doubles
    var longitude: Double
    var timestamp: Date
    var staleTime: Date             // when incident auto-expires
    var statusRaw: String           // IncidentStatus.rawValue
    var priorityRaw: String         // IncidentPriority.rawValue
    var reporter: String

    @Relationship(deleteRule: .cascade, inverse: \AssignmentModel.incident)
    var assignments: [AssignmentModel] = []

    init(
        id: UUID = UUID(),
        uid: String = UUID().uuidString,
        title: String,
        summary: String,
        latitude: Double,
        longitude: Double,
        timestamp: Date = Date(),
        staleTime: Date? = nil,
        statusRaw: String = "Active",
        priorityRaw: String = "Medium",
        reporter: String
    ) {
        self.id = id
        self.uid = uid
        self.title = title
        self.summary = summary
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.staleTime = staleTime ?? Date(timeIntervalSinceNow: 7200)
        self.statusRaw = statusRaw
        self.priorityRaw = priorityRaw
        self.reporter = reporter
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@Model
final class UnitModel {
    @Attribute(.unique) var id: UUID
    var callsign: String
    var roleRaw: String             // UnitRole.rawValue
    var statusRaw: String           // UnitStatus.rawValue
    var latitude: Double?
    var longitude: Double?
    var lastCheckin: Date
    var capabilities: [String]
    var battery: Int

    init(
        id: UUID = UUID(),
        callsign: String,
        roleRaw: String = "Rescue",
        statusRaw: String = "Available",
        latitude: Double? = nil,
        longitude: Double? = nil,
        lastCheckin: Date = Date(),
        capabilities: [String] = [],
        battery: Int = 100
    ) {
        self.id = id
        self.callsign = callsign
        self.roleRaw = roleRaw
        self.statusRaw = statusRaw
        self.latitude = latitude
        self.longitude = longitude
        self.lastCheckin = lastCheckin
        self.capabilities = capabilities
        self.battery = battery
    }

    var location: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

@Model
final class AssignmentModel {
    @Attribute(.unique) var id: UUID
    var unitId: UUID
    var assignedAt: Date
    var eta: Date?
    var note: String

    var incident: IncidentModel?

    init(
        id: UUID = UUID(),
        unitId: UUID,
        assignedAt: Date = Date(),
        eta: Date? = nil,
        note: String = ""
    ) {
        self.id = id
        self.unitId = unitId
        self.assignedAt = assignedAt
        self.eta = eta
        self.note = note
    }
}

// MARK: - Schema Bundle

/// Convenience for ModelContainer setup in app entry.
public enum ZeroDarkSchema {
    public static let allModels: [any PersistentModel.Type] = [
        TeamMemberModel.self,
        AfterActionReportModel.self,
        AAREntryModel.self,
        IncidentModel.self,
        UnitModel.self,
        AssignmentModel.self
    ]
}

// MARK: - ModelContainer Singleton

/// Shared SwiftData container for ZeroDark.
/// Falls back to in-memory store if disk persistence fails (rare; usually means
/// disk is full or sandboxed). Prepper-friendly: at least the session works.
@MainActor
public enum ZeroDarkModelContainer {
    public static let shared: ModelContainer = {
        let schema = Schema(ZeroDarkSchema.allModels)
        let onDisk = ModelConfiguration("ZeroDark", schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [onDisk])
            // Run one-shot legacy migration on first SwiftData launch.
            ZeroDarkMigration.migrateLegacyJSONIfNeeded(into: container)
            return container
        } catch {
            // Disk store failed — fall back to in-memory so the app still functions
            // for the session (loses persistence but lets the user continue).
            #if DEBUG
            print("[ZeroDarkModelContainer] WARNING: disk store failed (\(error)). Falling back to in-memory.")
            #endif
            let inMem = ModelConfiguration("ZeroDark-mem", schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [inMem])
        }
    }()
}

// MARK: - Legacy JSON → SwiftData Migration

/// One-shot migration that reads the existing JSON files written by
/// TeamRosterManager and AARManager and imports them into SwiftData.
///
/// Idempotent: gated by UserDefaults flag, runs once per device.
/// Non-destructive: leaves the original JSON files in place. The legacy
/// managers can continue running alongside SwiftData until they're cut over.
public enum ZeroDarkMigration {
    private static let migrationFlagKey = "ZeroDark.SwiftData.LegacyMigration.v1.complete"

    public static func migrateLegacyJSONIfNeeded(into container: ModelContainer) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlagKey) else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let context = ModelContext(container)
        var importedTeam = 0
        var importedAARs = 0

        // Team roster
        let rosterURL = docs.appendingPathComponent("team_roster.json")
        if let data = try? Data(contentsOf: rosterURL),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for dict in raw {
                guard let idStr = dict["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = dict["name"] as? String,
                      let callsign = dict["callsign"] as? String,
                      let role = dict["role"] as? String,
                      let radioChannel = dict["radioChannel"] as? Int,
                      let bloodType = dict["bloodType"] as? String else { continue }
                let allergies = dict["allergies"] as? [String] ?? []
                let emergency = dict["emergencyContact"] as? String ?? ""
                let notes = dict["notes"] as? String ?? ""
                context.insert(TeamMemberModel(
                    id: id, name: name, callsign: callsign,
                    roleRaw: role, radioChannel: radioChannel,
                    bloodTypeRaw: bloodType, allergies: allergies,
                    emergencyContact: emergency, notes: notes
                ))
                importedTeam += 1
            }
        }

        // AAR reports — preserve entry relationships
        let aarURL = docs.appendingPathComponent("aar_reports.json")
        if let data = try? Data(contentsOf: aarURL),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let isoDF = ISO8601DateFormatter()
            isoDF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackDF = ISO8601DateFormatter()

            func parseDate(_ value: Any?) -> Date? {
                if let d = value as? Date { return d }
                if let s = value as? String {
                    return isoDF.date(from: s) ?? fallbackDF.date(from: s)
                }
                if let n = value as? Double { return Date(timeIntervalSinceReferenceDate: n) }
                return nil
            }

            for reportDict in raw {
                guard let idStr = reportDict["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let title = reportDict["title"] as? String,
                      let missionDate = parseDate(reportDict["missionDate"]),
                      let location = reportDict["location"] as? String,
                      let createdBy = reportDict["createdBy"] as? String else { continue }
                let participants = reportDict["participants"] as? [String] ?? []
                let createdAt = parseDate(reportDict["createdAt"]) ?? Date()

                let report = AfterActionReportModel(
                    id: id, title: title, missionDate: missionDate,
                    location: location, participants: participants,
                    createdAt: createdAt, createdBy: createdBy
                )
                context.insert(report)

                if let entries = reportDict["entries"] as? [[String: Any]] {
                    for entryDict in entries {
                        guard let entIdStr = entryDict["id"] as? String,
                              let entId = UUID(uuidString: entIdStr),
                              let section = entryDict["section"] as? String,
                              let content = entryDict["content"] as? String,
                              let addedBy = entryDict["addedBy"] as? String else { continue }
                        let timestamp = parseDate(entryDict["timestamp"]) ?? Date()
                        let source = (entryDict["source"] as? String) ?? "Manual"
                        let lat = entryDict["latitude"] as? Double
                        let lon = entryDict["longitude"] as? Double

                        let entry = AAREntryModel(
                            id: entId, timestamp: timestamp,
                            sectionRaw: section, content: content,
                            addedBy: addedBy, sourceRaw: source,
                            latitude: lat, longitude: lon
                        )
                        entry.report = report
                        context.insert(entry)
                    }
                }
                importedAARs += 1
            }
        }

        do {
            try context.save()
            defaults.set(true, forKey: migrationFlagKey)
            #if DEBUG
            print("[ZeroDarkMigration] imported \(importedTeam) team member(s), \(importedAARs) AAR(s) into SwiftData")
            #endif
        } catch {
            #if DEBUG
            print("[ZeroDarkMigration] save failed: \(error). Will retry on next launch.")
            #endif
        }
    }

    /// Force a re-migration (clears the completion flag). For debugging only.
    public static func resetMigrationFlag() {
        UserDefaults.standard.removeObject(forKey: migrationFlagKey)
    }
}
