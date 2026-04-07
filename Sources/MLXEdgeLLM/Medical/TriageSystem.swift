import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - TriageSystem

class TriageSystem: ObservableObject {
    @Published var casualties: [Casualty] = []
    @Published var immediateCount: Int = 0
    @Published var delayedCount: Int = 0
    @Published var minorCount: Int = 0
    @Published var expectantCount: Int = 0

    func tagCasualty(_ casualty: Casualty, as status: TriageStatus) {
        if let index = casualties.firstIndex(where: { $0.id == casualty.id }) {
            casualties[index].status = status
            updateCounts()
        }
    }

    func updateCounts() {
        immediateCount = casualties.filter { $0.status == .immediate }.count
        delayedCount = casualties.filter { $0.status == .delayed }.count
        minorCount = casualties.filter { $0.status == .minor }.count
        expectantCount = casualties.filter { $0.status == .expectant }.count
    }

    func generateMETHANEReport() -> String {
        return """
        METHANE Report:
        Immediate: \(immediateCount)
        Delayed: \(delayedCount)
        Minor: \(minorCount)
        Expectant: \(expectantCount)
        """
    }
}

// MARK: - Casualty

struct Casualty: Identifiable {
    let id: UUID
    var status: TriageStatus
}

// MARK: - TriageStatus

enum TriageStatus {
    case immediate
    case delayed
    case minor
    case expectant
}

// MARK: - TriageView

struct TriageView: View {
    @StateObject private var triageSystem = TriageSystem()

    var body: some View {
        VStack {
            Text("Triage System")
                .font(.largeTitle)
                .padding()

            List(triageSystem.casualties) { casualty in
                HStack {
                    Text(casualty.id.uuidString)
                    Spacer()
                    Text(casualty.status.rawValue.capitalized)
                }
            }

            HStack {
                Text("Immediate: \(triageSystem.immediateCount)")
                Text("Delayed: \(triageSystem.delayedCount)")
                Text("Minor: \(triageSystem.minorCount)")
                Text("Expectant: \(triageSystem.expectantCount)")
            }
            .padding()

            Button(action: {
                let newCasualty = Casualty(id: UUID(), status: .immediate)
                triageSystem.casualties.append(newCasualty)
            }) {
                Text("Add Casualty")
            }
            .padding()

            Button(action: {
                let report = triageSystem.generateMETHANEReport()
                print(report)
            }) {
                Text("Generate Report")
            }
            .padding()
        }
    }
}

// MARK: - Preview

struct TriageView_Previews: PreviewProvider {
    static var previews: some View {
        TriageView()
    }
}