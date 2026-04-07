import Foundation
import SwiftUI
import CoreLocation
import ARKit
import AVFoundation

// MARK: - BoatOperationsManager

class BoatOperationsManager: ObservableObject {
    @Published var crewAssignments: [String: String] = [:]
    @Published var fuelStatus: Double = 100.0
    @Published var maintenanceNeeded: Bool = false
    @Published var rescueCounts: Int = 0
    @Published var boatLocation: CLLocationCoordinate2D?
    @Published var arSession: ARSession = ARSession()
    @Published var audioPlayer: AVAudioPlayer?

    init() {
        setupAudioPlayer()
    }

    func setupAudioPlayer() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to load audio player: \(error)")
        }
    }

    func launchBoat() {
        // Logic to launch the boat
        print("Boat launched")
    }

    func recoverBoat() {
        // Logic to recover the boat
        print("Boat recovered")
    }

    func updateCrewAssignment(name: String, role: String) {
        crewAssignments[name] = role
    }

    func updateFuelStatus(amount: Double) {
        fuelStatus = max(0, min(100, fuelStatus + amount))
    }

    func checkMaintenance() {
        maintenanceNeeded = arc4random_uniform(2) == 0
    }

    func recordRescue() {
        rescueCounts += 1
        if rescueCounts >= 5 {
            audioPlayer?.play()
        }
    }
}

// MARK: - BoatOperationsView

struct BoatOperationsView: View {
    @StateObject private var manager = BoatOperationsManager()

    var body: some View {
        VStack {
            Text("Boat Operations")
                .font(.largeTitle)
                .padding()

            HStack {
                Text("Crew Assignments:")
                Spacer()
                Button(action: {
                    manager.updateCrewAssignment(name: "John Doe", role: "Captain")
                }) {
                    Text("Assign Captain")
                }
            }
            .padding()

            HStack {
                Text("Fuel Status: \(Int(manager.fuelStatus))%")
                Spacer()
                Button(action: {
                    manager.updateFuelStatus(amount: -10)
                }) {
                    Text("Consume Fuel")
                }
            }
            .padding()

            HStack {
                Text("Maintenance Needed: \(manager.maintenanceNeeded ? "Yes" : "No")")
                Spacer()
                Button(action: {
                    manager.checkMaintenance()
                }) {
                    Text("Check Maintenance")
                }
            }
            .padding()

            HStack {
                Text("Rescue Counts: \(manager.rescueCounts)")
                Spacer()
                Button(action: {
                    manager.recordRescue()
                }) {
                    Text("Record Rescue")
                }
            }
            .padding()

            HStack {
                Button(action: {
                    manager.launchBoat()
                }) {
                    Text("Launch Boat")
                }
                .padding()

                Button(action: {
                    manager.recoverBoat()
                }) {
                    Text("Recover Boat")
                }
                .padding()
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview

struct BoatOperationsView_Previews: PreviewProvider {
    static var previews: some View {
        BoatOperationsView()
    }
}