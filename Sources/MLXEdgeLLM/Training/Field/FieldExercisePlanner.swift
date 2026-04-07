import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - FieldExercisePlanner

class FieldExercisePlanner: ObservableObject {
    @Published var logistics: Logistics
    @Published var safety: Safety
    @Published var objectives: [Objective]
    @Published var evaluationCriteria: [EvaluationCriterion]
    @Published var participants: [Participant]
    
    init(logistics: Logistics, safety: Safety, objectives: [Objective], evaluationCriteria: [EvaluationCriterion], participants: [Participant]) {
        self.logistics = logistics
        self.safety = safety
        self.objectives = objectives
        self.evaluationCriteria = evaluationCriteria
        self.participants = participants
    }
}

// MARK: - Logistics

struct Logistics {
    var location: CLLocationCoordinate2D
    var date: Date
    var duration: TimeInterval
    var equipment: [String]
}

// MARK: - Safety

struct Safety {
    var emergencyPlan: String
    var firstAidKitLocation: CLLocationCoordinate2D
    var weatherConditions: String
}

// MARK: - Objective

struct Objective {
    var id: UUID
    var description: String
    var priority: Int
}

// MARK: - EvaluationCriterion

struct EvaluationCriterion {
    var id: UUID
    var description: String
    var weight: Double
}

// MARK: - Participant

struct Participant {
    var id: UUID
    var name: String
    var role: String
    var status: ParticipantStatus
}

// MARK: - ParticipantStatus

enum ParticipantStatus {
    case pending
    case confirmed
    case completed
}

// MARK: - FieldExercisePlannerView

struct FieldExercisePlannerView: View {
    @StateObject private var planner = FieldExercisePlanner(
        logistics: Logistics(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), date: Date(), duration: 3600, equipment: ["Rifle", "Ammunition"]),
        safety: Safety(emergencyPlan: "Evacuate to the north", firstAidKitLocation: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), weatherConditions: "Sunny"),
        objectives: [
            Objective(id: UUID(), description: "Secure the objective", priority: 1),
            Objective(id: UUID(), description: "Evacuate safely", priority: 2)
        ],
        evaluationCriteria: [
            EvaluationCriterion(id: UUID(), description: "Objective completion", weight: 0.5),
            EvaluationCriterion(id: UUID(), description: "Safety protocols followed", weight: 0.3),
            EvaluationCriterion(id: UUID(), description: "Efficiency", weight: 0.2)
        ],
        participants: [
            Participant(id: UUID(), name: "John Doe", role: "Leader", status: .pending),
            Participant(id: UUID(), name: "Jane Smith", role: "Support", status: .confirmed)
        ]
    )
    
    var body: some View {
        VStack {
            Text("Field Exercise Planner")
                .font(.largeTitle)
                .padding()
            
            LogisticsView(logistics: $planner.logistics)
            SafetyView(safety: $planner.safety)
            ObjectivesView(objectives: $planner.objectives)
            EvaluationCriteriaView(evaluationCriteria: $planner.evaluationCriteria)
            ParticipantsView(participants: $planner.participants)
        }
        .padding()
    }
}

// MARK: - LogisticsView

struct LogisticsView: View {
    @Binding var logistics: Logistics
    
    var body: some View {
        Group {
            Text("Logistics")
                .font(.title2)
            
            TextField("Location", value: Binding(
                get: { "\(logistics.location.latitude), \(logistics.location.longitude)" },
                set: { newValue in
                    let components = newValue.split(separator: ",")
                    if components.count == 2, let lat = Double(components[0]), let lon = Double(components[1]) {
                        logistics.location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                }
            ), format: .number)
            DatePicker("Date", selection: $logistics.date, displayedComponents: .date)
            DatePicker("Duration", selection: $logistics.duration, displayedComponents: .hourAndMinute)
            List(logistics.equipment, id: \.self) { equipment in
                Text(equipment)
            }
            .onDelete { indexSet in
                logistics.equipment.remove(atOffsets: indexSet)
            }
            Button(action: {
                logistics.equipment.append("New Equipment")
            }) {
                Text("Add Equipment")
            }
        }
        .padding()
    }
}

// MARK: - SafetyView

struct SafetyView: View {
    @Binding var safety: Safety
    
    var body: some View {
        Group {
            Text("Safety")
                .font(.title2)
            
            TextField("Emergency Plan", text: $safety.emergencyPlan)
            TextField("First Aid Kit Location", value: Binding(
                get: { "\(safety.firstAidKitLocation.latitude), \(safety.firstAidKitLocation.longitude)" },
                set: { newValue in
                    let components = newValue.split(separator: ",")
                    if components.count == 2, let lat = Double(components[0]), let lon = Double(components[1]) {
                        safety.firstAidKitLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    }
                }
            ), format: .number)
            TextField("Weather Conditions", text: $safety.weatherConditions)
        }
        .padding()
    }
}

// MARK: - ObjectivesView

struct ObjectivesView: View {
    @Binding var objectives: [Objective]
    
    var body: some View {
        Group {
            Text("Objectives")
                .font(.title2)
            
            List($objectives) { $objective in
                HStack {
                    Text(objective.description)
                    Spacer()
                    Text("Priority: \(objective.priority)")
                }
            }
            .onDelete { indexSet in
                objectives.remove(atOffsets: indexSet)
            }
            Button(action: {
                objectives.append(Objective(id: UUID(), description: "New Objective", priority: objectives.count + 1))
            }) {
                Text("Add Objective")
            }
        }
        .padding()
    }
}

// MARK: - EvaluationCriteriaView

struct EvaluationCriteriaView: View {
    @Binding var evaluationCriteria: [EvaluationCriterion]
    
    var body: some View {
        Group {
            Text("Evaluation Criteria")
                .font(.title2)
            
            List($evaluationCriteria) { $criterion in
                HStack {
                    Text(criterion.description)
                    Spacer()
                    Text("Weight: \(criterion.weight, specifier: "%.2f")")
                }
            }
            .onDelete { indexSet in
                evaluationCriteria.remove(atOffsets: indexSet)
            }
            Button(action: {
                evaluationCriteria.append(EvaluationCriterion(id: UUID(), description: "New Criterion", weight: 0.0))
            }) {
                Text("Add Criterion")
            }
        }
        .padding()
    }
}

// MARK: - ParticipantsView

struct ParticipantsView: View {
    @Binding var participants: [Participant]
    
    var body: some View {
        Group {
            Text("Participants")
                .font(.title2)
            
            List($participants) { $participant in
                HStack {
                    Text(participant.name)
                    Spacer()
                    Text("Role: \(participant.role)")
                    Text("Status: \(participant.status.rawValue)")
                }
            }
            .onDelete { indexSet in
                participants.remove(atOffsets: indexSet)
            }
            Button(action: {
                participants.append(Participant(id: UUID(), name: "New Participant", role: "New Role", status: .pending))
            }) {
                Text("Add Participant")
            }
        }
        .padding()
    }
}

// MARK: - Preview

struct FieldExercisePlannerView_Previews: PreviewProvider {
    static var previews: some View {
        FieldExercisePlannerView()
    }
}