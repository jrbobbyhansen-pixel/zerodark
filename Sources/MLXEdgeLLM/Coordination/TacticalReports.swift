// TacticalReports.swift — Military Report Templates
// SITREP, 9-Line MEDEVAC, SALUTE, Contact Report

import Foundation
import CoreLocation
import SwiftUI

enum ReportType: String, Identifiable, CaseIterable {
    case sitrep = "SITREP"
    case medevac = "9-Line MEDEVAC"
    case salute = "SALUTE"
    case contact = "Contact Report"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sitrep: return "doc.plaintext"
        case .medevac: return "cross.fill"
        case .salute: return "eye.fill"
        case .contact: return "scope"
        }
    }
}

// MARK: - SITREP

struct SITREPReport: Codable {
    var dateTime: Date = Date()
    var location: String = ""           // MGRS
    var unitCallsign: String = ""
    var situation: String = ""          // Current situation
    var activities: String = ""         // Recent activities
    var casualties: String = "None"     // Friendly casualties
    var equipmentStatus: String = ""    // Equipment/ammo status
    var supplies: String = ""           // Supply status
    var morale: String = "Good"         // Unit morale
    var intentions: String = ""         // Next planned actions
    var remarks: String = ""            // Additional info

    func formatted() -> String {
        """
        SITREP
        ======
        DTG: \(dateTime.formatted())
        LOCATION: \(location)
        UNIT: \(unitCallsign)

        1. SITUATION: \(situation)
        2. ACTIVITIES: \(activities)
        3. CASUALTIES: \(casualties)
        4. EQUIPMENT: \(equipmentStatus)
        5. SUPPLIES: \(supplies)
        6. MORALE: \(morale)
        7. INTENTIONS: \(intentions)
        8. REMARKS: \(remarks)

        // END SITREP //
        """
    }
}

// MARK: - 9-Line MEDEVAC

struct MEDEVACReport: Codable {
    var line1_location: String = ""         // MGRS of pickup site
    var line2_frequency: String = ""        // Radio frequency/callsign
    var line3_patients: String = ""         // A=Urgent, B=Priority, C=Routine, D=Conv, E=Dead
    var line4_equipment: String = "None"    // A=None, B=Hoist, C=Extraction, D=Ventilator
    var line5_litter: String = "0L 1A"      // # Litter, # Ambulatory
    var line6_security: String = "N"        // N=No enemy, P=Possible, E=Enemy, X=Armed escort
    var line7_marking: String = "C"         // A=Panels, B=Pyro, C=Smoke, D=None, E=Other
    var line8_nationality: String = "A"     // A=US Mil, B=US Civ, C=Non-US Mil, D=Non-US Civ, E=EPW
    var line9_terrain: String = ""          // NBC contamination / terrain obstacles

    func formatted() -> String {
        """
        9-LINE MEDEVAC REQUEST
        ======================

        LINE 1 (Location): \(line1_location)
        LINE 2 (Freq/Callsign): \(line2_frequency)
        LINE 3 (# Patients by Precedence): \(line3_patients)
        LINE 4 (Special Equipment): \(line4_equipment)
        LINE 5 (# Patients by Type): \(line5_litter)
        LINE 6 (Security at PZ): \(line6_security)
        LINE 7 (Method of Marking): \(line7_marking)
        LINE 8 (Patient Nationality): \(line8_nationality)
        LINE 9 (NBC/Terrain): \(line9_terrain)

        // END 9-LINE //
        """
    }
}

// MARK: - SALUTE Report

struct SALUTEReport: Codable {
    var size: String = ""               // Number and type of personnel/vehicles
    var activity: String = ""           // What they're doing
    var location: String = ""           // MGRS
    var unit: String = ""               // Identifying info (uniforms, insignia, markings)
    var time: Date = Date()             // When observed
    var equipment: String = ""          // Weapons, vehicles, equipment

    func formatted() -> String {
        """
        SALUTE REPORT
        =============

        S - SIZE: \(size)
        A - ACTIVITY: \(activity)
        L - LOCATION: \(location)
        U - UNIT: \(unit)
        T - TIME: \(time.formatted())
        E - EQUIPMENT: \(equipment)

        // END SALUTE //
        """
    }
}

// MARK: - Contact Report

struct ContactReport: Codable {
    var dateTime: Date = Date()
    var location: String = ""           // MGRS
    var enemySize: String = ""          // Estimated size
    var enemyActivity: String = ""      // What they're doing
    var direction: String = ""          // Direction of travel/fire
    var actionsTaken: String = ""       // What you did
    var requestedSupport: String = ""   // What you need
    var casualties: String = "None"     // Friendly casualties

    func formatted() -> String {
        """
        CONTACT REPORT
        ==============
        DTG: \(dateTime.formatted())
        LOCATION: \(location)

        ENEMY SIZE: \(enemySize)
        ENEMY ACTIVITY: \(enemyActivity)
        DIRECTION: \(direction)

        ACTIONS TAKEN: \(actionsTaken)
        REQUEST: \(requestedSupport)
        CASUALTIES: \(casualties)

        // END CONTACT //
        """
    }
}
