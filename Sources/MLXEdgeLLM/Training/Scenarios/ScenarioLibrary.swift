import Foundation
import SwiftUI
import CoreLocation

// MARK: - Scenario Types
enum ScenarioType: String, CaseIterable {
    case SAR = "Search and Rescue"
    case fire = "Fire"
    case MCI = "Mass Casualty Incident"
}

// MARK: - Difficulty Levels
enum DifficultyLevel: String, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

// MARK: - Scenario
struct Scenario: Identifiable {
    let id = UUID()
    let name: String
    let type: ScenarioType
    let difficulty: DifficultyLevel
    let description: String
    let location: CLLocationCoordinate2D
    let duration: TimeInterval
    let objectives: [String]
    let resources: [String]
}

// MARK: - Scenario Library
class ScenarioLibrary: ObservableObject {
    @Published var scenarios: [Scenario] = [
        Scenario(
            name: "Mountain Rescue",
            type: .SAR,
            difficulty: .intermediate,
            description: "A climber is lost in the mountains. Locate and rescue the climber.",
            location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            duration: 3600, // 1 hour
            objectives: ["Locate the climber", "Ensure the climber is safe"],
            resources: ["First aid kit", "Satellite phone"]
        ),
        Scenario(
            name: "Forest Fire",
            type: .fire,
            difficulty: .advanced,
            description: "A forest fire is raging. Contain the fire and rescue any trapped individuals.",
            location: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),
            duration: 7200, // 2 hours
            objectives: ["Contain the fire", "Rescue trapped individuals"],
            resources: ["Fire extinguisher", "Water hose"]
        ),
        Scenario(
            name: "City Crash",
            type: .MCI,
            difficulty: .beginner,
            description: "A bus has crashed in the city. Rescue the passengers and provide medical assistance.",
            location: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            duration: 1800, // 30 minutes
            objectives: ["Rescue passengers", "Provide medical assistance"],
            resources: ["Ambulance", "First aid kit"]
        )
    ]
    
    func addScenario(_ scenario: Scenario) {
        scenarios.append(scenario)
    }
    
    func removeScenario(_ scenario: Scenario) {
        scenarios.removeAll { $0.id == scenario.id }
    }
}

// MARK: - Scenario View Model
class ScenarioViewModel: ObservableObject {
    @Published var selectedScenario: Scenario?
    
    func selectScenario(_ scenario: Scenario) {
        selectedScenario = scenario
    }
}

// MARK: - Scenario List View
struct ScenarioListView: View {
    @StateObject private var viewModel = ScenarioViewModel()
    @EnvironmentObject private var scenarioLibrary: ScenarioLibrary
    
    var body: some View {
        NavigationView {
            List(scenarioLibrary.scenarios) { scenario in
                Button(action: {
                    viewModel.selectScenario(scenario)
                }) {
                    VStack(alignment: .leading) {
                        Text(scenario.name)
                            .font(.headline)
                        Text(scenario.type.rawValue)
                            .font(.subheadline)
                        Text(scenario.difficulty.rawValue)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Scenarios")
            .sheet(item: $viewModel.selectedScenario) { scenario in
                ScenarioDetailView(scenario: scenario)
            }
        }
    }
}

// MARK: - Scenario Detail View
struct ScenarioDetailView: View {
    let scenario: Scenario
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(scenario.name)
                .font(.largeTitle)
                .padding()
            
            Text(scenario.description)
                .padding()
            
            Text("Location: \(scenario.location.latitude), \(scenario.location.longitude)")
                .padding()
            
            Text("Duration: \(scenario.duration.formatted(.hour().minute()))")
                .padding()
            
            Text("Objectives:")
                .font(.headline)
                .padding()
            
            ForEach(scenario.objectives, id: \.self) { objective in
                Text("- \(objective)")
                    .padding(.leading)
            }
            
            Text("Resources:")
                .font(.headline)
                .padding()
            
            ForEach(scenario.resources, id: \.self) { resource in
                Text("- \(resource)")
                    .padding(.leading)
            }
        }
        .navigationTitle(scenario.name)
    }
}

// MARK: - Preview
struct ScenarioListView_Previews: PreviewProvider {
    static var previews: some View {
        ScenarioListView()
            .environmentObject(ScenarioLibrary())
    }
}