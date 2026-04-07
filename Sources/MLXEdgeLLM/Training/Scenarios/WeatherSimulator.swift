import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - Weather Condition Types

enum WeatherCondition: String, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case rainy
    case snowy
    case stormy
}

// MARK: - WeatherSimulator

class WeatherSimulator: ObservableObject {
    @Published var currentCondition: WeatherCondition = .clear
    @Published var historicalConditions: [WeatherCondition] = []
    
    private var timer: Timer?
    
    init() {
        startSimulation()
    }
    
    deinit {
        stopSimulation()
    }
    
    func startSimulation() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.simulateWeatherChange()
        }
    }
    
    func stopSimulation() {
        timer?.invalidate()
        timer = nil
    }
    
    private func simulateWeatherChange() {
        let allConditions = WeatherCondition.allCases
        let nextIndex = (allConditions.firstIndex(of: currentCondition)! + 1) % allConditions.count
        currentCondition = allConditions[nextIndex]
        historicalConditions.append(currentCondition)
    }
    
    func replayHistoricalWeather() {
        guard !historicalConditions.isEmpty else { return }
        
        var index = 0
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if index < self.historicalConditions.count {
                self.currentCondition = self.historicalConditions[index]
                index += 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - WeatherView

struct WeatherView: View {
    @StateObject private var weatherSimulator = WeatherSimulator()
    
    var body: some View {
        VStack {
            Text("Current Weather: \(weatherSimulator.currentCondition.rawValue.capitalized)")
                .font(.largeTitle)
                .padding()
            
            Button(action: {
                weatherSimulator.startSimulation()
            }) {
                Text("Start Simulation")
            }
            .padding()
            
            Button(action: {
                weatherSimulator.stopSimulation()
            }) {
                Text("Stop Simulation")
            }
            .padding()
            
            Button(action: {
                weatherSimulator.replayHistoricalWeather()
            }) {
                Text("Replay Historical Weather")
            }
            .padding()
        }
        .onAppear {
            weatherSimulator.startSimulation()
        }
        .onDisappear {
            weatherSimulator.stopSimulation()
        }
    }
}

// MARK: - Preview

struct WeatherView_Previews: PreviewProvider {
    static var previews: some View {
        WeatherView()
    }
}