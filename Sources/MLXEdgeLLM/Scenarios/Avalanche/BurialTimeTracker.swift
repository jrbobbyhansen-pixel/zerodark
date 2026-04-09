import Foundation
import SwiftUI
import CoreLocation

// MARK: - BurialTimeTracker

class BurialTimeTracker: ObservableObject {
    @Published var victims: [Victim] = []
    @Published var criticalThreshold: TimeInterval = 3600 // 1 hour
    @Published var priorityAdjustments: [Victim: Int] = [:]
    
    private var timer: Timer?
    
    init() {
        startTracking()
    }
    
    deinit {
        stopTracking()
    }
    
    func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateBurialTimes()
        }
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
    }
    
    func addVictim(location: CLLocationCoordinate2D) {
        let victim = Victim(location: location)
        victims.append(victim)
    }
    
    func removeVictim(victim: Victim) {
        if let index = victims.firstIndex(of: victim) {
            victims.remove(at: index)
        }
    }
    
    private func updateBurialTimes() {
        for victim in victims {
            victim.burialTime += 1
            if victim.burialTime >= criticalThreshold {
                notifyCriticalThreshold(victim: victim)
            }
        }
    }
    
    private func notifyCriticalThreshold(victim: Victim) {
        // Implement notification logic here
        print("Critical threshold reached for victim at \(victim.location)")
    }
}

// MARK: - Victim

struct Victim: Identifiable, Equatable {
    let id = UUID()
    var location: CLLocationCoordinate2D
    var burialTime: TimeInterval = 0
}

// MARK: - BurialTimeTrackerView

struct BurialTimeTrackerView: View {
    @StateObject private var tracker = BurialTimeTracker()
    
    var body: some View {
        VStack {
            List(tracker.victims) { victim in
                HStack {
                    Text("Victim \(victim.id.uuidString.prefix(5))")
                    Spacer()
                    Text("Burial Time: \(String(format: "%.0f", victim.burialTime))s")
                }
            }
            Button(action: {
                tracker.addVictim(location: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
            }) {
                Text("Add Victim")
            }
        }
        .padding()
        .onAppear {
            tracker.startTracking()
        }
        .onDisappear {
            tracker.stopTracking()
        }
    }
}

// MARK: - Preview

struct BurialTimeTrackerView_Previews: PreviewProvider {
    static var previews: some View {
        BurialTimeTrackerView()
    }
}