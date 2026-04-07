import SwiftUI
import Foundation
import CoreLocation
import ARKit
import AVFoundation

// MARK: - StressInoculationView

struct StressInoculationView: View {
    @StateObject private var viewModel = StressInoculationViewModel()
    
    var body: some View {
        VStack {
            Text("Stress Inoculation Trainer")
                .font(.largeTitle)
                .padding()
            
            Text("Current Level: \(viewModel.currentLevel)")
                .font(.title2)
                .padding()
            
            Button(action: {
                viewModel.startTraining()
            }) {
                Text("Start Training")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(viewModel.isTraining)
            
            if viewModel.isTraining {
                Text("Training in progress...")
                    .padding()
            }
        }
        .padding()
    }
}

// MARK: - StressInoculationViewModel

class StressInoculationViewModel: ObservableObject {
    @Published var currentLevel = 1
    @Published var isTraining = false
    
    private var timer: Timer?
    
    func startTraining() {
        isTraining = true
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.progressToNextLevel()
        }
    }
    
    func progressToNextLevel() {
        currentLevel += 1
        if currentLevel > 5 {
            stopTraining()
        }
    }
    
    func stopTraining() {
        isTraining = false
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - StressInoculationService

class StressInoculationService: ObservableObject {
    @Published var stressLevel: Int = 1
    
    func increaseStressLevel() {
        stressLevel += 1
        if stressLevel > 5 {
            stressLevel = 5
        }
    }
    
    func decreaseStressLevel() {
        stressLevel -= 1
        if stressLevel < 1 {
            stressLevel = 1
        }
    }
}

// MARK: - Preview

struct StressInoculationView_Previews: PreviewProvider {
    static var previews: some View {
        StressInoculationView()
    }
}