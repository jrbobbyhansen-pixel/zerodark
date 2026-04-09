import Foundation
import SwiftUI

// MARK: - Probability of Detection Calculator

class PodCalculator: ObservableObject {
    @Published var searchType: SearchType = .visual
    @Published var terrain: TerrainType = .flat
    @Published var coverage: CoverageType = .partial
    @Published var searcherSkill: SearcherSkillLevel = .average
    @Published var cumulativePOD: Double = 0.0

    func calculatePOD() {
        let basePOD = baseProbabilityOfDetection()
        let terrainModifier = terrainModifier()
        let coverageModifier = coverageModifier()
        let skillModifier = skillModifier()

        cumulativePOD = basePOD * terrainModifier * coverageModifier * skillModifier
    }

    private func baseProbabilityOfDetection() -> Double {
        switch searchType {
        case .visual: return 0.7
        case .audio: return 0.5
        case .thermal: return 0.8
        }
    }

    private func terrainModifier() -> Double {
        switch terrain {
        case .flat: return 1.0
        case .hilly: return 0.8
        case .mountainous: return 0.5
        }
    }

    private func coverageModifier() -> Double {
        switch coverage {
        case .partial: return 0.6
        case .full: return 1.0
        }
    }

    private func skillModifier() -> Double {
        switch searcherSkill {
        case .beginner: return 0.7
        case .average: return 1.0
        case .advanced: return 1.3
        }
    }
}

// MARK: - Types

enum SearchType {
    case visual
    case audio
    case thermal
}

enum TerrainType {
    case flat
    case hilly
    case mountainous
}

enum CoverageType {
    case partial
    case full
}

enum SearcherSkillLevel {
    case beginner
    case average
    case advanced
}

// MARK: - SwiftUI View

struct PodCalculatorView: View {
    @StateObject private var podCalculator = PodCalculator()

    var body: some View {
        VStack {
            Text("Probability of Detection Calculator")
                .font(.largeTitle)
                .padding()

            Picker("Search Type", selection: $podCalculator.searchType) {
                ForEach(SearchType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Picker("Terrain", selection: $podCalculator.terrain) {
                ForEach(TerrainType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Picker("Coverage", selection: $podCalculator.coverage) {
                ForEach(CoverageType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Picker("Searcher Skill", selection: $podCalculator.searcherSkill) {
                ForEach(SearcherSkillLevel.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Button("Calculate POD") {
                podCalculator.calculatePOD()
            }
            .padding()

            Text("Cumulative POD: \(String(format: "%.2f", podCalculator.cumulativePOD))")
                .font(.title2)
                .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct PodCalculatorView_Previews: PreviewProvider {
    static var previews: some View {
        PodCalculatorView()
    }
}