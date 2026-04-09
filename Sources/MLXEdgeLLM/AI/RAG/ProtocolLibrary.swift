import Foundation
import SwiftUI

// MARK: - ProtocolLibrary

class ProtocolLibrary: ObservableObject {
    @Published var protocols: [ProtocolTemplate] = [
        MEDEVAC(),
        SITREP(),
        ContactReport(),
        RadioCheck()
    ]
    
    func searchProtocols(query: String) -> [ProtocolTemplate] {
        protocols.filter { $0.name.lowercased().contains(query.lowercased()) }
    }
}

// MARK: - ProtocolTemplate

protocol ProtocolTemplate {
    var name: String { get }
    var description: String { get }
    var version: String { get }
    var template: String { get }
}

// MARK: - MEDEVAC

struct MEDEVAC: ProtocolTemplate {
    var name: String { "MEDEVAC" }
    var description: String { "Medical evacuation protocol." }
    var version: String { "1.0" }
    var template: String {
        """
        **MEDEVAC Protocol**

        1. **Identify Casualty**: Assess the injured person's condition.
        2. **Secure the Area**: Ensure the scene is safe for both the casualty and rescuers.
        3. **Call for Help**: Use radio or other means to request medical assistance.
        4. **Provide Basic Care**: Administer first aid if trained.
        5. **Evacuate**: Move the casualty to a safe location or vehicle.
        6. **Report Status**: Update command with casualty's condition and location.
        """
    }
}

// MARK: - SITREP

struct SITREP: ProtocolTemplate {
    var name: String { "SITREP" }
    var description: String { "Situation report protocol." }
    var version: String { "1.0" }
    var template: String {
        """
        **SITREP Protocol**

        1. **Assess the Situation**: Evaluate the current environment and conditions.
        2. **Identify Threats**: Determine any potential dangers or adversaries.
        3. **Report Casualties**: Provide information on any injured personnel.
        4. **Report Resources**: Indicate available supplies and equipment.
        5. **Report Location**: Share the current position and any landmarks.
        6. **Report Mission Status**: Update on the progress of the mission.
        """
    }
}

// MARK: - ContactReport

struct ContactReport: ProtocolTemplate {
    var name: String { "Contact Report" }
    var description: String { "Contact report protocol." }
    var version: String { "1.0" }
    var template: String {
        """
        **Contact Report Protocol**

        1. **Identify Contact**: Note the identity and type of contact.
        2. **Assess Situation**: Evaluate the environment and conditions.
        3. **Report Location**: Provide the contact's location and any landmarks.
        4. **Report Status**: Describe the contact's actions and intentions.
        5. **Report Casualties**: Indicate any injured personnel.
        6. **Report Resources**: Share available supplies and equipment.
        7. **Report Mission Status**: Update on the progress of the mission.
        """
    }
}

// MARK: - RadioCheck

struct RadioCheck: ProtocolTemplate {
    var name: String { "Radio Check" }
    var description: String { "Radio check protocol." }
    var version: String { "1.0" }
    var template: String {
        """
        **Radio Check Protocol**

        1. **Initiate Check**: Transmit "Delta 1, this is Delta 2, radio check."
        2. **Respond**: Wait for a response from the other party.
        3. **Report Status**: Indicate if the radio is working properly.
        4. **Report Interference**: Note any issues with signal quality.
        5. **Report Battery**: Share the status of the radio's battery.
        6. **Report Location**: Provide the current position and any landmarks.
        7. **Report Mission Status**: Update on the progress of the mission.
        """
    }
}