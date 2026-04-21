// MARCHAssessment.swift — TCCC MARCH decision tree data model.
//
// MARCH is the TCCC (Tactical Combat Casualty Care) primary-survey mnemonic:
//   M — Massive hemorrhage
//   A — Airway
//   R — Respiration
//   C — Circulation
//   H — Hypothermia / Head injury
//
// This file models each step as a short decision tree (observations → indicated
// interventions) without prescribing medication dosages. The view walks the
// operator through the steps in order; any positive finding pops the relevant
// intervention checklist. All findings + interventions land on a CasualtyCard.

import Foundation

// MARK: - Step

public enum MARCHStep: Int, CaseIterable, Codable, Identifiable {
    case massiveHemorrhage = 0
    case airway
    case respiration
    case circulation
    case hypothermia

    public var id: Int { rawValue }

    public var letter: String {
        switch self {
        case .massiveHemorrhage: return "M"
        case .airway:            return "A"
        case .respiration:       return "R"
        case .circulation:       return "C"
        case .hypothermia:       return "H"
        }
    }

    public var title: String {
        switch self {
        case .massiveHemorrhage: return "Massive Hemorrhage"
        case .airway:            return "Airway"
        case .respiration:       return "Respiration"
        case .circulation:       return "Circulation"
        case .hypothermia:       return "Hypothermia / Head"
        }
    }

    /// Observational questions the medic answers at this step. Order matters —
    /// the first positive finding short-circuits and triggers the corresponding
    /// intervention bundle; negatives move on to the next question.
    public var questions: [MARCHQuestion] {
        switch self {
        case .massiveHemorrhage:
            return [
                .init(prompt: "Life-threatening extremity bleed?",
                      positive: .arterialExtremity),
                .init(prompt: "Junctional (groin/axilla) bleed?",
                      positive: .junctional),
                .init(prompt: "Non-compressible torso bleed?",
                      positive: .torsoBleed)
            ]
        case .airway:
            return [
                .init(prompt: "Airway obstructed or at risk of obstruction?",
                      positive: .airwayAtRisk),
                .init(prompt: "Maxillofacial trauma?",
                      positive: .maxillofacialTrauma),
                .init(prompt: "Unconscious without gag reflex?",
                      positive: .unconscious)
            ]
        case .respiration:
            return [
                .init(prompt: "Penetrating torso trauma?",
                      positive: .penetratingTorso),
                .init(prompt: "Signs of tension pneumothorax (absent breath sounds, JVD, deviation)?",
                      positive: .tensionPneumo),
                .init(prompt: "Chest wall open / sucking?",
                      positive: .openChest)
            ]
        case .circulation:
            return [
                .init(prompt: "Palpable radial pulse?",
                      positive: .radialPulseAbsent,   // positive here means ABSENT
                      invertLogic: true),
                .init(prompt: "Altered mental status?",
                      positive: .alteredMental),
                .init(prompt: "Signs of hemorrhagic shock (pale, cool, delayed cap refill)?",
                      positive: .shock)
            ]
        case .hypothermia:
            return [
                .init(prompt: "Exposed to cold / wet / wind?",
                      positive: .coldExposure),
                .init(prompt: "Head injury / any LOC?",
                      positive: .headInjury)
            ]
        }
    }
}

// MARK: - Question

public struct MARCHQuestion: Identifiable, Codable, Hashable {
    public let id: UUID
    public let prompt: String
    public let positive: MARCHFinding
    /// When true, a "No" answer fires the finding (e.g. "radial pulse absent").
    public let invertLogic: Bool

    public init(prompt: String, positive: MARCHFinding, invertLogic: Bool = false) {
        self.id = UUID()
        self.prompt = prompt
        self.positive = positive
        self.invertLogic = invertLogic
    }
}

// MARK: - Finding

public enum MARCHFinding: String, Codable, CaseIterable {
    // Hemorrhage
    case arterialExtremity, junctional, torsoBleed
    // Airway
    case airwayAtRisk, maxillofacialTrauma, unconscious
    // Respiration
    case penetratingTorso, tensionPneumo, openChest
    // Circulation
    case radialPulseAbsent, alteredMental, shock
    // Hypothermia / Head
    case coldExposure, headInjury

    public var indicatedInterventions: [MARCHIntervention] {
        switch self {
        case .arterialExtremity:    return [.tourniquet]
        case .junctional:           return [.junctionalTourniquet, .woundPacking]
        case .torsoBleed:           return [.xstatHemostaticGauze, .rapidEvac]
        case .airwayAtRisk:         return [.headTiltChinLift, .nasopharyngealAirway]
        case .maxillofacialTrauma:  return [.nasopharyngealAirway, .positionUpright]
        case .unconscious:          return [.recoveryPosition, .nasopharyngealAirway]
        case .penetratingTorso:     return [.ventedChestSeal, .monitorTensionPneumo]
        case .tensionPneumo:        return [.needleDecompression]
        case .openChest:            return [.ventedChestSeal]
        case .radialPulseAbsent:    return [.ivAccess, .fluidsIfIndicated, .rapidEvac]
        case .alteredMental:        return [.ivAccess, .reassessABC]
        case .shock:                return [.ivAccess, .fluidsIfIndicated, .preventHypothermia, .rapidEvac]
        case .coldExposure:         return [.preventHypothermia]
        case .headInjury:           return [.headUp30, .preventHypothermia, .monitorGCS]
        }
    }
}

// MARK: - Intervention

public enum MARCHIntervention: String, Codable, CaseIterable {
    case tourniquet
    case junctionalTourniquet
    case woundPacking
    case xstatHemostaticGauze
    case headTiltChinLift
    case nasopharyngealAirway
    case recoveryPosition
    case positionUpright
    case ventedChestSeal
    case needleDecompression
    case monitorTensionPneumo
    case ivAccess
    case fluidsIfIndicated
    case preventHypothermia
    case headUp30
    case monitorGCS
    case reassessABC
    case rapidEvac

    public var displayName: String {
        switch self {
        case .tourniquet:             return "Apply limb tourniquet"
        case .junctionalTourniquet:   return "Junctional tourniquet"
        case .woundPacking:           return "Wound packing + pressure"
        case .xstatHemostaticGauze:   return "Hemostatic gauze (XStat / Combat Gauze)"
        case .headTiltChinLift:       return "Head-tilt / chin-lift"
        case .nasopharyngealAirway:   return "Nasopharyngeal airway"
        case .recoveryPosition:       return "Recovery position"
        case .positionUpright:        return "Position upright / forward"
        case .ventedChestSeal:        return "Vented chest seal"
        case .needleDecompression:    return "Needle decompression"
        case .monitorTensionPneumo:   return "Monitor for tension pneumo"
        case .ivAccess:               return "IV / IO access"
        case .fluidsIfIndicated:      return "TCCC-indicated fluids"
        case .preventHypothermia:     return "Prevent hypothermia (HPMK)"
        case .headUp30:               return "Head of bed up 30°"
        case .monitorGCS:             return "Monitor GCS q5min"
        case .reassessABC:            return "Reassess ABC"
        case .rapidEvac:              return "Rapid 9-line evac"
        }
    }
}

// MARK: - Casualty record

public struct CasualtyCard: Codable, Identifiable {
    public let id: UUID
    public var callsign: String
    public var unit: String
    public var mechanism: String        // "GSW left thigh", "Fall 4m", "Blast"
    public var timeOfInjury: Date
    public var findings: [MARCHFinding]
    public var interventionsLogged: [LoggedIntervention]
    public var vitals: [VitalsSnapshot]
    public var notes: String

    public init(
        id: UUID = UUID(),
        callsign: String = "",
        unit: String = "",
        mechanism: String = "",
        timeOfInjury: Date = .init(),
        findings: [MARCHFinding] = [],
        interventionsLogged: [LoggedIntervention] = [],
        vitals: [VitalsSnapshot] = [],
        notes: String = ""
    ) {
        self.id = id
        self.callsign = callsign
        self.unit = unit
        self.mechanism = mechanism
        self.timeOfInjury = timeOfInjury
        self.findings = findings
        self.interventionsLogged = interventionsLogged
        self.vitals = vitals
        self.notes = notes
    }

    public struct LoggedIntervention: Codable, Identifiable, Hashable {
        public let id: UUID
        public let intervention: MARCHIntervention
        public let timestamp: Date
        public var location: String       // "left mid-thigh", "right chest 2nd ICS MCL"
        public var performedBy: String

        public init(
            intervention: MARCHIntervention,
            timestamp: Date = .init(),
            location: String = "",
            performedBy: String = ""
        ) {
            self.id = UUID()
            self.intervention = intervention
            self.timestamp = timestamp
            self.location = location
            self.performedBy = performedBy
        }
    }

    public struct VitalsSnapshot: Codable, Identifiable, Hashable {
        public let id: UUID
        public let timestamp: Date
        public var heartRate: Int?
        public var systolicBP: Int?
        public var spo2: Int?
        public var respirationRate: Int?
        public var gcs: Int?

        public init(
            timestamp: Date = .init(),
            heartRate: Int? = nil,
            systolicBP: Int? = nil,
            spo2: Int? = nil,
            respirationRate: Int? = nil,
            gcs: Int? = nil
        ) {
            self.id = UUID()
            self.timestamp = timestamp
            self.heartRate = heartRate
            self.systolicBP = systolicBP
            self.spo2 = spo2
            self.respirationRate = respirationRate
            self.gcs = gcs
        }
    }
}

// MARK: - Store

@MainActor
public final class CasualtyCardStore: ObservableObject {
    public static let shared = CasualtyCardStore()
    @Published public private(set) var cards: [CasualtyCard] = []

    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("casualty_cards.json")
    }()

    private init() { load() }

    public func upsert(_ card: CasualtyCard) {
        if let idx = cards.firstIndex(where: { $0.id == card.id }) {
            cards[idx] = card
        } else {
            cards.insert(card, at: 0)
        }
        save()
    }

    public func delete(_ id: UUID) {
        cards.removeAll { $0.id == id }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(cards) {
            try? data.write(to: saveURL, options: [.atomic, .completeFileProtection])
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? decoder.decode([CasualtyCard].self, from: data) else { return }
        cards = decoded
    }
}
