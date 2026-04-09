import Foundation
import SwiftUI

// MARK: - RiskAssessor

class RiskAssessor: ObservableObject {
    @Published var riskScore: Double = 0.0
    @Published var mitigationRecommendations: [String] = []

    func evaluateRisk(terrain: Terrain, weather: Weather, teamStatus: TeamStatus, timePressure: TimePressure) {
        let terrainRisk = terrain.riskFactor
        let weatherRisk = weather.riskFactor
        let teamRisk = teamStatus.riskFactor
        let timeRisk = timePressure.riskFactor

        riskScore = (terrainRisk + weatherRisk + teamRisk + timeRisk) / 4.0

        mitigationRecommendations = []
        if terrainRisk > 0.5 {
            mitigationRecommendations.append("Consider alternative routes to avoid high-risk terrain.")
        }
        if weatherRisk > 0.5 {
            mitigationRecommendations.append("Check for weather updates and prepare accordingly.")
        }
        if teamRisk > 0.5 {
            mitigationRecommendations.append("Ensure all team members are well-rested and equipped.")
        }
        if timeRisk > 0.5 {
            mitigationRecommendations.append("Plan for contingencies and allocate additional time for critical tasks.")
        }
    }
}

// MARK: - Terrain

struct Terrain {
    let type: String
    let elevation: Double
    let slope: Double

    var riskFactor: Double {
        // Example risk factor calculation
        return (elevation / 1000.0) + (slope / 10.0)
    }
}

// MARK: - Weather

struct Weather {
    let condition: String
    let temperature: Double
    let windSpeed: Double

    var riskFactor: Double {
        // Example risk factor calculation
        return (temperature / 30.0) + (windSpeed / 20.0)
    }
}

// MARK: - TeamStatus

struct TeamStatus {
    let numberOfMembers: Int
    let morale: Double
    let equipmentStatus: [String: Bool]

    var riskFactor: Double {
        let brokenCount = Double(equipmentStatus.filter { !$0.value }.count)
        let memberCount = Double(max(numberOfMembers, 1))
        return (1.0 - morale) + (brokenCount / memberCount)
    }
}

// MARK: - TimePressure

struct TimePressure {
    let deadline: Date
    let currentTime: Date

    var riskFactor: Double {
        // Example risk factor calculation
        let timeRemaining = deadline.timeIntervalSince(currentTime)
        return 1.0 - (timeRemaining / 3600.0) // Assuming 1 hour is the maximum time pressure
    }
}

// MARK: - RiskAssessorView

struct RiskAssessorView: View {
    @StateObject private var riskAssessor = RiskAssessor()
    @State private var terrain = Terrain(type: "Mountain", elevation: 2000.0, slope: 30.0)
    @State private var weather = Weather(condition: "Rain", temperature: 15.0, windSpeed: 10.0)
    @State private var teamStatus = TeamStatus(numberOfMembers: 5, morale: 0.8, equipmentStatus: ["gun": true, "ammo": false])
    @State private var timePressure = TimePressure(deadline: Date().addingTimeInterval(3600), currentTime: Date())

    var body: some View {
        VStack {
            Text("Risk Score: \(riskAssessor.riskScore, specifier: "%.2f")")
                .font(.largeTitle)
                .padding()

            Text("Mitigation Recommendations:")
                .font(.title2)
                .padding()

            ForEach(riskAssessor.mitigationRecommendations, id: \.self) { recommendation in
                Text("- \(recommendation)")
                    .padding(.leading)
            }

            Button("Evaluate Risk") {
                riskAssessor.evaluateRisk(terrain: terrain, weather: weather, teamStatus: teamStatus, timePressure: timePressure)
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}

// MARK: - Preview

struct RiskAssessorView_Previews: PreviewProvider {
    static var previews: some View {
        RiskAssessorView()
    }
}