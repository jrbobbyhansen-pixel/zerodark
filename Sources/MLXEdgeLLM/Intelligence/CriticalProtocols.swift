// CriticalProtocols.swift
// ZeroDark — Instant Protocol Cards for Life-or-Death Situations
// No AI generation. Pre-verified. Sub-100ms response.

import Foundation
import SwiftUI

// MARK: - Protocol Model

struct TacticalProtocol: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let category: ProtocolCategory
    let severity: Severity
    let timeframe: String  // "IMMEDIATE", "1-5 MIN", "WHEN ABLE"
    let steps: [ProtocolStep]
    let warnings: [String]
    let keywords: [String]  // For instant matching
    
    enum Severity: String, CaseIterable {
        case critical = "CRITICAL"    // Life-threatening, seconds matter
        case urgent = "URGENT"        // Important, minutes matter
        case priority = "PRIORITY"    // Do soon, but stable
        case routine = "ROUTINE"      // Standard procedure
        
        var color: Color {
            switch self {
            case .critical: return ZDDesign.signalRed
            case .urgent: return ZDDesign.sunsetOrange
            case .priority: return ZDDesign.safetyYellow
            case .routine: return ZDDesign.skyBlue
            }
        }
        
        var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .urgent: return "exclamationmark.circle.fill"
            case .priority: return "clock.fill"
            case .routine: return "checkmark.circle.fill"
            }
        }
    }
}

struct ProtocolStep: Hashable {
    let number: Int
    let action: String      // Bold action verb
    let detail: String      // Specifics
    let timing: String?     // Optional timing info
}

enum ProtocolCategory: String, CaseIterable, Identifiable {
    case medical = "Medical"
    case trauma = "Trauma"
    case recon = "Recon"
    case positions = "Positions"
    case movement = "Movement"
    case survival = "Survival"
    case navigation = "Navigation"
    case communication = "Comms"
    case evasion = "Evasion"
    case weapons = "Weapons"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .medical: return "cross.fill"
        case .trauma: return "bandage.fill"
        case .recon: return "binoculars.fill"
        case .positions: return "shield.fill"
        case .movement: return "figure.walk"
        case .survival: return "flame.fill"
        case .navigation: return "location.north.fill"
        case .communication: return "antenna.radiowaves.left.and.right"
        case .evasion: return "eye.slash.fill"
        case .weapons: return "scope"
        }
    }
    
    var color: Color {
        switch self {
        case .medical, .trauma: return ZDDesign.signalRed
        case .recon: return ZDDesign.cyanAccent
        case .positions: return ZDDesign.forestGreen
        case .movement: return ZDDesign.skyBlue
        case .survival: return ZDDesign.sunsetOrange
        case .navigation: return ZDDesign.safetyYellow
        case .communication: return ZDDesign.darkSage
        case .evasion: return ZDDesign.warmGray
        case .weapons: return ZDDesign.mediumGray
        }
    }
}

// MARK: - Protocol Database

@MainActor
final class ProtocolDatabase: ObservableObject {
    static let shared = ProtocolDatabase()
    
    @Published private(set) var protocols: [TacticalProtocol] = []
    private var isLoaded = false
    
    private init() {
        // Lazy load — don't load until first access
    }
    
    func ensureLoaded() {
        guard !isLoaded else { return }
        loadAllProtocols()
        isLoaded = true
    }
    
    // MARK: - Instant Lookup (<100ms)
    
    func search(query: String) -> [TacticalProtocol] {
        ensureLoaded()
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Exact keyword match first (fastest)
        let exactMatches = protocols.filter { proto in
            proto.keywords.contains { $0.lowercased() == normalizedQuery }
        }
        if !exactMatches.isEmpty { return exactMatches }
        
        // Partial keyword match
        let partialMatches = protocols.filter { proto in
            proto.keywords.contains { $0.lowercased().contains(normalizedQuery) } ||
            proto.title.lowercased().contains(normalizedQuery)
        }
        return partialMatches
    }
    
    func quickMatch(query: String) -> TacticalProtocol? {
        search(query: query).first
    }
    
    func protocols(for category: ProtocolCategory) -> [TacticalProtocol] {
        ensureLoaded()
        return protocols.filter { $0.category == category }
    }
    
    // MARK: - Load All Protocols
    
    private func loadAllProtocols() {
        protocols = [
            // ═══════════════════════════════════════════════════════════════
            // TRAUMA / TCCC PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Sucking Chest Wound",
                category: .trauma,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "SEAL", detail: "Apply occlusive dressing (chest seal, plastic, tape). Tape 3 sides only — creates flutter valve", timing: "0-30 sec"),
                    ProtocolStep(number: 2, action: "POSITION", detail: "Injured side DOWN if conscious. Recovery position if unconscious", timing: nil),
                    ProtocolStep(number: 3, action: "MONITOR", detail: "Watch for tension pneumo: increasing difficulty breathing, JVD, tracheal deviation", timing: "Continuous"),
                    ProtocolStep(number: 4, action: "BURP", detail: "If breathing worsens, lift corner of seal to release pressure, then reseal", timing: "As needed"),
                    ProtocolStep(number: 5, action: "EVACUATE", detail: "This is life-threatening. Prioritize immediate CASEVAC", timing: "ASAP")
                ],
                warnings: [
                    "Tension pneumothorax can kill in minutes",
                    "Both entry AND exit wounds need sealing",
                    "If no chest seal available: credit card + tape works"
                ],
                keywords: ["chest wound", "sucking chest", "pneumothorax", "chest seal", "lung", "breathing hole", "chest injury"]
            ),
            
            TacticalProtocol(
                title: "Tourniquet Application",
                category: .trauma,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "HIGH & TIGHT", detail: "Place 2-3 inches above wound, over clothing is OK. Never over a joint", timing: "0-15 sec"),
                    ProtocolStep(number: 2, action: "TIGHTEN", detail: "Pull band tight, twist windlass until bleeding STOPS", timing: "15-30 sec"),
                    ProtocolStep(number: 3, action: "LOCK", detail: "Secure windlass in clip. Bleeding must be completely stopped", timing: nil),
                    ProtocolStep(number: 4, action: "MARK TIME", detail: "Write 'T' and time on forehead or tourniquet. Example: T 14:32", timing: nil),
                    ProtocolStep(number: 5, action: "DO NOT REMOVE", detail: "Only medical personnel remove tourniquets. Leave it on.", timing: nil)
                ],
                warnings: [
                    "If still bleeding: tighten more or add second TQ 2\" above first",
                    "Pain is expected — it means it's working",
                    "2-hour limit is a myth in tactical settings — leave it on"
                ],
                keywords: ["tourniquet", "tq", "bleeding", "arterial", "limb bleeding", "severe bleeding", "blood loss", "hemorrhage"]
            ),
            
            TacticalProtocol(
                title: "CPR - Adult",
                category: .medical,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "CHECK", detail: "Tap shoulders, shout. No response = start CPR", timing: "5 sec"),
                    ProtocolStep(number: 2, action: "POSITION", detail: "Flat on back, hard surface. Kneel beside chest", timing: nil),
                    ProtocolStep(number: 3, action: "COMPRESS", detail: "Heel of hand center of chest, other hand on top. Push hard & fast: 2 inches deep, 100-120/min", timing: "30 compressions"),
                    ProtocolStep(number: 4, action: "BREATHS", detail: "Tilt head, lift chin, seal mouth, 2 breaths (1 sec each). Watch chest rise", timing: "2 breaths"),
                    ProtocolStep(number: 5, action: "REPEAT", detail: "Continue 30:2 cycle until: they respond, help arrives, or you physically cannot continue", timing: "Continuous")
                ],
                warnings: [
                    "Compressions-only CPR is acceptable if you can't/won't give breaths",
                    "Push hard enough to break ribs — that's normal",
                    "Don't stop for pulse checks"
                ],
                keywords: ["cpr", "cardiac arrest", "heart stopped", "not breathing", "unconscious", "no pulse", "resuscitation"]
            ),
            
            TacticalProtocol(
                title: "Severe Bleeding Control",
                category: .trauma,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "DIRECT PRESSURE", detail: "Gloved hand or cloth directly on wound. Press HARD", timing: "0-10 sec"),
                    ProtocolStep(number: 2, action: "PACK THE WOUND", detail: "Stuff gauze/cloth INTO the wound cavity, maintain pressure", timing: "10-30 sec"),
                    ProtocolStep(number: 3, action: "PRESSURE DRESSING", detail: "Wrap tightly. If blood soaks through, add more — don't remove", timing: nil),
                    ProtocolStep(number: 4, action: "TOURNIQUET", detail: "If limb + direct pressure fails → tourniquet immediately", timing: "If needed"),
                    ProtocolStep(number: 5, action: "ELEVATE", detail: "Raise injured limb above heart if possible (not for fractures)", timing: nil)
                ],
                warnings: [
                    "Junctional wounds (groin, armpit, neck) can't be tourniqueted — pack and hold pressure",
                    "Don't waste time on ineffective pressure — go to TQ fast",
                    "Bright red spurting = arterial = tourniquet NOW"
                ],
                keywords: ["bleeding", "blood", "hemorrhage", "wound", "cut", "laceration", "bleeding control"]
            ),
            
            TacticalProtocol(
                title: "Airway - Unconscious Casualty",
                category: .medical,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "HEAD TILT", detail: "Hand on forehead, tilt head back gently", timing: "2 sec"),
                    ProtocolStep(number: 2, action: "CHIN LIFT", detail: "Fingers under bony chin, lift up. Opens airway", timing: nil),
                    ProtocolStep(number: 3, action: "CLEAR", detail: "Finger sweep only if you SEE obstruction. Don't blind sweep", timing: nil),
                    ProtocolStep(number: 4, action: "CHECK", detail: "Look, listen, feel for breathing. 10 seconds max", timing: "10 sec"),
                    ProtocolStep(number: 5, action: "RECOVERY", detail: "If breathing: roll to recovery position (side) to prevent choking", timing: nil)
                ],
                warnings: [
                    "If suspected neck injury: jaw thrust only, no head tilt",
                    "Snoring = partial obstruction, reposition",
                    "Insert NPA if available and trained"
                ],
                keywords: ["airway", "unconscious", "breathing", "choking", "unresponsive", "passed out", "not breathing"]
            ),
            
            TacticalProtocol(
                title: "Fracture Immobilization",
                category: .trauma,
                severity: .urgent,
                timeframe: "1-5 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "ASSESS", detail: "Deformity, swelling, pain, crepitus (grinding). Check pulse below injury", timing: nil),
                    ProtocolStep(number: 2, action: "IMMOBILIZE", detail: "Splint in position found. Include joint above AND below fracture", timing: nil),
                    ProtocolStep(number: 3, action: "PAD", detail: "Fill gaps between limb and splint with soft material", timing: nil),
                    ProtocolStep(number: 4, action: "SECURE", detail: "Tie firmly but not tight enough to cut circulation", timing: nil),
                    ProtocolStep(number: 5, action: "RECHECK", detail: "Pulse, sensation, movement below splint. Check every 15 min", timing: "Every 15 min")
                ],
                warnings: [
                    "Open fractures: cover bone with moist sterile dressing first",
                    "No pulse after splinting = loosen and reposition",
                    "Don't try to straighten angulated fractures in field"
                ],
                keywords: ["fracture", "broken bone", "break", "splint", "deformity", "bone sticking out", "open fracture"]
            ),
            
            TacticalProtocol(
                title: "Shock Management",
                category: .medical,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "STOP BLEEDING", detail: "Control all external hemorrhage first — this is the cause", timing: "First"),
                    ProtocolStep(number: 2, action: "POSITION", detail: "Lay flat, elevate legs 6-12 inches (unless head/chest injury)", timing: nil),
                    ProtocolStep(number: 3, action: "WARM", detail: "Prevent heat loss. Cover with blanket, insulate from ground", timing: nil),
                    ProtocolStep(number: 4, action: "CALM", detail: "Reassure casualty. Anxiety worsens shock", timing: nil),
                    ProtocolStep(number: 5, action: "NOTHING BY MOUTH", detail: "No food, no water — they may need surgery", timing: nil)
                ],
                warnings: [
                    "Signs: pale/cold/clammy skin, rapid weak pulse, confusion, thirst",
                    "Shock kills — treat aggressively even if injury seems minor",
                    "Pregnant women: tilt left side to prevent compression"
                ],
                keywords: ["shock", "pale", "cold", "clammy", "weak pulse", "confused", "blood loss shock"]
            ),
            
            TacticalProtocol(
                title: "Burns Treatment",
                category: .trauma,
                severity: .urgent,
                timeframe: "1-5 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "STOP BURNING", detail: "Remove from heat source. Remove clothing/jewelry near burn (not if stuck)", timing: "Immediate"),
                    ProtocolStep(number: 2, action: "COOL", detail: "Cool water 10-20 min. NOT ice, NOT butter", timing: "10-20 min"),
                    ProtocolStep(number: 3, action: "COVER", detail: "Loose sterile dressing. Cling film works. Don't break blisters", timing: nil),
                    ProtocolStep(number: 4, action: "ELEVATE", detail: "Raise burned limbs to reduce swelling", timing: nil),
                    ProtocolStep(number: 5, action: "FLUIDS", detail: "If conscious and burns >20% body: small sips of water", timing: nil)
                ],
                warnings: [
                    "Airway burns (singed nose hair, soot in mouth) = CRITICAL priority",
                    "Circumferential burns can cut off circulation — monitor distal pulses",
                    "Chemical burns: brush off dry chemical first, then flush 20+ min"
                ],
                keywords: ["burn", "burns", "fire", "scald", "chemical burn", "thermal", "burned"]
            ),
            
            TacticalProtocol(
                title: "Snake Bite",
                category: .medical,
                severity: .urgent,
                timeframe: "1-5 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "MOVE AWAY", detail: "Get away from snake. Don't try to catch or kill it", timing: "Immediate"),
                    ProtocolStep(number: 2, action: "IMMOBILIZE", detail: "Keep bitten limb still and below heart level", timing: nil),
                    ProtocolStep(number: 3, action: "REMOVE", detail: "Take off rings, watches, tight clothing near bite — swelling will come", timing: nil),
                    ProtocolStep(number: 4, action: "MARK", detail: "Circle the edge of swelling with pen, note time. Track progression", timing: nil),
                    ProtocolStep(number: 5, action: "EVACUATE", detail: "Get to medical facility. Carry victim if possible — don't let them walk", timing: "ASAP")
                ],
                warnings: [
                    "DO NOT: cut, suck, tourniquet, ice, or apply electric shock",
                    "Note snake appearance if safe — helps with antivenom selection",
                    "20% of bites are 'dry' — no venom. Still evacuate."
                ],
                keywords: ["snake", "snake bite", "venom", "venomous", "serpent", "bitten by snake"]
            ),
            
            TacticalProtocol(
                title: "Hypothermia",
                category: .medical,
                severity: .urgent,
                timeframe: "1-5 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "SHELTER", detail: "Get out of cold/wind/wet. Any shelter is better than none", timing: "Immediate"),
                    ProtocolStep(number: 2, action: "REMOVE WET", detail: "Take off wet clothing. Replace with dry layers", timing: nil),
                    ProtocolStep(number: 3, action: "INSULATE", detail: "Insulate from ground. Wrap in blankets, sleeping bag, emergency blanket", timing: nil),
                    ProtocolStep(number: 4, action: "WARM CORE", detail: "Apply heat to neck, armpits, groin. Warm (not hot) packs or body heat", timing: nil),
                    ProtocolStep(number: 5, action: "WARM FLUIDS", detail: "If conscious: warm sweet drinks. NO alcohol, NO caffeine", timing: nil)
                ],
                warnings: [
                    "Handle gently — rough movement can trigger cardiac arrest in severe hypothermia",
                    "Shivering stops when core temp drops below 90°F — this is worse, not better",
                    "Don't warm extremities first — drives cold blood to core"
                ],
                keywords: ["hypothermia", "cold", "freezing", "shivering", "cold exposure", "frostbite", "frozen"]
            ),
            
            TacticalProtocol(
                title: "Heat Stroke",
                category: .medical,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "SHADE", detail: "Move to coolest available location immediately", timing: "Immediate"),
                    ProtocolStep(number: 2, action: "STRIP", detail: "Remove excess clothing, especially restrictive gear", timing: nil),
                    ProtocolStep(number: 3, action: "COOL AGGRESSIVELY", detail: "Ice packs to neck, armpits, groin. Wet entire body, fan vigorously", timing: nil),
                    ProtocolStep(number: 4, action: "COLD WATER IMMERSION", detail: "If available: immerse in cold water up to neck. Best method", timing: nil),
                    ProtocolStep(number: 5, action: "MONITOR", detail: "Continue cooling until temp below 102°F or mental status improves", timing: "Until improved")
                ],
                warnings: [
                    "Heat stroke = altered mental status + hot skin. This is LIFE THREATENING",
                    "Don't give fluids if confused/unconscious",
                    "Core temp >104°F causes brain damage. Cool NOW."
                ],
                keywords: ["heat stroke", "heat exhaustion", "overheating", "hot", "dehydration", "passed out heat", "heat casualty"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // RECON PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Observation Post Setup",
                category: .recon,
                severity: .priority,
                timeframe: "5-15 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "SELECT POSITION", detail: "Covered, concealed, good sight lines. NOT on hilltop silhouette. Avoid obvious terrain features", timing: nil),
                    ProtocolStep(number: 2, action: "ESTABLISH SECTORS", detail: "Divide observable area into sectors (clock method). Assign primary/secondary areas", timing: nil),
                    ProtocolStep(number: 3, action: "RANGE ESTIMATION", detail: "Identify reference points at known distances: 100m, 300m, 500m markers", timing: nil),
                    ProtocolStep(number: 4, action: "ENTRY/EXIT", detail: "Plan covered approach and withdrawal routes. Never silhouette against sky", timing: nil),
                    ProtocolStep(number: 5, action: "LOG", detail: "Start observation log: time, grid, activity observed, direction of travel", timing: "Continuous")
                ],
                warnings: [
                    "Optics reflect light — use lens covers, stay in shadow",
                    "Movement draws eyes — minimize, slow when necessary",
                    "Plan relief/rotation before OP gets compromised"
                ],
                keywords: ["observation post", "op", "lookout", "watch", "surveillance", "overwatch", "scout position"]
            ),
            
            TacticalProtocol(
                title: "Area Reconnaissance",
                category: .recon,
                severity: .priority,
                timeframe: "30+ MIN",
                steps: [
                    ProtocolStep(number: 1, action: "MAP STUDY", detail: "Identify key terrain, likely enemy positions, water, cover, obstacles before moving", timing: "Pre-mission"),
                    ProtocolStep(number: 2, action: "ESTABLISH ORP", detail: "Set objective rally point 300-400m from target. Security, covered position", timing: nil),
                    ProtocolStep(number: 3, action: "LEADER'S RECON", detail: "Small element moves forward to confirm map info, identify approach routes", timing: nil),
                    ProtocolStep(number: 4, action: "SYSTEMATIC SCAN", detail: "Observe from multiple points. Document: activity, numbers, equipment, patterns", timing: nil),
                    ProtocolStep(number: 5, action: "EXFIL", detail: "Withdraw on alternate route. Link at ORP. Debrief and consolidate intel", timing: nil)
                ],
                warnings: [
                    "Never observe from just one point — your perspective is limited",
                    "Time observations: guards change, patrols have schedules",
                    "If compromised: break contact, rally at ORP, report"
                ],
                keywords: ["recon", "reconnaissance", "scout", "area recon", "patrol", "scouting", "survey area"]
            ),
            
            TacticalProtocol(
                title: "Route Reconnaissance",
                category: .recon,
                severity: .priority,
                timeframe: "VARIABLE",
                steps: [
                    ProtocolStep(number: 1, action: "MAP ROUTE", detail: "Plan primary + alternate routes. Identify danger areas: chokepoints, open terrain, bridges", timing: "Pre-mission"),
                    ProtocolStep(number: 2, action: "POINT ELEMENT", detail: "Lead element moves ahead, stops at danger areas, signals clear or threat", timing: nil),
                    ProtocolStep(number: 3, action: "CHECK POINTS", detail: "At each checkpoint: assess terrain, cover, enemy indicators, trafficability", timing: nil),
                    ProtocolStep(number: 4, action: "DOCUMENT", detail: "Note conditions: road surface, bridges (weight capacity), fords, obstacles, signs of activity", timing: nil),
                    ProtocolStep(number: 5, action: "REPORT", detail: "SALUTE format for any enemy contact. Full route brief on return", timing: nil)
                ],
                warnings: [
                    "Linear danger areas (roads) are high-risk crossing points",
                    "Don't use same route twice — patterns get you killed",
                    "Trail signs: fresh tracks, disturbed vegetation, litter = recent activity"
                ],
                keywords: ["route recon", "path finding", "trail", "road recon", "check route", "scout route", "advance route"]
            ),
            
            TacticalProtocol(
                title: "SALUTE Report",
                category: .recon,
                severity: .routine,
                timeframe: "1-2 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "SIZE", detail: "Number of personnel and vehicles. 'Squad-size element' or '3 vehicles'", timing: nil),
                    ProtocolStep(number: 2, action: "ACTIVITY", detail: "What are they doing? Moving, digging, patrolling, static?", timing: nil),
                    ProtocolStep(number: 3, action: "LOCATION", detail: "Grid coordinate or reference to known point. '300m NW of checkpoint'", timing: nil),
                    ProtocolStep(number: 4, action: "UNIT", detail: "Identifying features: uniforms, insignia, equipment, vehicles", timing: nil),
                    ProtocolStep(number: 5, action: "TIME", detail: "When observed. Use 24-hour format with time zone", timing: nil),
                    ProtocolStep(number: 6, action: "EQUIPMENT", detail: "Weapons, vehicles, radios, special equipment visible", timing: nil)
                ],
                warnings: [
                    "Report what you SEE, not what you think",
                    "Even negative reports are valuable — 'no activity observed'",
                    "Send SALUTE immediately — information has a shelf life"
                ],
                keywords: ["salute", "salute report", "contact report", "enemy report", "spot report", "sitrep"]
            ),
            
            TacticalProtocol(
                title: "Counter-Tracking",
                category: .recon,
                severity: .priority,
                timeframe: "CONTINUOUS",
                steps: [
                    ProtocolStep(number: 1, action: "HARD SURFACE", detail: "Walk on rock, roots, hard ground when possible. Avoid soft soil, mud, snow", timing: "Continuous"),
                    ProtocolStep(number: 2, action: "WATER", detail: "Enter/exit streams on rock. Walk in water when practical", timing: nil),
                    ProtocolStep(number: 3, action: "CAMOUFLAGE SIGN", detail: "Replace disturbed vegetation, brush out obvious tracks, avoid breaking branches", timing: nil),
                    ProtocolStep(number: 4, action: "DECEPTION", detail: "False trails, backtracking, buttonhook. Make tracking difficult", timing: nil),
                    ProtocolStep(number: 5, action: "VARY PATTERN", detail: "Don't walk in file. Spread out, use different paths, rejoin at rally points", timing: nil)
                ],
                warnings: [
                    "Dogs track scent, not footprints — water crossings help",
                    "Fresh sign is easiest to track — age your trail if possible",
                    "Moving at night limits visual tracking but leaves same physical sign"
                ],
                keywords: ["counter tracking", "evasion", "hide tracks", "tracking", "cover trail", "anti tracking"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // DEFENSIVE POSITIONS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Fighting Position (Foxhole)",
                category: .positions,
                severity: .priority,
                timeframe: "30-60 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "SITE SELECTION", detail: "Cover from likely threat direction. Concealment. Good fields of fire. Avoid obvious terrain features", timing: nil),
                    ProtocolStep(number: 2, action: "MARK OUTLINE", detail: "Oval shape: 2ft wide × 3ft long × body depth. Head toward enemy", timing: nil),
                    ProtocolStep(number: 3, action: "DIG", detail: "Remove sod carefully (to replace). Dig to armpit depth. Create firing step at chest height", timing: "30-60 min"),
                    ProtocolStep(number: 4, action: "PARAPET", detail: "Pile spoil in front and sides. Cover with camouflage material. Keep low profile", timing: nil),
                    ProtocolStep(number: 5, action: "SECTORS", detail: "Clear fields of fire (quietly). Mark left and right limits. Establish range markers", timing: nil)
                ],
                warnings: [
                    "Don't silhouette yourself against the sky",
                    "Overhead cover for artillery/mortars takes more time but saves lives",
                    "Pre-position ammo, water, first aid within arm's reach"
                ],
                keywords: ["fighting position", "foxhole", "dig in", "defensive position", "hasty fighting position", "hole"]
            ),
            
            TacticalProtocol(
                title: "Hasty Ambush",
                category: .positions,
                severity: .urgent,
                timeframe: "1-5 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "SIGNAL", detail: "Leader gives silent signal (hand/arm) for hasty ambush", timing: "0 sec"),
                    ProtocolStep(number: 2, action: "POSITION", detail: "All elements move to nearest cover facing threat direction. Linear or L-shape", timing: "30 sec"),
                    ProtocolStep(number: 3, action: "SECTORS", detail: "Each position takes sector. Ensure interlocking fire, no gaps, no fratricide", timing: nil),
                    ProtocolStep(number: 4, action: "WAIT", detail: "Silence, no movement, weapons ready. Initiate on leader's signal ONLY", timing: nil),
                    ProtocolStep(number: 5, action: "INITIATE", detail: "Leader initiates with most casualty-producing weapon. Maximum violence, then break contact", timing: "On signal")
                ],
                warnings: [
                    "Know your withdrawal route BEFORE initiating",
                    "Never pursue after ambush — secondary ambushes exist",
                    "EPW handling delays withdrawal — be ready"
                ],
                keywords: ["ambush", "hasty ambush", "quick ambush", "surprise attack", "enemy contact"]
            ),
            
            TacticalProtocol(
                title: "Perimeter Defense",
                category: .positions,
                severity: .priority,
                timeframe: "15-30 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "TERRAIN", detail: "Select defensible ground: cover, concealment, observation, fields of fire, obstacles", timing: nil),
                    ProtocolStep(number: 2, action: "ASSIGN SECTORS", detail: "Divide 360° into sectors. Overlap sectors for interlocking fire. No gaps", timing: nil),
                    ProtocolStep(number: 3, action: "POSITIONS", detail: "Each fighting position covers its sector. Stagger depth. Identify alternate positions", timing: nil),
                    ProtocolStep(number: 4, action: "EARLY WARNING", detail: "LPs/OPs forward. Trip flares, noise devices on approaches", timing: nil),
                    ProtocolStep(number: 5, action: "REHEARSE", detail: "Everyone knows challenge/password, rally point, withdrawal route, responsibilities", timing: nil)
                ],
                warnings: [
                    "All-round security means every direction is covered at all times",
                    "Avoid 'fatal funnel' — don't cluster positions",
                    "Sleep plan: always maintain minimum security awake"
                ],
                keywords: ["perimeter", "defensive perimeter", "360 security", "night perimeter", "camp security", "base defense"]
            ),
            
            TacticalProtocol(
                title: "Cover vs Concealment",
                category: .positions,
                severity: .routine,
                timeframe: "INSTANT",
                steps: [
                    ProtocolStep(number: 1, action: "COVER = STOPS BULLETS", detail: "Thick trees, concrete, engine blocks, filled sandbags, earth", timing: nil),
                    ProtocolStep(number: 2, action: "CONCEALMENT = HIDES YOU", detail: "Bushes, shadows, tall grass, darkness. Won't stop bullets", timing: nil),
                    ProtocolStep(number: 3, action: "BEST = BOTH", detail: "Ideal position has BOTH cover AND concealment", timing: nil),
                    ProtocolStep(number: 4, action: "USE DEPTH", detail: "Thick cover > thin cover. 12\" of earth stops most rifle rounds", timing: nil),
                    ProtocolStep(number: 5, action: "AVOID FALSE COVER", detail: "Interior walls, car doors, thin wood = concealment only. Will not stop rounds", timing: nil)
                ],
                warnings: [
                    "A bush won't stop a bullet but a concrete wall will",
                    "Windows, cars (except engine block), furniture = NOT cover",
                    "In urban: corners provide cover, center of walls are weakest"
                ],
                keywords: ["cover", "concealment", "protection", "hide", "cover position", "bullet proof", "safe position"]
            ),
            
            TacticalProtocol(
                title: "Sniper Hide Selection",
                category: .positions,
                severity: .priority,
                timeframe: "15-30 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "BACKGROUND", detail: "Position against dark/varied background. Never silhouette", timing: nil),
                    ProtocolStep(number: 2, action: "DEPTH", detail: "Set back from aperture (window, vegetation). Muzzle inside, in shadow", timing: nil),
                    ProtocolStep(number: 3, action: "ESCAPE", detail: "Covered withdrawal route. Plan primary and alternate", timing: nil),
                    ProtocolStep(number: 4, action: "RANGE DATA", detail: "Pre-calculate ranges to likely target areas. Record hold-offs", timing: nil),
                    ProtocolStep(number: 5, action: "MINIMIZE SIGN", detail: "No brass ejection visible. No muzzle blast signature. Suppress if possible", timing: nil)
                ],
                warnings: [
                    "Obvious positions (rooftops, single trees) are checked first",
                    "Urban: upper floors give angle but are obvious. Lower floors are better",
                    "Movement into/out of position is highest risk — plan carefully"
                ],
                keywords: ["sniper", "sniper hide", "sniper position", "shooting position", "overwatch", "marksman"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // MOVEMENT PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Movement Formations",
                category: .movement,
                severity: .routine,
                timeframe: "INSTANT",
                steps: [
                    ProtocolStep(number: 1, action: "FILE", detail: "Single line, one behind another. Easy control, poor firepower forward. Use in dense terrain", timing: nil),
                    ProtocolStep(number: 2, action: "WEDGE", detail: "Inverted V shape. Good security forward/flanks. Use in open terrain", timing: nil),
                    ProtocolStep(number: 3, action: "LINE", detail: "Abreast, all on line. Maximum firepower forward. Assault formation", timing: nil),
                    ProtocolStep(number: 4, action: "ECHELON", detail: "Diagonal. Protects one flank while moving. Use when threat on known flank", timing: nil),
                    ProtocolStep(number: 5, action: "STAGGERED COLUMN", detail: "Two files, offset. Good for roads. Balanced security/control", timing: nil)
                ],
                warnings: [
                    "Formation is dictated by terrain, visibility, likely enemy direction",
                    "Interval: can see person ahead, hear whispered commands",
                    "If contact front: file/wedge → line automatically"
                ],
                keywords: ["formation", "movement formation", "patrol formation", "wedge", "file", "column", "squad formation"]
            ),
            
            TacticalProtocol(
                title: "Danger Area Crossing",
                category: .movement,
                severity: .priority,
                timeframe: "5-10 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "HALT", detail: "Stop in cover before danger area. Hand signal 'danger area'", timing: nil),
                    ProtocolStep(number: 2, action: "OBSERVE", detail: "Leader moves forward, observes crossing point. Look for ambush indicators", timing: "3-5 min"),
                    ProtocolStep(number: 3, action: "SECURITY", detail: "Position flank security at near side, left and right", timing: nil),
                    ProtocolStep(number: 4, action: "CROSS", detail: "Cross at narrowest point, one element at a time. Fastest moving soldier crosses first to far side", timing: nil),
                    ProtocolStep(number: 5, action: "CONSOLIDATE", detail: "Far side security set. Near side security crosses last. Resume movement", timing: nil)
                ],
                warnings: [
                    "Linear danger areas (roads): cross perpendicular, don't walk along them",
                    "Small units: scroll method — continuous movement, no stopping in open",
                    "Large danger areas may require bounding overwatch"
                ],
                keywords: ["danger area", "crossing", "road crossing", "open area", "linear danger area", "lda"]
            ),
            
            TacticalProtocol(
                title: "Bounding Overwatch",
                category: .movement,
                severity: .priority,
                timeframe: "CONTINUOUS",
                steps: [
                    ProtocolStep(number: 1, action: "SPLIT", detail: "Divide into two elements: bounding element and overwatch element", timing: nil),
                    ProtocolStep(number: 2, action: "OVERWATCH SET", detail: "Overwatch element in position, covering forward. Weapons ready", timing: nil),
                    ProtocolStep(number: 3, action: "BOUND", detail: "Bounding element moves forward to next covered position (50-100m max)", timing: nil),
                    ProtocolStep(number: 4, action: "SET", detail: "Bounding element sets in new position, establishes overwatch", timing: nil),
                    ProtocolStep(number: 5, action: "ALTERNATE", detail: "Previous overwatch now bounds forward. Repeat. Leapfrog pattern", timing: nil)
                ],
                warnings: [
                    "Use when enemy contact is likely — slower but safer",
                    "Bounds should be within effective supporting range of overwatch",
                    "Successive bounds: overwatch element moves to SAME position, not leapfrog"
                ],
                keywords: ["bounding", "overwatch", "bounding overwatch", "bound", "leapfrog", "fire and maneuver"]
            ),
            
            TacticalProtocol(
                title: "Night Movement",
                category: .movement,
                severity: .priority,
                timeframe: "CONTINUOUS",
                steps: [
                    ProtocolStep(number: 1, action: "LIGHT DISCIPLINE", detail: "No white light. Red/green filtered only if absolutely necessary. No glow from screens", timing: nil),
                    ProtocolStep(number: 2, action: "NOISE DISCIPLINE", detail: "Tape metal, pad loose items. No talking. Hand signals only. Slow deliberate movement", timing: nil),
                    ProtocolStep(number: 3, action: "ADAPT VISION", detail: "20-30 min to full dark adaptation. Protect it. Use peripheral vision — rods see movement better", timing: nil),
                    ProtocolStep(number: 4, action: "INTERVAL", detail: "Close interval — can touch person ahead. Easily lost at night", timing: nil),
                    ProtocolStep(number: 5, action: "PACE", detail: "Move slower. High step to avoid tripping. Stop, listen, move", timing: nil)
                ],
                warnings: [
                    "Moon illumination changes everything — plan around it",
                    "NVGs create tunnel vision — still need to stop and scan",
                    "Challenge/password critical — night fratricide is common"
                ],
                keywords: ["night movement", "night patrol", "darkness", "night travel", "moving at night", "nvg"]
            ),
            
            TacticalProtocol(
                title: "React to Contact",
                category: .movement,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "RETURN FIRE", detail: "Immediately return fire toward threat. Get rounds downrange NOW", timing: "0-3 sec"),
                    ProtocolStep(number: 2, action: "TAKE COVER", detail: "Move to nearest cover/concealment while firing. Don't freeze in the open", timing: "3-10 sec"),
                    ProtocolStep(number: 3, action: "LOCATE", detail: "Identify enemy position: muzzle flash, sound, dust, movement", timing: nil),
                    ProtocolStep(number: 4, action: "COMMUNICATE", detail: "Call out contact: 'CONTACT FRONT!' Direction, distance, description", timing: nil),
                    ProtocolStep(number: 5, action: "LEADER ACTION", detail: "Leader assesses and gives direction: assault, suppress, flank, break contact", timing: nil)
                ],
                warnings: [
                    "First 10 seconds are critical — win the initial exchange",
                    "Suppression buys time and space to maneuver",
                    "If outmatched: break contact immediately, don't get decisively engaged"
                ],
                keywords: ["contact", "enemy contact", "ambush", "firefight", "react to contact", "engaged", "taking fire"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // SURVIVAL PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Water Procurement",
                category: .survival,
                severity: .critical,
                timeframe: "VARIES",
                steps: [
                    ProtocolStep(number: 1, action: "LOCATE", detail: "Follow terrain downhill, animal trails, bird flight patterns. Listen for water", timing: nil),
                    ProtocolStep(number: 2, action: "COLLECT", detail: "Rainwater: clean. Streams: flowing > stagnant. Morning dew: wipe with cloth, wring out", timing: nil),
                    ProtocolStep(number: 3, action: "FILTER", detail: "Remove sediment: cloth filter, sand/charcoal filter, let settle", timing: nil),
                    ProtocolStep(number: 4, action: "PURIFY", detail: "Boil 1 min (3 min above 6500ft). Or: purification tablets per instructions. Or: UV sterilizer", timing: nil),
                    ProtocolStep(number: 5, action: "STORE", detail: "Clean container. Protect from contamination. Ration: 2 liters/day minimum", timing: nil)
                ],
                warnings: [
                    "Dehydration kills faster than starvation — prioritize water over food",
                    "Clear water can still contain pathogens — always purify",
                    "Snow: melt before drinking — eating snow drops core temp"
                ],
                keywords: ["water", "drinking water", "thirst", "dehydration", "find water", "purify water", "water source"]
            ),
            
            TacticalProtocol(
                title: "Fire Starting",
                category: .survival,
                severity: .priority,
                timeframe: "10-30 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "SITE", detail: "Clear area to dirt, away from overhanging branches, upwind of camp, near fuel supply", timing: nil),
                    ProtocolStep(number: 2, action: "TINDER", detail: "Finest, driest material: bark shavings, dry grass, birch bark, dryer lint, char cloth", timing: nil),
                    ProtocolStep(number: 3, action: "KINDLING", detail: "Pencil-thick dry sticks. Stage from smallest to largest", timing: nil),
                    ProtocolStep(number: 4, action: "IGNITE", detail: "Lighter/matches best. Ferro rod: strike into tinder. Friction: bow drill onto tinder", timing: nil),
                    ProtocolStep(number: 5, action: "BUILD", detail: "Feed kindling slowly. Don't smother. Add larger fuel as fire establishes. Teepee or log cabin structure", timing: nil)
                ],
                warnings: [
                    "Wet conditions: look for dead standing wood, inside of logs, under overhangs",
                    "Fire = light + smoke — tactical considerations may preclude fire",
                    "Never leave fire unattended. Full extinguish before moving"
                ],
                keywords: ["fire", "start fire", "fire starting", "campfire", "warmth", "heat", "fire making"]
            ),
            
            TacticalProtocol(
                title: "Emergency Shelter",
                category: .survival,
                severity: .urgent,
                timeframe: "15-60 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "SITE", detail: "Protected from wind, elevated from flood/cold ground, near materials, away from hazards (widowmakers, ants)", timing: nil),
                    ProtocolStep(number: 2, action: "FRAME", detail: "Debris hut: ridgepole at 45°, ribs on sides. Lean-to: single slope, back to wind", timing: nil),
                    ProtocolStep(number: 3, action: "INSULATE", detail: "Layer debris 3 ft thick. Leaves, grass, pine boughs. Thicker = warmer", timing: nil),
                    ProtocolStep(number: 4, action: "BED", detail: "Ground insulation critical. 6+ inches of debris between you and ground", timing: nil),
                    ProtocolStep(number: 5, action: "SMALL", detail: "Smaller space = less body heat needed to warm. Just big enough for you", timing: nil)
                ],
                warnings: [
                    "Ground steals heat fastest — insulate below you first",
                    "Poncho/tarp: faster but less insulation. Combine with debris",
                    "Test before dark — you don't want to discover problems at 2am"
                ],
                keywords: ["shelter", "emergency shelter", "survival shelter", "debris hut", "lean to", "sleep", "overnight"]
            ),
            
            TacticalProtocol(
                title: "Signaling for Rescue",
                category: .survival,
                severity: .priority,
                timeframe: "VARIES",
                steps: [
                    ProtocolStep(number: 1, action: "SIGNAL MIRROR", detail: "Flash at aircraft/ships. Aim reflection using sighting hole. Effective 10+ miles in sun", timing: "When aircraft visible"),
                    ProtocolStep(number: 2, action: "FIRE/SMOKE", detail: "3 fires in triangle = distress. Add green vegetation for white smoke (day) or flame (night)", timing: nil),
                    ProtocolStep(number: 3, action: "GROUND SIGNALS", detail: "Large symbols in clearing: V = need assistance, X = need medical, I = moving this way. Minimum 10ft tall", timing: nil),
                    ProtocolStep(number: 4, action: "WHISTLE", detail: "3 blasts = distress. Carries farther than voice. Conserves energy", timing: "When searchers near"),
                    ProtocolStep(number: 5, action: "STAY VISIBLE", detail: "Stay with vehicle/crash site if safe. Move to clearing. Wear bright colors. Wave arms", timing: nil)
                ],
                warnings: [
                    "Rescue most likely along planned route — stay near unless unsafe",
                    "Signaling takes energy — conserve and signal when opportunity is real",
                    "PLB/EPIRB with GPS gives exact location — use immediately if available"
                ],
                keywords: ["signal", "rescue", "sos", "distress", "help", "signaling", "rescue signal", "found", "location"]
            ),
            
            TacticalProtocol(
                title: "Edible Plant ID Basics",
                category: .survival,
                severity: .routine,
                timeframe: "VARIES",
                steps: [
                    ProtocolStep(number: 1, action: "AVOID", detail: "White/yellow berries, milky sap, almond smell, 3-leaf patterns, umbrella flowers, beans/pods unless positive ID", timing: nil),
                    ProtocolStep(number: 2, action: "UNIVERSAL TEST", detail: "Skin test (8hr) → lip test (15min) → tongue test (15min) → chew spit (15min) → swallow small (8hr)", timing: "24+ hours total"),
                    ProtocolStep(number: 3, action: "SAFE BETS", detail: "Cattail (all parts), acorns (leached), dandelion, pine (inner bark, needles), grass seeds", timing: nil),
                    ProtocolStep(number: 4, action: "COOK WHEN POSSIBLE", detail: "Cooking neutralizes some toxins and makes nutrients more available", timing: nil),
                    ProtocolStep(number: 5, action: "OBSERVE ANIMALS", detail: "What animals eat isn't always safe for humans — but total avoidance by animals is a warning", timing: nil)
                ],
                warnings: [
                    "When in doubt, don't eat it — starvation takes weeks, poisoning takes hours",
                    "Never eat mushrooms without positive expert ID — too many deadly lookalikes",
                    "Water and shelter are more critical than food in short-term survival"
                ],
                keywords: ["edible", "plants", "food", "forage", "foraging", "eat", "berries", "wild food", "survival food"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // NAVIGATION PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Map Reading Basics",
                category: .navigation,
                severity: .routine,
                timeframe: "VARIES",
                steps: [
                    ProtocolStep(number: 1, action: "ORIENT", detail: "Align map north with compass north. Use terrain features to confirm orientation", timing: nil),
                    ProtocolStep(number: 2, action: "IDENTIFY POSITION", detail: "Find 3 known terrain features. Triangulate position. Mark on map", timing: nil),
                    ProtocolStep(number: 3, action: "READ CONTOURS", detail: "Close lines = steep. Far apart = flat. V pointing uphill = valley. V pointing downhill = ridge", timing: nil),
                    ProtocolStep(number: 4, action: "PLAN ROUTE", detail: "Identify waypoints, checkpoints, handrails (linear features to follow)", timing: nil),
                    ProtocolStep(number: 5, action: "MEASURE", detail: "Map distance × scale = ground distance. Pace count for actual travel", timing: nil)
                ],
                warnings: [
                    "Magnetic declination varies by location — adjust compass to map",
                    "Trust your compass over intuition — terrain distorts perception",
                    "Check position at every waypoint — errors compound"
                ],
                keywords: ["map", "map reading", "navigation", "contour", "terrain", "where am i", "lost", "position"]
            ),
            
            TacticalProtocol(
                title: "Compass Navigation",
                category: .navigation,
                severity: .routine,
                timeframe: "VARIES",
                steps: [
                    ProtocolStep(number: 1, action: "HOLD LEVEL", detail: "Compass flat, at chest height. No metal nearby (guns, radios, vehicles)", timing: nil),
                    ProtocolStep(number: 2, action: "POINT DIRECTION", detail: "Direction-of-travel arrow points where you want to go", timing: nil),
                    ProtocolStep(number: 3, action: "ROTATE BEZEL", detail: "Turn bezel until 'N' aligns with red magnetic needle", timing: nil),
                    ProtocolStep(number: 4, action: "READ BEARING", detail: "Bearing is number at index line (direction-of-travel arrow base)", timing: nil),
                    ProtocolStep(number: 5, action: "FOLLOW", detail: "Keep needle in red 'shed' (orienting arrow). Walk in direction-of-travel direction", timing: nil)
                ],
                warnings: [
                    "Magnetic vs Grid vs True north — know your map's reference",
                    "Metal and electronics affect compass — step away before reading",
                    "Night: aim off intentionally (5-10°) then correct at target"
                ],
                keywords: ["compass", "bearing", "azimuth", "direction", "compass navigation", "heading"]
            ),
            
            TacticalProtocol(
                title: "Navigation Without Compass",
                category: .navigation,
                severity: .priority,
                timeframe: "VARIES",
                steps: [
                    ProtocolStep(number: 1, action: "SUN", detail: "Rises ~East, sets ~West. Shadow stick: mark tip, wait 15min, mark again. Line between = E-W", timing: nil),
                    ProtocolStep(number: 2, action: "STARS (NORTH)", detail: "North Star: follow Big Dipper's pointer stars 5× distance. Stays fixed, within 1° of true north", timing: nil),
                    ProtocolStep(number: 3, action: "STARS (SOUTH)", detail: "Southern Cross: extend long axis 4.5×. Point on horizon below = ~south", timing: nil),
                    ProtocolStep(number: 4, action: "WATCH", detail: "Point hour hand at sun. South is halfway between hour hand and 12 (N. hemisphere)", timing: nil),
                    ProtocolStep(number: 5, action: "NATURE", detail: "Less reliable: moss on north side (often wrong), tree rings wider on south (inconsistent)", timing: nil)
                ],
                warnings: [
                    "Natural signs are unreliable — use only as confirmation, not primary",
                    "Stick shadow method takes time but is accurate",
                    "Clouds obscure celestial navigation — have backup plan"
                ],
                keywords: ["no compass", "primitive navigation", "stars", "sun navigation", "lost no compass", "direction without compass"]
            ),
            
            TacticalProtocol(
                title: "Pace Count",
                category: .navigation,
                severity: .routine,
                timeframe: "CONTINUOUS",
                steps: [
                    ProtocolStep(number: 1, action: "ESTABLISH BASE", detail: "Walk 100m on flat ground, count every LEFT foot strike. That's your pace count", timing: "Once"),
                    ProtocolStep(number: 2, action: "ADJUST TERRAIN", detail: "Add 10% for uphill. Add 10-15% for rough terrain. Less for downhill", timing: nil),
                    ProtocolStep(number: 3, action: "TRACK", detail: "Use beads, knots, pebbles to count hundreds of meters traveled", timing: "Continuous"),
                    ProtocolStep(number: 4, action: "RESET", detail: "Reset at each checkpoint/waypoint. Start fresh count for next leg", timing: nil),
                    ProtocolStep(number: 5, action: "VERIFY", detail: "Cross-check with terrain features at expected distances", timing: "At checkpoints")
                ],
                warnings: [
                    "Average person: 62-68 paces per 100m (flat). Know YOUR count",
                    "Night: pace count drifts. Count more frequently",
                    "Very rough terrain: dead reckoning becomes unreliable — use terrain association"
                ],
                keywords: ["pace count", "distance", "how far", "pacing", "measure distance", "walking distance"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // COMMUNICATION PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Radio Procedure",
                category: .communication,
                severity: .routine,
                timeframe: "INSTANT",
                steps: [
                    ProtocolStep(number: 1, action: "LISTEN BEFORE TX", detail: "Wait for clear channel. Don't interrupt ongoing transmission", timing: nil),
                    ProtocolStep(number: 2, action: "CALL FORMAT", detail: "[Called station] THIS IS [your callsign]. 'Alpha Base, this is Bravo 2'", timing: nil),
                    ProtocolStep(number: 3, action: "MESSAGE", detail: "Brief, clear, use prowords. Key details: Who, What, Where, When", timing: nil),
                    ProtocolStep(number: 4, action: "CONFIRMATION", detail: "End with 'OVER' (expect reply) or 'OUT' (no reply needed). Never both", timing: nil),
                    ProtocolStep(number: 5, action: "READBACK", detail: "Receiver repeats key info. Sender confirms or corrects", timing: "Critical info only")
                ],
                warnings: [
                    "Assume enemy is listening — use brevity, authentication, encryption if available",
                    "Silence is sometimes better than transmission — consider tactical situation",
                    "Weak signal: shorten message, try later, try higher ground"
                ],
                keywords: ["radio", "comms", "communication", "transmit", "broadcast", "radio procedure"]
            ),
            
            TacticalProtocol(
                title: "9-Line MEDEVAC",
                category: .communication,
                severity: .critical,
                timeframe: "1-2 MIN",
                steps: [
                    ProtocolStep(number: 1, action: "LINE 1", detail: "Location: Grid coordinate of pickup site", timing: nil),
                    ProtocolStep(number: 2, action: "LINE 2", detail: "Frequency + Callsign: Radio freq and callsign at site", timing: nil),
                    ProtocolStep(number: 3, action: "LINE 3", detail: "Patients: A=Urgent, B=Priority, C=Routine, D=Convenience", timing: nil),
                    ProtocolStep(number: 4, action: "LINE 4", detail: "Special Equipment: A=None, B=Hoist, C=Extraction, D=Ventilator", timing: nil),
                    ProtocolStep(number: 5, action: "LINE 5", detail: "Patients: Number by type (litter/ambulatory)", timing: nil),
                    ProtocolStep(number: 6, action: "LINE 6", detail: "Security: N=No enemy, P=Possible, E=Enemy in area, X=Armed escort", timing: nil),
                    ProtocolStep(number: 7, action: "LINE 7", detail: "Marking: A=Panels, B=Pyro, C=Smoke, D=None, E=Other", timing: nil),
                    ProtocolStep(number: 8, action: "LINE 8", detail: "Nationality: A=US Military, B=US Civilian, C=Non-US Military, D=Non-US Civilian, E=EPW", timing: nil),
                    ProtocolStep(number: 9, action: "LINE 9", detail: "NBC/Terrain: Terrain description, NBC contamination if any", timing: nil)
                ],
                warnings: [
                    "Have 9-line memorized or on card — speed matters",
                    "Mark LZ before calling — be ready when bird arrives",
                    "Rehearse with team — everyone should know the format"
                ],
                keywords: ["medevac", "9 line", "nine line", "medical evacuation", "helicopter", "casevac", "dustoff"]
            ),
            
            TacticalProtocol(
                title: "Hand and Arm Signals",
                category: .communication,
                severity: .routine,
                timeframe: "INSTANT",
                steps: [
                    ProtocolStep(number: 1, action: "HALT", detail: "Fist raised overhead. Hold until acknowledged", timing: nil),
                    ProtocolStep(number: 2, action: "MOVE OUT", detail: "Arm extended, palm up, sweep in direction of movement", timing: nil),
                    ProtocolStep(number: 3, action: "ENEMY IN SIGHT", detail: "Point weapon in enemy direction", timing: nil),
                    ProtocolStep(number: 4, action: "DANGER AREA", detail: "Extend arm parallel to ground, palm down, wave up and down", timing: nil),
                    ProtocolStep(number: 5, action: "RALLY", detail: "Circle arm overhead, point to rally point", timing: nil),
                    ProtocolStep(number: 6, action: "I DON'T UNDERSTAND", detail: "Hands open, palms up, shrug shoulders", timing: nil)
                ],
                warnings: [
                    "Signal must be acknowledged before continuing",
                    "At night: IR signals or touch signals pre-planned",
                    "Team must know same signals — standardize before mission"
                ],
                keywords: ["hand signals", "arm signals", "silent signals", "visual signals", "no voice"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // EVASION PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Initial Evasion",
                category: .evasion,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "MOVE", detail: "Get away from last known position immediately. Distance is survival", timing: "0-5 min"),
                    ProtocolStep(number: 2, action: "HIDE", detail: "Find concealment. Dense vegetation, terrain folds. Not the first obvious spot", timing: "5-15 min"),
                    ProtocolStep(number: 3, action: "OBSERVE", detail: "Watch your backtrail. Listen. Let pursuit pass before moving", timing: "15+ min"),
                    ProtocolStep(number: 4, action: "PLAN", detail: "Assess: Where are friendlies? What resources do you have? What's your route?", timing: nil),
                    ProtocolStep(number: 5, action: "MOVE TACTICALLY", detail: "Travel at night, hide by day. Use terrain, avoid roads and villages initially", timing: "Ongoing")
                ],
                warnings: [
                    "First hour is critical — they're searching hardest",
                    "Don't run blindly — move with purpose, think ahead",
                    "If captured is imminent: hide critical items, prepare cover story"
                ],
                keywords: ["evasion", "escape", "evade", "on the run", "being hunted", "pursued", "escape and evasion", "sere"]
            ),
            
            TacticalProtocol(
                title: "E&E Movement",
                category: .evasion,
                severity: .priority,
                timeframe: "ONGOING",
                steps: [
                    ProtocolStep(number: 1, action: "NIGHT TRAVEL", detail: "Move at night, hide at day. Rest during daylight in concealed position", timing: nil),
                    ProtocolStep(number: 2, action: "AVOID", detail: "Roads, trails, villages, farms, dogs, people. Cross roads at bends/low points", timing: nil),
                    ProtocolStep(number: 3, action: "WATER", detail: "Travel along water when possible. Masks scent, provides resource, hard to track", timing: nil),
                    ProtocolStep(number: 4, action: "CACHE", detail: "Never carry everything. Cache supplies along route for return trips or emergencies", timing: nil),
                    ProtocolStep(number: 5, action: "APPROACH", detail: "When approaching friendlies: authentication, recognition signals. Don't surprise them", timing: nil)
                ],
                warnings: [
                    "Starvation takes weeks, capture can take minutes — prioritize evasion over food",
                    "Trust no one initially — resistance networks take time to verify",
                    "Your own forces may shoot first — have recognition signals ready"
                ],
                keywords: ["e&e", "escape and evasion", "evading", "movement while evading", "getting home", "behind lines"]
            ),
            
            TacticalProtocol(
                title: "Surveillance Detection",
                category: .evasion,
                severity: .priority,
                timeframe: "CONTINUOUS",
                steps: [
                    ProtocolStep(number: 1, action: "BASELINE", detail: "Know what's normal: usual people, cars, patterns in your area", timing: "Ongoing"),
                    ProtocolStep(number: 2, action: "SPOT ANOMALIES", detail: "Same person/vehicle multiple times. People who don't fit. Out-of-place activity", timing: nil),
                    ProtocolStep(number: 3, action: "TEST", detail: "Make unexpected stops or turns. See who reacts or follows", timing: nil),
                    ProtocolStep(number: 4, action: "SDR", detail: "Surveillance Detection Route: planned route with checkpoints to identify and lose followers", timing: nil),
                    ProtocolStep(number: 5, action: "DON'T ALERT", detail: "If surveilled, act normal. Don't let them know you know. Gather info, then act", timing: nil)
                ],
                warnings: [
                    "Professional surveillance uses multiple teams and vehicles — hard to spot",
                    "Electronic surveillance (phone, vehicle trackers) bypasses physical SDR",
                    "Pattern of life is your enemy — break routines unpredictably"
                ],
                keywords: ["surveillance", "being watched", "followed", "counter surveillance", "sdr", "tail", "being followed"]
            ),
            
            // ═══════════════════════════════════════════════════════════════
            // WEAPONS PROTOCOLS
            // ═══════════════════════════════════════════════════════════════
            
            TacticalProtocol(
                title: "Stoppage Clearing (Rifle)",
                category: .weapons,
                severity: .critical,
                timeframe: "IMMEDIATE",
                steps: [
                    ProtocolStep(number: 1, action: "TAP", detail: "Slap magazine firmly to seat it. Many stoppages are feed failures", timing: "1 sec"),
                    ProtocolStep(number: 2, action: "RACK", detail: "Pull charging handle fully to rear, release. Ejects round, loads fresh", timing: "1 sec"),
                    ProtocolStep(number: 3, action: "ASSESS", detail: "Attempt to fire. If still stopped, proceed to remedial", timing: "1 sec"),
                    ProtocolStep(number: 4, action: "LOCK BACK", detail: "Lock bolt to rear, remove magazine, observe chamber", timing: nil),
                    ProtocolStep(number: 5, action: "CLEAR & RELOAD", detail: "Strip stuck round, reinsert magazine, chamber round, assess", timing: nil)
                ],
                warnings: [
                    "In contact: immediate action first, assess later",
                    "Double feed: lock back, strip mag, rack 3×, reinsert, chamber",
                    "Catastrophic malfunction: transition to secondary weapon"
                ],
                keywords: ["jam", "malfunction", "stoppage", "weapon jam", "gun jam", "clearing", "tap rack"]
            ),
            
            TacticalProtocol(
                title: "Magazine Change",
                category: .weapons,
                severity: .routine,
                timeframe: "2-5 SEC",
                steps: [
                    ProtocolStep(number: 1, action: "ASSESS", detail: "Feel bolt lock back or count rounds. Change before empty if possible", timing: nil),
                    ProtocolStep(number: 2, action: "POSITION", detail: "Bring weapon to workspace. Index fresh mag with support hand", timing: nil),
                    ProtocolStep(number: 3, action: "RELEASE", detail: "Press mag release, strip empty mag (let drop or retain)", timing: nil),
                    ProtocolStep(number: 4, action: "INSERT", detail: "Index fresh mag, insert with force, tug to confirm seat", timing: nil),
                    ProtocolStep(number: 5, action: "CHAMBER", detail: "If bolt locked: release bolt. If not: no action needed. Weapon up, back in fight", timing: nil)
                ],
                warnings: [
                    "Tactical reload: change before empty, retain partial mag",
                    "Speed reload: change when empty, let mag drop, speed matters",
                    "Know your mag pouches by feel — eyes stay on threat"
                ],
                keywords: ["reload", "magazine change", "mag change", "reloading", "out of ammo", "change magazine"]
            )
        ]
    }
}

// MARK: - Protocol Card View

struct ProtocolCardView: View {
    let proto: TacticalProtocol
    @State private var expanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: proto.severity.icon)
                    .foregroundColor(proto.severity.color)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(proto.title.uppercased())
                        .font(.headline.bold())
                        .foregroundColor(ZDDesign.pureWhite)
                    
                    HStack(spacing: 8) {
                        Text(proto.severity.rawValue)
                            .font(.caption2.bold())
                            .foregroundColor(proto.severity.color)
                        
                        Text("•")
                            .foregroundColor(ZDDesign.mediumGray)
                        
                        Text(proto.timeframe)
                            .font(.caption2)
                            .foregroundColor(ZDDesign.mediumGray)
                        
                        Spacer()
                        
                        Label(proto.category.rawValue, systemImage: proto.category.icon)
                            .font(.caption2)
                            .foregroundColor(proto.category.color)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(proto.severity.color.opacity(0.2))
            
            // Steps
            VStack(alignment: .leading, spacing: 8) {
                ForEach(proto.steps, id: \.number) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(step.number)")
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .frame(width: 24, height: 24)
                            .background(proto.severity.color)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(step.action)
                                    .font(.subheadline.bold())
                                    .foregroundColor(proto.severity.color)
                                
                                if let timing = step.timing {
                                    Spacer()
                                    Text(timing)
                                        .font(.caption2)
                                        .foregroundColor(ZDDesign.mediumGray)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.3))
                                        .cornerRadius(4)
                                }
                            }
                            
                            Text(step.detail)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Warnings
            if !proto.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("WARNINGS", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundColor(ZDDesign.safetyYellow)
                    
                    ForEach(proto.warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(ZDDesign.safetyYellow)
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .padding()
                .background(ZDDesign.safetyYellow.opacity(0.15))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            Spacer().frame(height: 8)
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(12)
    }
}

// MARK: - Protocol Browser View

struct ProtocolBrowserView: View {
    @ObservedObject private var db = ProtocolDatabase.shared
    @State private var searchQuery = ""
    @State private var selectedCategory: ProtocolCategory?
    @State private var selectedProtocol: TacticalProtocol?
    
    var filteredProtocols: [TacticalProtocol] {
        if !searchQuery.isEmpty {
            return db.search(query: searchQuery)
        } else if let category = selectedCategory {
            return db.protocols(for: category)
        } else {
            return db.protocols
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                TextField("Search protocols...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("All") {
                            selectedCategory = nil
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedCategory == nil ? ZDDesign.cyanAccent : Color.gray.opacity(0.3))
                        .foregroundColor(ZDDesign.pureWhite)
                        .cornerRadius(16)
                        
                        ForEach(ProtocolCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.icon)
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == category ? category.color : Color.gray.opacity(0.3))
                            .foregroundColor(ZDDesign.pureWhite)
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Protocol list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredProtocols) { proto in
                            Button {
                                selectedProtocol = proto
                            } label: {
                                protocolRow(proto)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Protocols")
            .sheet(item: $selectedProtocol) { proto in
                NavigationStack {
                    ScrollView {
                        ProtocolCardView(proto: proto)
                            .padding()
                    }
                    .navigationTitle(proto.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                selectedProtocol = nil
                            }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }
    
    private func protocolRow(_ proto: TacticalProtocol) -> some View {
        HStack(spacing: 12) {
            Image(systemName: proto.severity.icon)
                .foregroundColor(proto.severity.color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(proto.title)
                    .font(.subheadline.bold())
                    .foregroundColor(ZDDesign.pureWhite)
                
                HStack(spacing: 6) {
                    Text(proto.severity.rawValue)
                        .font(.caption2)
                        .foregroundColor(proto.severity.color)
                    
                    Text("•")
                        .foregroundColor(ZDDesign.mediumGray)
                    
                    Label(proto.category.rawValue, systemImage: proto.category.icon)
                        .font(.caption2)
                        .foregroundColor(proto.category.color)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(ZDDesign.mediumGray)
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(10)
    }
}

#Preview {
    ProtocolBrowserView()
        .preferredColorScheme(.dark)
}
