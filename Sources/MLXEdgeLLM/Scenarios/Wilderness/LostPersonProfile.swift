import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - LostPersonProfile

struct LostPersonProfile {
    let age: Int
    let experience: Experience
    let equipment: [Equipment]
    let physicalCondition: PhysicalCondition
    let mentalState: MentalState
    
    enum Experience {
        case novice
        case intermediate
        case advanced
    }
    
    enum Equipment: String, CaseIterable {
        case map
        case compass
        case flashlight
        case whistle
        case firstAidKit
        case waterBottle
        case food
    }
    
    enum PhysicalCondition {
        case excellent
        case good
        case fair
        case poor
    }
    
    enum MentalState {
        case calm
        case anxious
        case confused
        case distressed
    }
}

// MARK: - LostPersonProfileViewModel

class LostPersonProfileViewModel: ObservableObject {
    @Published var age: Int = 30
    @Published var experience: LostPersonProfile.Experience = .intermediate
    @Published var equipment: Set<LostPersonProfile.Equipment> = [.map, .compass]
    @Published var physicalCondition: LostPersonProfile.PhysicalCondition = .good
    @Published var mentalState: LostPersonProfile.MentalState = .calm
    
    func updateProfile() -> LostPersonProfile {
        return LostPersonProfile(
            age: age,
            experience: experience,
            equipment: Array(equipment),
            physicalCondition: physicalCondition,
            mentalState: mentalState
        )
    }
}

// MARK: - LostPersonProfileView

struct LostPersonProfileView: View {
    @StateObject private var viewModel = LostPersonProfileViewModel()
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Personal Information")) {
                    TextField("Age", value: $viewModel.age, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                    
                    Picker("Experience", selection: $viewModel.experience) {
                        ForEach(LostPersonProfile.Experience.allCases, id: \.self) { experience in
                            Text(experience.rawValue.capitalized)
                        }
                    }
                }
                
                Section(header: Text("Equipment")) {
                    ForEach(LostPersonProfile.Equipment.allCases, id: \.self) { equipment in
                        Toggle(equipment.rawValue.capitalized, isOn: Binding(
                            get: { viewModel.equipment.contains(equipment) },
                            set: { viewModel.equipment.toggleMembership(of: equipment, isMember: $0) }
                        ))
                    }
                }
                
                Section(header: Text("Physical Condition")) {
                    Picker("Physical Condition", selection: $viewModel.physicalCondition) {
                        ForEach(LostPersonProfile.PhysicalCondition.allCases, id: \.self) { condition in
                            Text(condition.rawValue.capitalized)
                        }
                    }
                }
                
                Section(header: Text("Mental State")) {
                    Picker("Mental State", selection: $viewModel.mentalState) {
                        ForEach(LostPersonProfile.MentalState.allCases, id: \.self) { state in
                            Text(state.rawValue.capitalized)
                        }
                    }
                }
            }
            
            Button(action: {
                let profile = viewModel.updateProfile()
                print("Updated Profile: \(profile)")
            }) {
                Text("Update Profile")
            }
            .padding()
        }
        .navigationTitle("Lost Person Profile")
    }
}

// MARK: - Preview

struct LostPersonProfileView_Previews: PreviewProvider {
    static var previews: some View {
        LostPersonProfileView()
    }
}