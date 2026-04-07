import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - VirtualVictim

class VirtualVictim: ObservableObject, Identifiable {
    let id = UUID()
    var name: String
    var age: Int
    var gender: String
    var location: CLLocationCoordinate2D
    var condition: Condition
    var vitals: Vitals
    var treatment: Treatment?
    var outcome: Outcome?

    init(name: String, age: Int, gender: String, location: CLLocationCoordinate2D, condition: Condition) {
        self.name = name
        self.age = age
        self.gender = gender
        self.location = location
        self.condition = condition
        self.vitals = Vitals(condition: condition)
    }

    func applyTreatment(_ treatment: Treatment) {
        self.treatment = treatment
        vitals.update(with: treatment)
        outcome = determineOutcome()
    }

    private func determineOutcome() -> Outcome {
        // Placeholder logic for determining outcome
        if vitals.stable {
            return .stable
        } else {
            return .critical
        }
    }
}

// MARK: - Condition

enum Condition: String, Codable {
    case minorInjury
    case majorInjury
    case criticalInjury
}

// MARK: - Vitals

class Vitals: ObservableObject {
    @Published var heartRate: Int
    @Published var bloodPressure: String
    @Published var oxygenSaturation: Int
    @Published var stable: Bool

    init(condition: Condition) {
        switch condition {
        case .minorInjury:
            heartRate = 90
            bloodPressure = "120/80"
            oxygenSaturation = 98
            stable = true
        case .majorInjury:
            heartRate = 120
            bloodPressure = "140/90"
            oxygenSaturation = 92
            stable = false
        case .criticalInjury:
            heartRate = 160
            bloodPressure = "160/100"
            oxygenSaturation = 85
            stable = false
        }
    }

    func update(with treatment: Treatment) {
        // Placeholder logic for updating vitals based on treatment
        heartRate -= treatment.heartRateEffect
        bloodPressure = "\(Int(bloodPressure.split(separator: "/")[0]) + treatment.bloodPressureEffect)/\(Int(bloodPressure.split(separator: "/")[1]) + treatment.bloodPressureEffect)"
        oxygenSaturation += treatment.oxygenSaturationEffect
        stable = heartRate < 100 && bloodPressure == "120/80" && oxygenSaturation > 95
    }
}

// MARK: - Treatment

struct Treatment: Codable {
    let name: String
    let heartRateEffect: Int
    let bloodPressureEffect: Int
    let oxygenSaturationEffect: Int
}

// MARK: - Outcome

enum Outcome: String, Codable {
    case stable
    case critical
}

// MARK: - VirtualVictimsViewModel

class VirtualVictimsViewModel: ObservableObject {
    @Published var victims: [VirtualVictim] = []

    func generateVictim() {
        let name = "Victim \(victims.count + 1)"
        let age = Int.random(in: 18...80)
        let gender = ["Male", "Female"].randomElement() ?? "Male"
        let location = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let condition = Condition.allCases.randomElement() ?? .minorInjury
        let victim = VirtualVictim(name: name, age: age, gender: gender, location: location, condition: condition)
        victims.append(victim)
    }
}

// MARK: - VirtualVictimsView

struct VirtualVictimsView: View {
    @StateObject private var viewModel = VirtualVictimsViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.victims) { victim in
                VStack(alignment: .leading) {
                    Text(victim.name)
                        .font(.headline)
                    Text("Age: \(victim.age), Gender: \(victim.gender)")
                        .font(.subheadline)
                    Text("Condition: \(victim.condition.rawValue)")
                        .font(.subheadline)
                    Text("Heart Rate: \(victim.vitals.heartRate), Blood Pressure: \(victim.vitals.bloodPressure), Oxygen Saturation: \(victim.vitals.oxygenSaturation)")
                        .font(.subheadline)
                    if let treatment = victim.treatment {
                        Text("Treatment: \(treatment.name)")
                            .font(.subheadline)
                    }
                    if let outcome = victim.outcome {
                        Text("Outcome: \(outcome.rawValue)")
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Virtual Victims")
            .toolbar {
                Button(action: viewModel.generateVictim) {
                    Label("Generate Victim", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Preview

struct VirtualVictimsView_Previews: PreviewProvider {
    static var previews: some View {
        VirtualVictimsView()
    }
}