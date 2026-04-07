import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - AARBuilder

class AARBuilder: ObservableObject {
    @Published var timeline: [MissionEvent] = []
    @Published var decisions: [Decision] = []
    @Published var outcomes: [Outcome] = []
    @Published var lessonsLearned: [String] = []

    func buildAAR() -> AfterActionReport {
        return AfterActionReport(
            timeline: timeline,
            decisions: decisions,
            outcomes: outcomes,
            lessonsLearned: lessonsLearned
        )
    }

    func exportToPDF() {
        // Implementation for exporting AAR to PDF
    }

    func exportToMarkdown() {
        // Implementation for exporting AAR to Markdown
    }
}

// MARK: - MissionEvent

struct MissionEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let description: String
    let location: CLLocationCoordinate2D?
}

// MARK: - Decision

struct Decision: Identifiable {
    let id = UUID()
    let timestamp: Date
    let decision: String
    let rationale: String
}

// MARK: - Outcome

struct Outcome: Identifiable {
    let id = UUID()
    let timestamp: Date
    let outcome: String
    let impact: String
}

// MARK: - AfterActionReport

struct AfterActionReport: Identifiable {
    let id = UUID()
    let timeline: [MissionEvent]
    let decisions: [Decision]
    let outcomes: [Outcome]
    let lessonsLearned: [String]
}

// MARK: - AARView

struct AARView: View {
    @StateObject private var aarBuilder = AARBuilder()

    var body: some View {
        VStack {
            List(aarBuilder.timeline) { event in
                Text("\(event.timestamp): \(event.description)")
            }
            .navigationTitle("After Action Report")
        }
        .environmentObject(aarBuilder)
    }
}

// MARK: - Preview

struct AARView_Previews: PreviewProvider {
    static var previews: some View {
        AARView()
    }
}