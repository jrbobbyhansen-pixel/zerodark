// ThreatClassMap.swift — Maps COCO YOLOv8 class IDs to tactical threat categories
// Configurable distance-to-threat-level mapping for field operations

import Foundation

// MARK: - Tactical Threat Category

enum TacticalThreatCategory: String, CaseIterable {
    case human          // Person, group
    case vehicle        // Car, truck, bus, motorcycle
    case weapon         // Knife, scissors (COCO subset)
    case container      // Backpack, suitcase, handbag (potential IED)
    case animal         // Dog, horse, bear
    case structural     // Fire hydrant, stop sign, traffic light
    case environmental  // Umbrella, kite (visual clutter)
    case cover          // Objects usable as cover (vehicles, large furniture)
}

// MARK: - Tactical Threat Level

enum TacticalThreatLevel: Int, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: TacticalThreatLevel, rhs: TacticalThreatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - YOLO Detection

struct YOLODetection {
    let classId: Int
    let className: String
    let confidence: Float
    let boundingBox: CGRect       // Normalized 0-1
    let position3D: SIMD3<Float>? // World coordinates (nil if no depth)
    let distance: Float?          // Meters from camera

    var tacticalCategory: TacticalThreatCategory {
        ThreatClassMap.category(for: classId)
    }

    func tacticalLevel(config: ThreatClassMap.Config = .default) -> TacticalThreatLevel {
        ThreatClassMap.threatLevel(for: classId, distance: distance, config: config)
    }
}

// MARK: - ThreatClassMap

struct ThreatClassMap {

    struct Config {
        // Distance thresholds for human threats (meters)
        var humanCriticalRange: Float = 3.0
        var humanHighRange: Float = 5.0
        var humanMediumRange: Float = 10.0
        var humanLowRange: Float = 20.0

        // Distance thresholds for vehicle threats
        var vehicleHighRange: Float = 10.0
        var vehicleMediumRange: Float = 20.0

        // Weapon is always critical regardless of distance
        var weaponAlwaysCritical: Bool = true

        // Minimum confidence to report
        var minConfidence: Float = 0.35

        static let `default` = Config()
    }

    // COCO class ID -> category mapping
    // Full COCO 80-class list: https://cocodataset.org/#explore
    private static let classCategories: [Int: TacticalThreatCategory] = [
        // Humans
        0: .human,       // person

        // Vehicles
        1: .vehicle,     // bicycle
        2: .vehicle,     // car
        3: .vehicle,     // motorcycle
        5: .vehicle,     // bus
        7: .vehicle,     // truck
        8: .vehicle,     // boat

        // Animals
        14: .animal,     // bird
        15: .animal,     // cat
        16: .animal,     // dog
        17: .animal,     // horse
        18: .animal,     // sheep
        19: .animal,     // cow
        20: .animal,     // elephant
        21: .animal,     // bear

        // Weapons/tools
        43: .weapon,     // knife
        76: .weapon,     // scissors

        // Containers (potential concealment)
        24: .container,  // backpack
        26: .container,  // handbag
        28: .container,  // suitcase

        // Structural
        9: .structural,  // traffic light
        10: .structural, // fire hydrant
        11: .structural, // stop sign
        13: .structural, // bench

        // Environmental clutter
        25: .environmental, // umbrella

        // Cover — large objects usable for concealment/protection
        // These are also mapped under .vehicle above; cover classification
        // is applied contextually via coverCategory(for:distance:)
        56: .structural,     // chair (small, not cover)
        57: .cover,          // couch
        59: .cover,          // bed
        60: .structural,     // dining table
        72: .cover,          // refrigerator
    ]

    /// Returns `.cover` for objects that can serve as ballistic/visual cover
    /// based on size heuristics and distance. Vehicles already in .vehicle
    /// category can also serve as cover — use this for non-vehicle cover objects.
    static func coverCategory(for classId: Int, distance: Float?) -> TacticalThreatCategory? {
        let cat = category(for: classId)
        // Vehicles at close range are potential cover
        if cat == .vehicle, let d = distance, d < 15.0 { return .cover }
        if cat == .cover { return .cover }
        return nil
    }

    static func category(for classId: Int) -> TacticalThreatCategory {
        classCategories[classId] ?? .environmental
    }

    static func threatLevel(
        for classId: Int,
        distance: Float?,
        config: Config = .default
    ) -> TacticalThreatLevel {
        let category = category(for: classId)
        let dist = distance ?? Float.greatestFiniteMagnitude

        switch category {
        case .human:
            if dist < config.humanCriticalRange { return .critical }
            if dist < config.humanHighRange { return .high }
            if dist < config.humanMediumRange { return .medium }
            if dist < config.humanLowRange { return .low }
            return .none

        case .vehicle:
            if dist < config.vehicleHighRange { return .high }
            if dist < config.vehicleMediumRange { return .medium }
            return .low

        case .weapon:
            return config.weaponAlwaysCritical ? .critical : .high

        case .container:
            // Unattended containers near humans are more concerning
            if dist < 5.0 { return .medium }
            return .low

        case .animal:
            if dist < 5.0 { return .medium }
            return .low

        case .structural:
            return .none

        case .environmental:
            return .none

        case .cover:
            return .none  // Cover objects are not threats — they provide protection
        }
    }

    /// COCO class name lookup
    static let classNames: [Int: String] = [
        0: "person", 1: "bicycle", 2: "car", 3: "motorcycle", 4: "airplane",
        5: "bus", 6: "train", 7: "truck", 8: "boat", 9: "traffic light",
        10: "fire hydrant", 11: "stop sign", 12: "parking meter", 13: "bench",
        14: "bird", 15: "cat", 16: "dog", 17: "horse", 18: "sheep",
        19: "cow", 20: "elephant", 21: "bear", 22: "zebra", 23: "giraffe",
        24: "backpack", 25: "umbrella", 26: "handbag", 27: "tie", 28: "suitcase",
        29: "frisbee", 30: "skis", 31: "snowboard", 32: "sports ball", 33: "kite",
        34: "baseball bat", 35: "baseball glove", 36: "skateboard", 37: "surfboard",
        38: "tennis racket", 39: "bottle", 40: "wine glass", 41: "cup",
        42: "fork", 43: "knife", 44: "spoon", 45: "bowl", 46: "banana",
        47: "apple", 48: "sandwich", 49: "orange", 50: "broccoli",
        51: "carrot", 52: "hot dog", 53: "pizza", 54: "donut", 55: "cake",
        56: "chair", 57: "couch", 58: "potted plant", 59: "bed",
        60: "dining table", 61: "toilet", 62: "tv", 63: "laptop",
        64: "mouse", 65: "remote", 66: "keyboard", 67: "cell phone",
        68: "microwave", 69: "oven", 70: "toaster", 71: "sink",
        72: "refrigerator", 73: "book", 74: "clock", 75: "vase",
        76: "scissors", 77: "teddy bear", 78: "hair drier", 79: "toothbrush"
    ]
}
