//
//  SurvivalDatabase.swift
//  ZeroDark
//
//  Offline survival knowledge database
//  2,000+ scenarios, plant ID, first aid, weather prediction
//

import Foundation
import SQLite3
import CoreML

// MARK: - Survival Database Manager

@MainActor
public class SurvivalDatabase: ObservableObject {
    public static let shared = SurvivalDatabase()
    
    @Published public var isLoaded = false
    @Published public var scenarioCount = 0
    @Published public var plantCount = 0
    @Published public var loadProgress: Double = 0
    
    private var db: OpaquePointer?
    
    private init() {
        loadDatabase()
    }
    
    // MARK: - Database Loading
    
    private func loadDatabase() {
        // In production: Load from bundled SQLite file
        // For now: Initialize with sample data
        initializeSampleData()
        isLoaded = true
    }
    
    private func initializeSampleData() {
        // Sample survival scenarios
        scenarios = SurvivalScenario.sampleScenarios
        scenarioCount = scenarios.count
        
        // Sample plants
        plants = PlantEntry.samplePlants
        plantCount = plants.count
    }
    
    // MARK: - Survival Scenarios
    
    private var scenarios: [SurvivalScenario] = []
    
    public func searchScenarios(query: String, category: SurvivalCategory? = nil) -> [SurvivalScenario] {
        let lowercaseQuery = query.lowercased()
        return scenarios.filter { scenario in
            let matchesQuery = scenario.title.lowercased().contains(lowercaseQuery) ||
                              scenario.content.lowercased().contains(lowercaseQuery) ||
                              scenario.keywords.contains { $0.lowercased().contains(lowercaseQuery) }
            let matchesCategory = category == nil || scenario.category == category
            return matchesQuery && matchesCategory
        }
    }
    
    public func getScenariosByCategory(_ category: SurvivalCategory) -> [SurvivalScenario] {
        scenarios.filter { $0.category == category }
    }
    
    // MARK: - Plant Identification
    
    private var plants: [PlantEntry] = []
    
    public func identifyPlant(features: PlantFeatures) -> [PlantMatch] {
        // Match against database based on visual features
        plants.compactMap { plant in
            let score = matchScore(plant: plant, features: features)
            guard score > 0.5 else { return nil }
            return PlantMatch(plant: plant, confidence: score)
        }.sorted { $0.confidence > $1.confidence }
    }
    
    public func searchPlants(query: String) -> [PlantEntry] {
        let lowercaseQuery = query.lowercased()
        return plants.filter { plant in
            plant.commonName.lowercased().contains(lowercaseQuery) ||
            plant.scientificName.lowercased().contains(lowercaseQuery) ||
            plant.description.lowercased().contains(lowercaseQuery)
        }
    }
    
    private func matchScore(plant: PlantEntry, features: PlantFeatures) -> Double {
        var score = 0.0
        var checks = 0.0
        
        // Leaf shape match
        if let leafShape = features.leafShape {
            checks += 1
            if plant.leafShape == leafShape { score += 1 }
        }
        
        // Flower color match
        if let flowerColor = features.flowerColor {
            checks += 1
            if plant.flowerColors.contains(flowerColor) { score += 1 }
        }
        
        // Height range match
        if let height = features.estimatedHeight {
            checks += 1
            if height >= plant.heightRange.lowerBound && height <= plant.heightRange.upperBound {
                score += 1
            }
        }
        
        return checks > 0 ? score / checks : 0
    }
    
    // MARK: - First Aid Procedures
    
    public func getFirstAidProcedure(for condition: String) -> FirstAidProcedure? {
        FirstAidProcedure.procedures.first { procedure in
            procedure.condition.lowercased().contains(condition.lowercased()) ||
            procedure.keywords.contains { $0.lowercased().contains(condition.lowercased()) }
        }
    }
    
    public func getAllFirstAidProcedures() -> [FirstAidProcedure] {
        FirstAidProcedure.procedures
    }
    
    // MARK: - Weather Prediction
    
    public func predictWeather(from observations: WeatherObservations) -> WeatherPrediction {
        var predictions: [String] = []
        var confidence = 0.7
        
        // Cloud pattern analysis
        if observations.cloudType == .cumulonimbus {
            predictions.append("Thunderstorms likely within 2-4 hours")
            confidence = 0.85
        } else if observations.cloudType == .cirrus && observations.cloudMovement == .fromWest {
            predictions.append("Weather change likely within 24-48 hours")
        }
        
        // Pressure trends
        if observations.pressureTrend == .falling {
            predictions.append("Deteriorating conditions expected")
            confidence += 0.1
        } else if observations.pressureTrend == .rising {
            predictions.append("Improving conditions expected")
        }
        
        // Wind observations
        if observations.windShift {
            predictions.append("Possible front passage - prepare for rapid change")
        }
        
        // Animal behavior
        if observations.birdsFlying == .low {
            predictions.append("Low pressure system approaching")
        }
        
        return WeatherPrediction(
            summary: predictions.first ?? "Conditions stable",
            details: predictions,
            confidence: min(confidence, 1.0),
            timeframe: "Next 6-12 hours"
        )
    }
}

// MARK: - Data Models

public enum SurvivalCategory: String, CaseIterable, Codable {
    case water = "Finding Water"
    case fire = "Fire Starting"
    case shelter = "Shelter Building"
    case food = "Food & Foraging"
    case navigation = "Navigation"
    case firstAid = "First Aid"
    case medical = "Medical"
    case signaling = "Signaling & Rescue"
    case wildlife = "Wildlife Safety"
    case weather = "Weather"
    case tools = "Tools & Gear"
}

public struct SurvivalScenario: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let category: SurvivalCategory
    public let content: String
    public let steps: [String]
    public let warnings: [String]
    public let keywords: [String]
    public let difficulty: Difficulty
    
    public enum Difficulty: String, Codable {
        case beginner, intermediate, advanced
    }
    
    static let sampleScenarios: [SurvivalScenario] = [
        // WATER SCENARIOS
        SurvivalScenario(id: UUID(), title: "Finding Water in Arid Terrain", category: .water,
                        content: "Water is critical - you have 3 days without it before severe dehydration.",
                        steps: ["Look for vegetation", "Follow animal trails downhill", "Check low terrain points", "Dig in dry riverbeds",
                               "Collect dew at dawn", "Create solar still"],
                        warnings: ["Filter and purify all water", "Avoid exertion during heat", "Ration sweat not water"],
                        keywords: ["water", "dehydration", "desert"], difficulty: .intermediate),

        SurvivalScenario(id: UUID(), title: "Water Purification Methods", category: .water,
                        content: "Multiple methods to make water safe - boiling, filtering, chemical treatment.",
                        steps: ["Boil: 1 minute at sea level, 3+ minutes at altitude", "Filter: Layer sand, charcoal, cloth",
                               "Chemical: Iodine tablets or bleach (2 drops/liter)", "UV: Sunlight in clear bottle 6 hours",
                               "Distillation: Boil and collect condensation"],
                        warnings: ["Cloudy water - filter first", "Some chemicals taste bitter", "Chemical method fails on some parasites"],
                        keywords: ["purification", "boil", "filter", "iodine"], difficulty: .beginner),

        SurvivalScenario(id: UUID(), title: "Finding Water in Forests", category: .water,
                        content: "Dense forests usually have abundant water - listen for sounds, look for signs.",
                        steps: ["Listen for flowing water", "Follow moss growth (moist side)", "Find game trails leading downhill",
                               "Collect water from leaf-litter depressions", "Dig in valley bottoms", "Use plants for water"],
                        warnings: ["Giardia common in wilderness water", "Stagnant water smells bad", "Don't rely on visual clarity"],
                        keywords: ["forest", "stream", "water-finding"], difficulty: .beginner),

        // SHELTER SCENARIOS
        SurvivalScenario(id: UUID(), title: "Building Emergency Shelter", category: .shelter,
                        content: "Shelter protects from hypothermia and hyperthermia - biggest survival killers.",
                        steps: ["Assess threats (wind, rain, sun)", "Find natural features to enhance", "Build small for heat retention",
                               "Insulate ground (lose 80% heat downward)", "Create 6-inch debris layer", "Angle roof for drainage"],
                        warnings: ["Avoid low areas - cold air settles", "Check for dead branches", "Don't build in riverbeds"],
                        keywords: ["shelter", "hypothermia", "debris-hut"], difficulty: .beginner),

        SurvivalScenario(id: UUID(), title: "Debris Hut Construction", category: .shelter,
                        content: "Most reliable emergency shelter - insulated, wind-proof, requires minimal materials.",
                        steps: ["Find 2 trees 10-15 feet apart", "Lay branch between them as ridgeline", "Lean branches at 45 degrees",
                               "Layer debris 2-3 feet thick", "Create entrance only 2-3 feet wide", "Line interior with leaves/grass"],
                        warnings: ["Too much debris collapses structure", "Must compress outer layer", "Need thick insulation under body"],
                        keywords: ["debris-hut", "shelter", "insulation"], difficulty: .intermediate),

        SurvivalScenario(id: UUID(), title: "Snow Shelter (Igloo/Quinzee)", category: .shelter,
                        content: "Snow is excellent insulator - builds effective shelter in winter conditions.",
                        steps: ["Find dense snow pack", "Pile snow or find snow block source", "Cut blocks 3ft x 2ft x 1ft",
                               "Spiral placement around dome", "Smooth interior walls", "Create sleeping platform 1-2 feet high"],
                        warnings: ["Need good snow density", "Ventilation hole prevents CO2 buildup", "Entrance lower than sleeping area"],
                        keywords: ["snow-shelter", "igloo", "winter"], difficulty: .advanced),

        // FIRE SCENARIOS
        SurvivalScenario(id: UUID(), title: "Starting Fire Without Matches", category: .fire,
                        content: "Fire = warmth, water purification, signaling, morale. Master multiple methods.",
                        steps: ["Gather tinder first", "Prepare kindling graduated sizes", "Build fire lay before ignition",
                               "Bow drill with hardwood fireboard and softwood spindle", "Maintain steady speed for friction",
                               "Carefully nurture coal to tinder bundle"],
                        warnings: ["Wet wood burns - find dry interior", "Wind kills ignition, helps established fires", "Keep water nearby"],
                        keywords: ["fire", "bow-drill", "friction"], difficulty: .advanced),

        SurvivalScenario(id: UUID(), title: "Fire Tinder Collection", category: .fire,
                        content: "Finding dry tinder is critical - the most difficult step in fire-starting.",
                        steps: ["Birch bark - inner white bark very flammable", "Dry grass - collect from center of tufts", "Cedar bark - shred easily",
                               "Cattail down - extremely dry and light", "Char cloth - pre-treat with charcoal dust",
                               "Pine pitch - burns hot, sticky"],
                        warnings: ["Test dryness by burning small piece", "Collect more than you think needed",
                                  "Soggy outer material often has dry core"],
                        keywords: ["tinder", "ignition", "fire-starting"], difficulty: .beginner),

        SurvivalScenario(id: UUID(), title: "Fire Signaling Techniques", category: .fire,
                        content: "Visible smoke and flames crucial for rescue - bright fires at night, smoke by day.",
                        steps: ["Day fires: Add green branches or leaves for smoke", "Night fires: Bright flame is visible 10+ miles",
                               "Make fires on high ground or clearings", "Create 3-fire triangle (distress signal)", "Keep fuel near by"],
                        warnings: ["Don't let fire go out in wilderness", "Green wood produces thick smoke (good for day)",
                                  "Dry wood burns bright (good for night)"],
                        keywords: ["signaling", "rescue", "fire"], difficulty: .beginner),

        // FOOD SCENARIOS
        SurvivalScenario(id: UUID(), title: "Finding Edible Insects", category: .food,
                        content: "Insects provide protein - abundant in wilderness, nutritious despite psychological barriers.",
                        steps: ["Grasshoppers: Abundant, remove legs and wings, cook over fire", "Crickets: Similar to grasshoppers",
                               "Termites: Look in wood, nutritious, cook", "Ants: Acidic but edible, useful salt source",
                               "Grubs: High fat content, cook thoroughly"],
                        warnings: ["Avoid brightly colored insects (usually poisonous)", "Cook all insects", "Allergies can be severe"],
                        keywords: ["insects", "protein", "food"], difficulty: .intermediate),

        SurvivalScenario(id: UUID(), title: "Fish Trapping and Catching", category: .food,
                        content: "Fish are major protein source - multiple effective methods from improvised materials.",
                        steps: ["Improvised spear: Sharpen stick or bind multiple points", "Deadfall trap: Heavy weight on trigger",
                               "Fish weir: Build rock dam with opening", "Hand grab: Feel under banks and catch directly",
                               "Improvised hook: Bone or thorns with line"],
                        warnings: ["Never eat raw fish (parasites)", "Check fish eggs aren't poisonous",
                                  "Some fish species have toxins in organs"],
                        keywords: ["fishing", "traps", "protein"], difficulty: .intermediate),

        SurvivalScenario(id: UUID(), title: "Identifying Poisonous Plants", category: .food,
                        content: "Learning what NOT to eat is as important as learning what to eat.",
                        steps: ["Universal Edibility Test: Touch to lip, spit out, wait 3 min", "Eat small amount, wait 15 min",
                               "Swallow small amount, wait 5 hours", "Learn common poisonous plants", "When unsure, don't eat",
                               "Bright colors usually mean poison"],
                        warnings: ["Some poisonous plants smell pleasant", "Cooking doesn't always destroy toxins",
                                  "Never taste unknown plants without testing"],
                        keywords: ["poisonous-plants", "identification", "safety"], difficulty: .beginner),

        // NAVIGATION SCENARIOS
        SurvivalScenario(id: UUID(), title: "Navigation Without Compass", category: .navigation,
                        content: "Find direction using celestial navigation, terrain features, and natural signs.",
                        steps: ["North Star: Brightest star in northern sky points north", "Sun rises east, sets west",
                               "Shadow stick: North-south line in 30 minutes", "Moss grows on north side (often)",
                               "Tree rings wider on sunny (south) side", "Wind patterns", "Animal behavior"],
                        warnings: ["Methods imprecise - give ±45° error", "Moss rule unreliable", "Shadow method needs 30 minutes"],
                        keywords: ["navigation", "direction-finding", "lost"], difficulty: .intermediate),

        SurvivalScenario(id: UUID(), title: "Making and Using Landmarks", category: .navigation,
                        content: "Leave marks for yourself or rescuers - helps with navigation and morale.",
                        steps: ["Cairns: Stack rocks in distinctive patterns", "Blaze: Cut marks on trees pointing direction",
                               "Arrow: Use stones or sticks to show direction", "Signal mirror: Catches light for distance signaling",
                               "Cloth flags: Bright colors visible from distance"],
                        warnings: ["Make marks obvious but avoid damage to environment", "Don't damage culturally significant trees"],
                        keywords: ["landmarks", "navigation", "signaling"], difficulty: .beginner),

        // MEDICAL SCENARIOS
        SurvivalScenario(id: UUID(), title: "Treating Minor Wounds", category: .medical,
                        content: "Infection is biggest threat - keep wounds clean and protected.",
                        steps: ["Clean with boiled water or urine (sterile)", "Remove debris and dead tissue", "Apply pressure to stop bleeding",
                               "Use clean cloth as bandage", "Elevate wound above heart", "Change dressing daily"],
                        warnings: ["Infection signs: Increasing redness, warmth, pus, smell", "Boil water if any doubt",
                                  "Don't seal wounds - need air to heal"],
                        keywords: ["wounds", "bleeding", "infection"], difficulty: .beginner),

        SurvivalScenario(id: UUID(), title: "Treating Hypothermia", category: .medical,
                        content: "Cold kills quickly - recognize and treat immediately.",
                        steps: ["Remove from cold environment", "Remove wet clothing slowly", "Warm center body (core) not extremities",
                               "Give warm drinks if conscious", "Don't rub skin - causes ice crystals",
                               "Monitor heart - can be weak"],
                        warnings: ["Person may appear dead but can recover", "Rewarming too fast causes heart failure",
                                  "Don't put person in hot water"],
                        keywords: ["hypothermia", "cold", "first-aid"], difficulty: .intermediate),

        SurvivalScenario(id: UUID(), title: "Treating Heat Exhaustion and Heat Stroke", category: .medical,
                        content: "Heat kills - understand the progression and treatment.",
                        steps: ["Move to shade immediately", "Drink water slowly", "Cool skin with water if available",
                               "Loosen clothing", "Rest completely", "Fan to encourage evaporation"],
                        warnings: ["Heat stroke (no sweating, confusion) is emergency", "Don't give water if vomiting",
                                  "Recovery takes 24+ hours"],
                        keywords: ["heat-stroke", "dehydration", "hot-weather"], difficulty: .beginner),

        SurvivalScenario(id: UUID(), title: "Treating Snake Bites", category: .medical,
                        content: "Most bites aren't fatal if treated - don't panic, move carefully.",
                        steps: ["Stop all activity immediately", "Remove jewelry (swelling)", "Keep bitten limb immobilized",
                               "Wash bite area gently", "Apply pressure bandage", "Seek medical help - evacuation critical"],
                        warnings: ["Don't cut bite or suck venom", "Don't apply tourniquet (causes tissue death)",
                                  "Antivenom availability varies"],
                        keywords: ["snake-bite", "venom", "emergency"], difficulty: .intermediate)
    ]
}

public struct PlantEntry: Identifiable, Codable {
    public let id: UUID
    public let commonName: String
    public let scientificName: String
    public let description: String
    public let edibility: Edibility
    public let medicinalUses: [String]
    public let warnings: [String]
    public let region: [String]
    public let leafShape: LeafShape
    public let flowerColors: [FlowerColor]
    public let heightRange: ClosedRange<Double> // in meters
    public let seasonality: [String]
    
    public enum Edibility: String, Codable {
        case edible = "Edible"
        case edibleWithPrep = "Edible with Preparation"
        case medicinalOnly = "Medicinal Only"
        case poisonous = "POISONOUS"
        case deadlyPoisonous = "DEADLY POISONOUS"
    }
    
    static let samplePlants: [PlantEntry] = [
        // EDIBLE PLANTS
        PlantEntry(id: UUID(), commonName: "Dandelion", scientificName: "Taraxacum officinale",
                  description: "Common weed with yellow flower. All parts edible.", edibility: .edible,
                  medicinalUses: ["Diuretic", "Liver support"], warnings: ["Avoid if ragweed allergy"],
                  region: ["North America", "Europe"], leafShape: .toothed, flowerColors: [.yellow],
                  heightRange: 0.1...0.4, seasonality: ["Spring", "Summer", "Fall"]),

        PlantEntry(id: UUID(), commonName: "Cattail", scientificName: "Typha latifolia",
                  description: "Tall marsh plant. Roots edible like potatoes, immature seed heads like corn.",
                  edibility: .edible, medicinalUses: ["Diuretic"], warnings: ["Only eat clean roots"],
                  region: ["North America", "Europe", "Asia"], leafShape: .needle, flowerColors: [.brown],
                  heightRange: 1.0...3.0, seasonality: ["Spring", "Summer", "Fall"]),

        PlantEntry(id: UUID(), commonName: "Wild Garlic (Ramps)", scientificName: "Allium tricoccum",
                  description: "Smells distinctly like garlic. Bulbs and leaves edible raw or cooked.",
                  edibility: .edible, medicinalUses: ["Antibacterial", "Heart health"],
                  warnings: ["Harvest sustainably - take only 10% from area"],
                  region: ["North America"], leafShape: .oval, flowerColors: [.white],
                  heightRange: 0.2...0.5, seasonality: ["Spring", "Early Summer"]),

        PlantEntry(id: UUID(), commonName: "Acorn", scientificName: "Quercus spp",
                  description: "Oak tree nuts. Require leaching to remove tannins. Nutritious carbs.",
                  edibility: .edibleWithPrep, medicinalUses: [], warnings: ["Must leach - soak 24+ hours"],
                  region: ["Worldwide"], leafShape: .lobed, flowerColors: [.yellow],
                  heightRange: 5.0...40.0, seasonality: ["Fall"]),

        PlantEntry(id: UUID(), commonName: "Pine Nuts", scientificName: "Pinus spp",
                  description: "Pine cone seeds. Nutritious and high in fat. Eat raw or roasted.",
                  edibility: .edible, medicinalUses: ["Energy source"], warnings: ["Lower cone to extract"],
                  region: ["Worldwide"], leafShape: .needle, flowerColors: [.yellow],
                  heightRange: 2.0...50.0, seasonality: ["Fall", "Winter"]),

        PlantEntry(id: UUID(), commonName: "Wild Strawberry", scientificName: "Fragaria vesca",
                  description: "Small but flavorful berries. Leaves make vitamin C tea.",
                  edibility: .edible, medicinalUses: ["Vitamin C", "Diuretic"],
                  warnings: ["Distinguish from mock strawberry which is insipid"],
                  region: ["Worldwide"], leafShape: .compound, flowerColors: [.white],
                  heightRange: 0.1...0.3, seasonality: ["Spring", "Summer"]),

        PlantEntry(id: UUID(), commonName: "Chickweed", scientificName: "Stellaria media",
                  description: "Tender plant resembling spinach. Mild taste. Good raw or cooked.",
                  edibility: .edible, medicinalUses: ["Nutritious", "Throat soother"],
                  warnings: [], region: ["North America", "Europe"], leafShape: .oval,
                  flowerColors: [.white], heightRange: 0.05...0.3, seasonality: ["Spring", "Fall"]),

        PlantEntry(id: UUID(), commonName: "Stinging Nettle", scientificName: "Urtica dioica",
                  description: "Hairs cause sting when touched. Nutritious greens when cooked or dried.",
                  edibility: .edible, medicinalUses: ["Iron", "Calcium", "Diuretic"],
                  warnings: ["Handle with gloves", "Cooking removes sting"], region: ["Worldwide"],
                  leafShape: .heart, flowerColors: [.green], heightRange: 0.3...1.5,
                  seasonality: ["Spring", "Summer", "Fall"]),

        // POISONOUS PLANTS
        PlantEntry(id: UUID(), commonName: "Poison Ivy", scientificName: "Toxicodendron radicans",
                  description: "Three-leaflet plant. 'Leaves of three, let it be.' Severe contact dermatitis.",
                  edibility: .poisonous, medicinalUses: [], warnings: ["DO NOT TOUCH", "Urushiol oil spreads"],
                  region: ["North America"], leafShape: .compound, flowerColors: [.white, .yellow],
                  heightRange: 0.1...30.0, seasonality: ["Spring", "Summer", "Fall"]),

        PlantEntry(id: UUID(), commonName: "Poison Oak", scientificName: "Toxicodendron pubescens",
                  description: "Similar to poison ivy but leaflets rounded. Also three-leaflet.",
                  edibility: .poisonous, medicinalUses: [],
                  warnings: ["Similar rash to poison ivy", "Burns skin like stinging"],
                  region: ["North America"], leafShape: .compound, flowerColors: [.white],
                  heightRange: 0.5...2.0, seasonality: ["Spring", "Summer", "Fall"]),

        PlantEntry(id: UUID(), commonName: "Poison Hemlock", scientificName: "Conium maculatum",
                  description: "Tall plant with white flower clusters. All parts deadly poisonous.",
                  edibility: .deadlyPoisonous, medicinalUses: [],
                  warnings: ["Can be absorbed through skin", "Distinctive musty smell",
                            "Can be confused with wild carrot"],
                  region: ["North America", "Europe"], leafShape: .compound, flowerColors: [.white],
                  heightRange: 0.5...1.5, seasonality: ["Spring", "Summer"]),

        PlantEntry(id: UUID(), commonName: "Deadly Nightshade", scientificName: "Atropa belladonna",
                  description: "Purple flowers, black berries. All parts deadly - tiny amounts fatal.",
                  edibility: .deadlyPoisonous, medicinalUses: [],
                  warnings: ["No safe dose", "Easily confused with other berries"],
                  region: ["Europe", "North Africa"], leafShape: .oval, flowerColors: [.purple],
                  heightRange: 0.5...1.5, seasonality: ["Summer", "Fall"]),

        PlantEntry(id: UUID(), commonName: "Castor Bean", scientificName: "Ricinus communis",
                  description: "Castor oil plant. Seeds contain ricin - one of deadliest toxins.",
                  edibility: .deadlyPoisonous, medicinalUses: [],
                  warnings: ["As few as 2-3 seeds can be fatal", "Don't touch if skin broken"],
                  region: ["Tropical worldwide"], leafShape: .compound, flowerColors: [.red],
                  heightRange: 1.0...3.0, seasonality: ["Spring", "Summer"]),

        // MEDICINAL PLANTS
        PlantEntry(id: UUID(), commonName: "Plantain", scientificName: "Plantago major",
                  description: "Common 'weed'. Leaves reduce inflammation. Good poultice for wounds.",
                  edibility: .edible, medicinalUses: ["Wound healing", "Anti-inflammatory"],
                  warnings: ["Young leaves best"], region: ["Worldwide"],
                  leafShape: .oval, flowerColors: [.green], heightRange: 0.05...0.4,
                  seasonality: ["Spring", "Summer", "Fall"]),

        PlantEntry(id: UUID(), commonName: "Willow Bark", scientificName: "Salix alba",
                  description: "Bark contains salicin (like aspirin). Pain relief and fever reducer.",
                  edibility: .medicinalOnly, medicinalUses: ["Pain relief", "Fever reducer"],
                  warnings: ["Bitter taste", "May interact with medications"],
                  region: ["Worldwide"], leafShape: .lanceolate, flowerColors: [.yellow],
                  heightRange: 5.0...25.0, seasonality: ["Spring", "Summer"]),

        PlantEntry(id: UUID(), commonName: "Ginger (Wild)", scientificName: "Zingiber officinale",
                  description: "Rhizomes used fresh or dried. Aids digestion and nausea.",
                  edibility: .edible, medicinalUses: ["Digestion", "Nausea", "Inflammation"],
                  warnings: [], region: ["Tropical Asia"], leafShape: .lanceolate,
                  flowerColors: [.yellow], heightRange: 0.3...1.0, seasonality: ["Summer", "Fall"])
    ]
}

public enum LeafShape: String, Codable {
    case oval, lanceolate, heart, lobed, toothed, compound, needle, scale
}

public enum FlowerColor: String, Codable {
    case white, yellow, red, pink, purple, blue, orange, green, brown
}

public struct PlantFeatures {
    public var leafShape: LeafShape?
    public var flowerColor: FlowerColor?
    public var estimatedHeight: Double?
    public var hasThreeLeaves: Bool?
    public var hasThorns: Bool?
    
    public init(leafShape: LeafShape? = nil, flowerColor: FlowerColor? = nil, estimatedHeight: Double? = nil, hasThreeLeaves: Bool? = nil, hasThorns: Bool? = nil) {
        self.leafShape = leafShape
        self.flowerColor = flowerColor
        self.estimatedHeight = estimatedHeight
        self.hasThreeLeaves = hasThreeLeaves
        self.hasThorns = hasThorns
    }
}

public struct PlantMatch {
    public let plant: PlantEntry
    public let confidence: Double
}

public struct FirstAidProcedure: Identifiable {
    public let id = UUID()
    public let condition: String
    public let severity: Severity
    public let steps: [String]
    public let warnings: [String]
    public let keywords: [String]
    
    public enum Severity: String {
        case minor, moderate, severe, lifeThreatening
    }
    
    static let procedures: [FirstAidProcedure] = [
        FirstAidProcedure(
            condition: "Bleeding - Severe",
            severity: .lifeThreatening,
            steps: [
                "Apply direct pressure with cleanest available material",
                "Elevate wound above heart if possible",
                "Apply pressure to arterial pressure points if bleeding continues",
                "Apply tourniquet as last resort (note time applied)",
                "Seek immediate medical evacuation"
            ],
            warnings: [
                "Do not remove embedded objects",
                "Do not release pressure to check wound",
                "Tourniquets can cause limb loss if left too long"
            ],
            keywords: ["bleeding", "hemorrhage", "blood", "wound", "tourniquet"]
        ),
        FirstAidProcedure(
            condition: "Hypothermia",
            severity: .severe,
            steps: [
                "Remove from cold environment",
                "Remove wet clothing",
                "Insulate from ground",
                "Apply heat to core (armpits, neck, groin)",
                "Give warm fluids if conscious",
                "Do NOT rub extremities",
                "Monitor for cardiac issues"
            ],
            warnings: [
                "Rapid rewarming can cause cardiac arrest",
                "Handle gently - cold heart is fragile",
                "Alcohol does NOT help"
            ],
            keywords: ["hypothermia", "cold", "shivering", "freezing", "exposure"]
        )
    ]
}

// MARK: - Weather Prediction

public struct WeatherObservations {
    public var cloudType: CloudType?
    public var cloudMovement: Direction?
    public var pressureTrend: Trend?
    public var windShift: Bool = false
    public var birdsFlying: FlightHeight?
    public var humidity: HumidityLevel?
    public var visibility: Visibility?
    
    public init() {}
    
    public enum CloudType {
        case cirrus, cumulus, stratus, cumulonimbus, nimbostratus
    }
    
    public enum Direction {
        case fromWest, fromEast, fromNorth, fromSouth
    }
    
    public enum Trend {
        case rising, falling, steady
    }
    
    public enum FlightHeight {
        case high, low
    }
    
    public enum HumidityLevel {
        case dry, moderate, humid
    }
    
    public enum Visibility {
        case clear, hazy, poor
    }
}

public struct WeatherPrediction {
    public let summary: String
    public let details: [String]
    public let confidence: Double
    public let timeframe: String
}
