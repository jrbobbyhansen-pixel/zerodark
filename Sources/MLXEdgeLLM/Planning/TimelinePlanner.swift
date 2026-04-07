import SwiftUI
import Foundation
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TimelinePlanner

struct TimelinePlanner: View {
    @StateObject private var viewModel = TimelineViewModel()
    
    var body: some View {
        VStack {
            TimelineView(viewModel: viewModel)
                .padding()
            
            Button("Share Timeline") {
                viewModel.shareTimeline()
            }
            .padding()
        }
        .navigationTitle("Mission Timeline")
    }
}

// MARK: - TimelineViewModel

class TimelineViewModel: ObservableObject {
    @Published var phases: [MissionPhase] = []
    @Published var actualTimes: [String: Date] = [:]
    
    func addPhase(_ phase: MissionPhase) {
        phases.append(phase)
    }
    
    func updateActualTime(for phase: MissionPhase, to time: Date) {
        actualTimes[phase.name] = time
    }
    
    func shareTimeline() {
        // Implementation for sharing timeline via mesh
    }
}

// MARK: - MissionPhase

struct MissionPhase: Identifiable {
    let id = UUID()
    let name: String
    let startTime: Date
    let noLaterThan: Date
}

// MARK: - TimelineView

struct TimelineView: View {
    @ObservedObject var viewModel: TimelineViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(viewModel.phases) { phase in
                    MissionPhaseView(phase: phase, actualTime: viewModel.actualTimes[phase.name])
                        .padding()
                }
            }
        }
    }
}

// MARK: - MissionPhaseView

struct MissionPhaseView: View {
    let phase: MissionPhase
    let actualTime: Date?
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(phase.name)
                .font(.headline)
            
            HStack {
                Text("Start Time: \(phase.startTime, formatter: dateFormatter)")
                Text("No Later Than: \(phase.noLaterThan, formatter: dateFormatter)")
            }
            
            if let actualTime = actualTime {
                Text("Actual Time: \(actualTime, formatter: dateFormatter)")
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - DateFormatter

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()