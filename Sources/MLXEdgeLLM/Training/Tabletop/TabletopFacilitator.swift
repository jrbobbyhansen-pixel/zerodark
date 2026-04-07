import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TabletopFacilitator

class TabletopFacilitator: ObservableObject {
    @Published var discussionPrompts: [String] = []
    @Published var decisionPoints: [String] = []
    @Published var currentTime: Date = Date()
    @Published var exerciseDuration: TimeInterval = 3600 // 1 hour
    @Published var isExerciseRunning: Bool = false
    
    private var timer: Timer?
    
    func startExercise() {
        isExerciseRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.currentTime = Date()
            if self?.currentTime.timeIntervalSince(self?.timer?.fireDate ?? Date()) ?? 0 >= self?.exerciseDuration ?? 0 {
                self?.stopExercise()
            }
        }
    }
    
    func stopExercise() {
        isExerciseRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func addDiscussionPrompt(_ prompt: String) {
        discussionPrompts.append(prompt)
    }
    
    func addDecisionPoint(_ point: String) {
        decisionPoints.append(point)
    }
}

// MARK: - TabletopFacilitatorView

struct TabletopFacilitatorView: View {
    @StateObject private var facilitator = TabletopFacilitator()
    
    var body: some View {
        VStack {
            Text("Tabletop Exercise Facilitator")
                .font(.largeTitle)
                .padding()
            
            HStack {
                Text("Current Time: \(facilitator.currentTime, formatter: dateFormatter)")
                Spacer()
                Button(action: {
                    facilitator.isExerciseRunning ? facilitator.stopExercise() : facilitator.startExercise()
                }) {
                    Text(facilitator.isExerciseRunning ? "Stop Exercise" : "Start Exercise")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            
            List {
                Section(header: Text("Discussion Prompts")) {
                    ForEach(facilitator.discussionPrompts, id: \.self) { prompt in
                        Text(prompt)
                    }
                }
                
                Section(header: Text("Decision Points")) {
                    ForEach(facilitator.decisionPoints, id: \.self) { point in
                        Text(point)
                    }
                }
            }
            .padding()
            
            Button(action: {
                facilitator.addDiscussionPrompt("New Discussion Prompt")
            }) {
                Text("Add Discussion Prompt")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
            
            Button(action: {
                facilitator.addDecisionPoint("New Decision Point")
            }) {
                Text("Add Decision Point")
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
    }
}

// MARK: - DateFormatter

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}()