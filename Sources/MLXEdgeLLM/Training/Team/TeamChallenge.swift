import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TeamChallenge

struct TeamChallenge {
    let id: UUID
    let name: String
    let description: String
    let startTime: Date
    let duration: TimeInterval
    let tasks: [Task]
}

// MARK: - Task

struct Task {
    let id: UUID
    let name: String
    let description: String
    let location: CLLocationCoordinate2D
    let requiredItems: [String]
    let completionCriteria: String
}

// MARK: - TeamChallengeViewModel

class TeamChallengeViewModel: ObservableObject {
    @Published var challenges: [TeamChallenge] = []
    @Published var selectedChallenge: TeamChallenge?
    @Published var isChallengeActive = false
    @Published var currentTime: Date = Date()
    
    private var timer: Timer?
    
    init() {
        loadChallenges()
    }
    
    func loadChallenges() {
        // Simulate loading challenges from a data source
        challenges = [
            TeamChallenge(
                id: UUID(),
                name: "Operation Swift Strike",
                description: "Complete all tasks within the time limit to secure victory.",
                startTime: Date().addingTimeInterval(60), // 1 minute from now
                duration: 300, // 5 minutes
                tasks: [
                    Task(
                        id: UUID(),
                        name: "Task 1: Reconnaissance",
                        description: "Locate the enemy base and report back.",
                        location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                        requiredItems: ["Binoculars"],
                        completionCriteria: "Enemy base located"
                    ),
                    Task(
                        id: UUID(),
                        name: "Task 2: Sabotage",
                        description: "Disable the enemy communication system.",
                        location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                        requiredItems: ["Explosives"],
                        completionCriteria: "Communication system disabled"
                    )
                ]
            )
        ]
    }
    
    func startChallenge(_ challenge: TeamChallenge) {
        selectedChallenge = challenge
        isChallengeActive = true
        currentTime = challenge.startTime
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.currentTime = Date()
        }
    }
    
    func stopChallenge() {
        isChallengeActive = false
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - TeamChallengeView

struct TeamChallengeView: View {
    @StateObject private var viewModel = TeamChallengeViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.challenges) { challenge in
                NavigationLink(destination: ChallengeDetailView(challenge: challenge)) {
                    VStack(alignment: .leading) {
                        Text(challenge.name)
                            .font(.headline)
                        Text(challenge.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Team Challenges")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Add new challenge
                    }) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
    }
}

// MARK: - ChallengeDetailView

struct ChallengeDetailView: View {
    let challenge: TeamChallenge
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(challenge.name)
                .font(.largeTitle)
                .padding(.bottom)
            
            Text(challenge.description)
                .font(.body)
                .padding(.bottom)
            
            Text("Start Time: \(challenge.startTime, style: .date)")
                .font(.subheadline)
                .padding(.bottom)
            
            Text("Duration: \(Int(challenge.duration)) seconds")
                .font(.subheadline)
                .padding(.bottom)
            
            List(challenge.tasks) { task in
                VStack(alignment: .leading) {
                    Text(task.name)
                        .font(.headline)
                    Text(task.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Tasks")
        }
        .padding()
    }
}

// MARK: - Preview

struct TeamChallengeView_Previews: PreviewProvider {
    static var previews: some View {
        TeamChallengeView()
    }
}