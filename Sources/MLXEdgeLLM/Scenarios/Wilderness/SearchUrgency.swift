import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - SearchUrgencyCalculator

class SearchUrgencyCalculator: ObservableObject {
    @Published var urgencyLevel: UrgencyLevel = .low
    @Published var timeMissing: TimeInterval = 0
    @Published var weatherConditions: WeatherConditions = .clear
    @Published var terrainType: TerrainType = .flat
    @Published var subjectProfile: SubjectProfile = .adult
    
    func calculateUrgency() {
        let baseUrgency = calculateBaseUrgency()
        let weatherFactor = calculateWeatherFactor()
        let terrainFactor = calculateTerrainFactor()
        let profileFactor = calculateProfileFactor()
        
        let totalUrgency = baseUrgency + weatherFactor + terrainFactor + profileFactor
        
        urgencyLevel = UrgencyLevel(from: totalUrgency)
    }
    
    private func calculateBaseUrgency() -> Double {
        return timeMissing / 3600.0 // Convert time missing to hours
    }
    
    private func calculateWeatherFactor() -> Double {
        switch weatherConditions {
        case .clear: return 0.0
        case .rainy: return 0.5
        case .stormy: return 1.0
        }
    }
    
    private func calculateTerrainFactor() -> Double {
        switch terrainType {
        case .flat: return 0.0
        case .hilly: return 0.5
        case .mountainous: return 1.0
        }
    }
    
    private func calculateProfileFactor() -> Double {
        switch subjectProfile {
        case .child: return 1.0
        case .adult: return 0.5
        case .elderly: return 0.75
        }
    }
}

// MARK: - UrgencyLevel

enum UrgencyLevel: Comparable {
    case low
    case medium
    case high
    case critical
    
    init(from value: Double) {
        switch value {
        case 0...2: self = .low
        case 2...4: self = .medium
        case 4...6: self = .high
        default: self = .critical
        }
    }
}

// MARK: - WeatherConditions

enum WeatherConditions {
    case clear
    case rainy
    case stormy
}

// MARK: - TerrainType

enum TerrainType {
    case flat
    case hilly
    case mountainous
}

// MARK: - SubjectProfile

enum SubjectProfile {
    case child
    case adult
    case elderly
}

// MARK: - SearchUrgencyView

struct SearchUrgencyView: View {
    @StateObject private var calculator = SearchUrgencyCalculator()
    
    var body: some View {
        VStack {
            Text("Search Urgency Calculator")
                .font(.largeTitle)
                .padding()
            
            HStack {
                Text("Time Missing (hours):")
                TextField("0", value: $calculator.timeMissing, formatter: NumberFormatter())
                    .keyboardType(.decimalPad)
                    .padding()
            }
            .padding()
            
            Picker("Weather Conditions", selection: $calculator.weatherConditions) {
                ForEach(WeatherConditions.allCases, id: \.self) { condition in
                    Text(condition.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Picker("Terrain Type", selection: $calculator.terrainType) {
                ForEach(TerrainType.allCases, id: \.self) { terrain in
                    Text(terrain.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Picker("Subject Profile", selection: $calculator.subjectProfile) {
                ForEach(SubjectProfile.allCases, id: \.self) { profile in
                    Text(profile.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Button("Calculate Urgency") {
                calculator.calculateUrgency()
            }
            .padding()
            
            Text("Urgency Level: \(calculator.urgencyLevel.rawValue.capitalized)")
                .font(.title2)
                .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct SearchUrgencyView_Previews: PreviewProvider {
    static var previews: some View {
        SearchUrgencyView()
    }
}