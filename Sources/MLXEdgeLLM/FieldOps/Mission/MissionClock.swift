import SwiftUI
import Foundation
import AVFoundation
import CoreLocation

// MARK: - MissionClock

class MissionClock: ObservableObject {
    @Published var currentTime: Date = Date()
    @Published var missionStartDate: Date?
    @Published var missionEndDate: Date?
    @Published var phaseTimers: [String: TimeInterval] = [:]
    @Published var currentPhase: String?
    @Published var isCountdownActive: Bool = false
    @Published var isPhaseActive: Bool = false
    
    private var countdownTimer: Timer?
    private var phaseTimer: Timer?
    private let audioPlayer = try? AVAudioPlayer(data: Data(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "alert", ofType: "mp3")!)))
    
    init() {
        audioPlayer?.prepareToPlay()
    }
    
    func startMission(startDate: Date, endDate: Date) {
        missionStartDate = startDate
        missionEndDate = endDate
        isCountdownActive = true
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
            if self?.currentTime >= self?.missionEndDate ?? Date() {
                self?.stopMission()
                self?.playAlert()
            }
        }
    }
    
    func stopMission() {
        isCountdownActive = false
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    func startPhase(phase: String, duration: TimeInterval) {
        currentPhase = phase
        phaseTimers[phase] = duration
        isPhaseActive = true
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePhaseTime()
            if self?.phaseTimers[phase] == 0 {
                self?.stopPhase()
                self?.playAlert()
            }
        }
    }
    
    func stopPhase() {
        isPhaseActive = false
        phaseTimer?.invalidate()
        phaseTimer = nil
    }
    
    private func updateCurrentTime() {
        currentTime = Date()
    }
    
    private func updatePhaseTime() {
        if let currentPhase = currentPhase, let duration = phaseTimers[currentPhase] {
            phaseTimers[currentPhase] = max(0, duration - 1)
        }
    }
    
    private func playAlert() {
        audioPlayer?.play()
    }
}

// MARK: - MissionClockView

struct MissionClockView: View {
    @StateObject private var viewModel = MissionClock()
    
    var body: some View {
        VStack {
            Text("Mission Clock")
                .font(.largeTitle)
                .padding()
            
            Text(viewModel.currentTime, style: .time)
                .font(.title)
                .padding()
            
            if let missionStartDate = viewModel.missionStartDate, let missionEndDate = viewModel.missionEndDate {
                Text("Mission Start: \(missionStartDate, style: .date)")
                    .font(.subheadline)
                Text("Mission End: \(missionEndDate, style: .date)")
                    .font(.subheadline)
            }
            
            if viewModel.isCountdownActive {
                Text("Mission Countdown Active")
                    .font(.headline)
                    .padding()
            }
            
            if let currentPhase = viewModel.currentPhase {
                Text("Current Phase: \(currentPhase)")
                    .font(.headline)
                    .padding()
                
                if let duration = viewModel.phaseTimers[currentPhase] {
                    Text("Time Left: \(Int(duration)) seconds")
                        .font(.subheadline)
                        .padding()
                }
            }
            
            if viewModel.isPhaseActive {
                Text("Phase Active")
                    .font(.headline)
                    .padding()
            }
            
            Button("Start Mission") {
                viewModel.startMission(startDate: Date(), endDate: Date().addingTimeInterval(3600)) // 1 hour mission
            }
            .padding()
            
            Button("Stop Mission") {
                viewModel.stopMission()
            }
            .padding()
            
            Button("Start Phase A") {
                viewModel.startPhase(phase: "A", duration: 60) // 1 minute phase
            }
            .padding()
            
            Button("Stop Phase") {
                viewModel.stopPhase()
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct MissionClockView_Previews: PreviewProvider {
    static var previews: some View {
        MissionClockView()
    }
}