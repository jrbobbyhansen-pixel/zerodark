// ThreatCategory.swift — Threat classification categories (Boeing SDR-Hazards pattern)

import Foundation
import SwiftUI

/// Reported threat classification category (AI-classified from free text)
public enum ReportedThreatCategory: String, Codable, CaseIterable {
    case none
    case environmental
    case personnel
    case equipment
    case chemical
    case biological
    case radiological
    case explosive
    case intelligence

    public var displayName: String {
        switch self {
        case .none: return "No Threat"
        case .environmental: return "Environmental"
        case .personnel: return "Personnel"
        case .equipment: return "Equipment"
        case .chemical: return "Chemical"
        case .biological: return "Biological"
        case .radiological: return "Radiological"
        case .explosive: return "Explosive"
        case .intelligence: return "Intelligence"
        }
    }

    public var icon: String {
        switch self {
        case .none: return "checkmark.shield.fill"
        case .environmental: return "cloud.rain.fill"
        case .personnel: return "person.fill"
        case .equipment: return "gearshape.fill"
        case .chemical: return "beaker.fill"
        case .biological: return "drop.fill"
        case .radiological: return "radiowaves.right"
        case .explosive: return "burst.fill"
        case .intelligence: return "eye.fill"
        }
    }

    public var color: Color {
        switch self {
        case .none: return ZDDesign.successGreen
        case .environmental: return Color(red: 0.2, green: 0.8, blue: 0.8)
        case .personnel: return Color(red: 1.0, green: 0.8, blue: 0.2)
        case .equipment: return Color(red: 0.8, green: 0.4, blue: 0.2)
        case .chemical: return Color(red: 0.8, green: 0.2, blue: 0.8)
        case .biological: return Color(red: 0.8, green: 0.2, blue: 0.2)
        case .radiological: return Color(red: 1.0, green: 1.0, blue: 0.0)
        case .explosive: return ZDDesign.signalRed
        case .intelligence: return Color(red: 0.4, green: 0.6, blue: 1.0)
        }
    }

    public var priority: Int {
        switch self {
        case .none: return 0
        case .environmental: return 2
        case .personnel: return 4
        case .equipment: return 3
        case .chemical: return 5
        case .biological: return 5
        case .radiological: return 5
        case .explosive: return 5
        case .intelligence: return 2
        }
    }
}
